import std/[algorithm, json, os, strformat, tables, monotimes]
import threading/channels
import ./[config, logging, output_format, types]

type
  OutputContext* = object
    outputDir*: string
    inputFile*: string
    pageStartUser*: int
    pageEndUser*: int
    config*: Config
    outputChan*: Chan[OutputMessage]
    summaryChan*: Chan[OutputSummary]

proc writeResult(outputDir: string; cfg: Config; jsonlFile: var File; res: Result; base: MonoTime) =
  if cfg.outputFormat == ofJsonl:
    let node = resultToJson(res, base)
    jsonlFile.writeLine($node)
  else:
    let textPath = pageTextPath(outputDir, res.pageNumberUser)
    let metaPath = pageMetaPath(outputDir, res.pageNumberUser)
    writeFile(textPath, res.text)
    let metaNode = resultToMetadataJson(res, base)
    writeFile(metaPath, pretty(metaNode))

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
    if not open(jsonlFile, jsonlPath(ctx.outputDir), fmAppend):
      raise newException(IOError, "Failed to open JSONL output file.")

  var pendingOrdered = initTable[int, Result]()
  var nextExpected = 0
  let expectedTotal = max(0, ctx.pageEndUser - ctx.pageStartUser + 1)
  var seen = newSeq[bool](expectedTotal)
  var receivedCount = 0

  proc recordResult(res: Result) =
    if res.pageId < 0 or res.pageId >= expectedTotal:
      logError(&"result out of range page_id={res.pageId} expected=0..{expectedTotal - 1}")
    else:
      if seen[res.pageId]:
        logError(&"duplicate result for page_id={res.pageId}")
      else:
        seen[res.pageId] = true
        receivedCount.inc
    manifest.pages.add(PageSummary(
      pageId: res.pageId,
      pageNumberUser: res.pageNumberUser,
      status: res.status,
      attemptCount: res.attemptCount,
      errorKind: if res.status == rsFailure: $res.errorKind else: "",
      httpStatus: res.httpStatus
    ))
    summary.totalCount.inc
    if res.status == rsSuccess:
      summary.successCount.inc
    else:
      summary.failureCount.inc

  proc flushOrdered() =
    while pendingOrdered.hasKey(nextExpected):
      let res = pendingOrdered[nextExpected]
      pendingOrdered.del(nextExpected)
      writeResult(ctx.outputDir, ctx.config, jsonlFile, res, runStartMono)
      recordResult(res)
      inc nextExpected

  var msg: OutputMessage
  while true:
    ctx.outputChan.recv(msg)
    case msg.kind
    of omPageResult:
      let res = msg.result
      if ctx.config.orderingMode == omInputOrder:
        pendingOrdered[res.pageId] = res
        flushOrdered()
      else:
        writeResult(ctx.outputDir, ctx.config, jsonlFile, res, runStartMono)
        recordResult(res)
    of omOutputDone:
      break

  if ctx.config.orderingMode == omInputOrder and pendingOrdered.len > 0:
    var keys = newSeq[int](pendingOrdered.len)
    var i = 0
    for k in pendingOrdered.keys:
      keys[i] = k
      inc i
    keys.sort()
    for k in keys:
      let res = pendingOrdered[k]
      writeResult(ctx.outputDir, ctx.config, jsonlFile, res, runStartMono)
      recordResult(res)

  if ctx.config.outputFormat == ofJsonl:
    close(jsonlFile)

  if receivedCount != expectedTotal:
    let missing = expectedTotal - receivedCount
    if missing > 0:
      logError(&"missing results count={missing} expected={expectedTotal} received={receivedCount}")
      summary.failureCount.inc(missing)

  manifest.finishedAtUnixMs = nowUnixMs()
  let manifestNode = manifestToJson(manifest)
  writeFile(manifestPath(ctx.outputDir), pretty(manifestNode))

  ctx.summaryChan.send(summary)
