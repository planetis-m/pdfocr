import std/[json, os, monotimes]
import threading/channels
import ./[config, output_format, types]

type
  OutputContext* = object
    outputDir*: string
    inputFile*: string
    pageStartUser*: int
    pageEndUser*: int
    config*: Config
    outputChan*: Chan[OutputMessage]
    summaryChan*: Chan[OutputSummary]

proc runOutputWriter*(ctx: OutputContext) {.thread.} =
  createDir(ctx.outputDir)
  let runStartUnixMs = nowUnixMs()
  let runStartMono = getMonoTime()

  var manifest = RunManifest(
    inputFile: ctx.inputFile,
    inputChecksum: "",
    pageStartUser: ctx.pageStartUser,
    pageEndUser: ctx.pageEndUser,
    config: ctx.config,
    pages: @[],
    startedAtUnixMs: runStartUnixMs,
    finishedAtUnixMs: 0
  )

  var summary = OutputSummary(successCount: 0, failureCount: 0, totalCount: 0)
  var jsonlFile: File
  if ctx.config.outputFormat == ofJsonl:
    if not open(jsonlFile, jsonlPath(ctx.outputDir), fmWrite):
      raise newException(IOError, "Failed to open JSONL output file.")

  var msg: OutputMessage
  while true:
    ctx.outputChan.recv(msg)
    case msg.kind
    of omPageResult:
      let res = msg.result
      let meta = PageSummary(
        pageId: res.pageId,
        pageNumberUser: res.pageNumberUser,
        status: res.status,
        attemptCount: res.attemptCount,
        errorKind: if res.status == rsFailure: $res.errorKind else: "",
        httpStatus: res.httpStatus
      )
      manifest.pages.add(meta)
      summary.totalCount.inc
      if res.status == rsSuccess:
        summary.successCount.inc
      else:
        summary.failureCount.inc

      if ctx.config.outputFormat == ofJsonl:
        let node = resultToJson(res, runStartMono)
        jsonlFile.writeLine($node)
      else:
        let textPath = pageTextPath(ctx.outputDir, res.pageNumberUser)
        let metaPath = pageMetaPath(ctx.outputDir, res.pageNumberUser)
        writeFile(textPath, res.text)
        let metaNode = resultToMetadataJson(res, runStartMono)
        writeFile(metaPath, pretty(metaNode))
    of omOutputDone:
      break

  if ctx.config.outputFormat == ofJsonl:
    close(jsonlFile)

  manifest.finishedAtUnixMs = nowUnixMs()
  let manifestNode = manifestToJson(manifest)
  writeFile(manifestPath(ctx.outputDir), pretty(manifestNode))

  ctx.summaryChan.send(summary)
