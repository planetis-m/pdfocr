import std/[os, exitprocs]
import threading/channels
import pdfocr/[cli, config, logging, types, producer, output_writer, page_ranges]
when defined(threadSanitizer) or defined(addressSanitizer):
  import pdfocr/network_stub as network_impl
else:
  import pdfocr/network_worker as network_impl
import pdfocr/[curl, pdfium]

proc runPipeline(opts: CliOptions; pageStartIdx, pageEndIdx: int): int =
  let inputChan = newChan[InputMessage](opts.config.highWater)
  let outputChan = newChan[OutputMessage](opts.config.highWater)
  let summaryChan = newChan[OutputSummary](1)

  var producerThread: Thread[ProducerContext]
  var networkThread: Thread[NetworkContext]
  var outputThread: Thread[OutputContext]

  let producerCtx = ProducerContext(
    pdfPath: opts.pdfPath,
    pageStart: pageStartIdx,
    pageEnd: pageEndIdx,
    outputDir: opts.outputDir,
    config: opts.config,
    inputChan: inputChan,
    outputChan: outputChan
  )
  let networkCtx = network_impl.NetworkContext(
    apiKey: opts.apiKey,
    config: opts.config,
    inputChan: inputChan,
    outputChan: outputChan
  )
  let outputCtx = OutputContext(
    outputDir: opts.outputDir,
    inputFile: extractFilename(opts.pdfPath),
    pageStartUser: opts.pageStart,
    pageEndUser: opts.pageEnd,
    config: opts.config,
    outputChan: outputChan,
    summaryChan: summaryChan
  )

  createThread(producerThread, runProducer, producerCtx)
  createThread(networkThread, network_impl.runNetworkWorker, networkCtx)
  createThread(outputThread, runOutputWriter, outputCtx)

  joinThread(producerThread)
  joinThread(networkThread)
  joinThread(outputThread)
  var summary: OutputSummary
  summaryChan.recv(summary)
  if summary.failureCount > 0:
    return 1
  return 0

proc main(): int =
  var opts = parseArgs()
  logConfigSnapshot(opts.config)

  initPdfium()
  initCurlGlobal()
  try:
    var doc = loadDocument(opts.pdfPath)
    try:
      let totalPages = pageCount(doc)
      if totalPages <= 0:
        logWarn("PDF has no pages; nothing to process.")
        return 0
      let normalizedRange = normalizePageRange(totalPages, opts.pageStart, opts.pageEnd)
      opts.pageStart = normalizedRange.a
      opts.pageEnd = normalizedRange.b
      let startIdx = normalizedRange.a - 1
      let endIdx = normalizedRange.b - 1
      return runPipeline(opts, startIdx, endIdx)
    finally:
      close(doc)
  finally:
    cleanupCurlGlobal()
    destroyPdfium()

  return 0

when isMainModule:
  try:
    setProgramResult(main())
  except CatchableError:
    logError("Fatal error: " & getCurrentExceptionMsg())
    setProgramResult(1)
