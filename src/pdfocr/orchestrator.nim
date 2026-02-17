import std/atomics
import threading/channels
import ./[constants, curl, errors, json_codec, logging, network_scheduler,
         page_selection, pdfium, types, webp]

proc initGlobalLibraries*() =
  initPdfium()
  initCurlGlobal()

proc cleanupGlobalLibraries*() =
  cleanupCurlGlobal()
  destroyPdfium()

proc renderFailureResult(seqId: SeqId; page: int; kind: ErrorKind; message: string): PageResult =
  PageResult(
    seqId: seqId,
    page: page,
    status: psError,
    attempts: 1,
    text: "",
    errorKind: kind,
    errorMessage: boundedErrorMessage(message),
    httpStatus: HttpNone
  )

proc renderPageToWebp(doc: PdfDocument; page: int): tuple[
    ok: bool,
    webpBytes: seq[byte],
    errorKind: ErrorKind,
    errorMessage: string
] =
  var bitmap: PdfBitmap
  try:
    var pdfPage = loadPage(doc, page - 1)
    bitmap = renderPageAtScale(
      pdfPage,
      RenderScale,
      rotate = RenderRotate,
      flags = RenderFlags
    )
  except CatchableError:
    return (
      ok: false,
      webpBytes: @[],
      errorKind: PdfError,
      errorMessage: boundedErrorMessage(getCurrentExceptionMsg())
    )

  let bitmapWidth = width(bitmap)
  let bitmapHeight = height(bitmap)
  let pixels = buffer(bitmap)
  let rowStride = stride(bitmap)
  if bitmapWidth <= 0 or bitmapHeight <= 0 or pixels.isNil or rowStride <= 0:
    return (
      ok: false,
      webpBytes: @[],
      errorKind: PdfError,
      errorMessage: "invalid bitmap state from renderer"
    )

  try:
    let webpBytes = compressBgr(
      Positive(bitmapWidth),
      Positive(bitmapHeight),
      pixels,
      rowStride,
      WebpQuality
    )
    if webpBytes.len == 0:
      return (
        ok: false,
        webpBytes: @[],
        errorKind: EncodeError,
        errorMessage: "encoded WebP output was empty"
      )
    return (
      ok: true,
      webpBytes: webpBytes,
      errorKind: NoError,
      errorMessage: ""
    )
  except CatchableError:
    return (
      ok: false,
      webpBytes: @[],
      errorKind: EncodeError,
      errorMessage: boundedErrorMessage(getCurrentExceptionMsg())
    )

proc runOrchestrator*(cliArgs: seq[string]): int =
  var runtimeConfig: RuntimeConfig
  try:
    runtimeConfig = buildRuntimeConfig(cliArgs)
  except CatchableError:
    logError(getCurrentExceptionMsg())
    return ExitFatalRuntime

  resetSharedAtomics()

  var
    globalsInitialized = false
    networkStarted = false
    stopSent = false
    anyError = false
    written = 0
    okCount = 0
    errCount = 0

    taskCh: Chan[OcrTask]
    resultCh: Chan[PageResult]
    networkThread: Thread[NetworkWorkerContext]

  try:
    initGlobalLibraries()
    globalsInitialized = true

    let doc = loadDocument(runtimeConfig.inputPath)
    taskCh = newChan[OcrTask](Positive(1))
    resultCh = newChan[PageResult](Positive(1))

    createThread(networkThread, runNetworkWorker, NetworkWorkerContext(
      taskCh: taskCh,
      resultCh: resultCh,
      apiKey: runtimeConfig.apiKey
    ))
    networkStarted = true

    logInfo("startup: selected_count=" & $runtimeConfig.selectedCount &
      " first_page=" & $runtimeConfig.selectedPages[0] &
      " last_page=" & $runtimeConfig.selectedPages[^1])

    for seqId in 0 ..< runtimeConfig.selectedCount:
      let page = runtimeConfig.selectedPages[seqId]
      let rendered = renderPageToWebp(doc, page)

      var pageResult: PageResult
      if rendered.ok:
        taskCh.send(OcrTask(
          kind: otkPage,
          seqId: seqId,
          page: page,
          webpBytes: rendered.webpBytes
        ))
        resultCh.recv(pageResult)
      else:
        pageResult = renderFailureResult(seqId, page, rendered.errorKind, rendered.errorMessage)

      if pageResult.seqId != seqId:
        logWarn("network result seq_id mismatch; correcting for ordered output")
        pageResult.seqId = seqId
      if pageResult.page != page:
        logWarn("network result page mismatch; correcting output page")
        pageResult.page = page

      stdout.write(encodeResultLine(pageResult))
      stdout.write('\n')

      if pageResult.status == psOk:
        inc okCount
      else:
        inc errCount
        anyError = true

      inc written
      NextToWrite.store(written, moRelaxed)
      OkCount.store(okCount, moRelaxed)
      ErrCount.store(errCount, moRelaxed)

    flushFile(stdout)
    taskCh.send(OcrTask(kind: otkStop, seqId: -1, page: 0, webpBytes: @[]))
    stopSent = true
    joinThread(networkThread)
    networkStarted = false

    logInfo("completion: written=" & $written &
      " ok=" & $okCount &
      " err=" & $errCount &
      " retries=" & $RetryCount.load(moRelaxed))

    if anyError:
      result = ExitHasPageErrors
    else:
      result = ExitAllOk
  except CatchableError:
    logError(getCurrentExceptionMsg())
    result = ExitFatalRuntime
  finally:
    if networkStarted:
      if not stopSent:
        try:
          taskCh.send(OcrTask(kind: otkStop, seqId: -1, page: 0, webpBytes: @[]))
        except CatchableError:
          discard
      joinThread(networkThread)
    if globalsInitialized:
      cleanupGlobalLibraries()
