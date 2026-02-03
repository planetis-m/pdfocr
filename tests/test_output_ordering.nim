import std/[json, os, strutils]
import threading/channels
import pdfocr/[config, output_writer, types]

proc main() =
  let tmpDir = getTempDir().joinPath("pdfocr_ordering_test")
  if dirExists(tmpDir):
    removeDir(tmpDir)
  createDir(tmpDir)

  var cfg = defaultConfig()
  cfg.outputFormat = ofJsonl
  cfg.orderingMode = omInputOrder

  let outputChan = newChan[OutputMessage](Positive(10))
  let summaryChan = newChan[OutputSummary](Positive(1))

  var th: Thread[OutputContext]
  let ctx = OutputContext(
    outputDir: tmpDir,
    inputFile: "input.pdf",
    pageStartUser: 1,
    pageEndUser: 2,
    config: cfg,
    outputChan: outputChan,
    summaryChan: summaryChan
  )
  createThread(th, runOutputWriter, ctx)

  outputChan.send(OutputMessage(
    kind: omPageResult,
    result: Result(pageId: 1, pageNumberUser: 2, status: rsSuccess, text: "b",
      errorKind: ekNetworkError, errorMessage: "", httpStatus: 200, attemptCount: 1)
  ))
  outputChan.send(OutputMessage(
    kind: omPageResult,
    result: Result(pageId: 0, pageNumberUser: 1, status: rsSuccess, text: "a",
      errorKind: ekNetworkError, errorMessage: "", httpStatus: 200, attemptCount: 1)
  ))
  outputChan.send(OutputMessage(kind: omOutputDone))

  joinThread(th)

  let jsonl = readFile(tmpDir.joinPath("results.jsonl")).strip().splitLines()
  doAssert jsonl.len == 2
  let first = parseJson(jsonl[0])
  let second = parseJson(jsonl[1])
  doAssert first["page_id"].getInt() == 0
  doAssert second["page_id"].getInt() == 1

when isMainModule:
  main()
