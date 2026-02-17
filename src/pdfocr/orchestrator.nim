import std/[atomics, tables]
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
    nextToRender = 0
    nextToWrite = 0
    outstanding = 0

    taskCh: Chan[OcrTask]
    resultCh: Chan[PageResult]
    networkThread: Thread[NetworkWorkerContext]

  try:
    initGlobalLibraries()
    globalsInitialized = true

    let doc = loadDocument(runtimeConfig.inputPath)
    taskCh = newChan[OcrTask](Positive(MaxInflight))
    resultCh = newChan[PageResult](Positive(MaxInflight))

    createThread(networkThread, runNetworkWorker, NetworkWorkerContext(
      taskCh: taskCh,
      resultCh: resultCh,
      apiKey: runtimeConfig.apiKey
    ))
    networkStarted = true

    logInfo("startup: selected_count=" & $runtimeConfig.selectedCount &
      " first_page=" & $runtimeConfig.selectedPages[0] &
      " last_page=" & $runtimeConfig.selectedPages[^1])

    var pendingBySeq = initTable[int, PageResult]()
    var usesNetwork = newSeq[bool](runtimeConfig.selectedCount)

    proc writeResult(resultForSeq: PageResult) =
      stdout.write(encodeResultLine(resultForSeq))
      stdout.write('\n')

      if resultForSeq.status == psOk:
        inc okCount
      else:
        inc errCount
        anyError = true

      if usesNetwork[resultForSeq.seqId]:
        dec outstanding

      inc written
      inc nextToWrite
      NextToWrite.store(written, moRelaxed)
      OkCount.store(okCount, moRelaxed)
      ErrCount.store(errCount, moRelaxed)

    proc flushReady() =
      while nextToWrite < runtimeConfig.selectedCount and pendingBySeq.hasKey(nextToWrite):
        var pageResult = pendingBySeq[nextToWrite]
        pendingBySeq.del(nextToWrite)
        let mappedPage = runtimeConfig.selectedPages[nextToWrite]
        if pageResult.seqId != nextToWrite:
          logWarn("corrected mismatched seq_id before ordered write")
          pageResult.seqId = nextToWrite
        if pageResult.page != mappedPage:
          logWarn("corrected mismatched page before ordered write")
          pageResult.page = mappedPage
        writeResult(pageResult)

    while nextToWrite < runtimeConfig.selectedCount:
      while nextToRender < runtimeConfig.selectedCount and
            (nextToRender - nextToWrite) < MaxInflight and
            outstanding < MaxInflight:
        let seqId = nextToRender
        let page = runtimeConfig.selectedPages[seqId]
        let rendered = renderPageToWebp(doc, page)

        if rendered.ok:
          usesNetwork[seqId] = true
          taskCh.send(OcrTask(
            kind: otkPage,
            seqId: seqId,
            page: page,
            webpBytes: rendered.webpBytes
          ))
          inc outstanding
        else:
          pendingBySeq[seqId] = renderFailureResult(
            seqId,
            page,
            rendered.errorKind,
            rendered.errorMessage
          )

        inc nextToRender
        flushReady()

      if nextToWrite >= runtimeConfig.selectedCount:
        break

      if pendingBySeq.hasKey(nextToWrite):
        flushReady()
        continue

      if outstanding > 0:
        var networkResult: PageResult
        resultCh.recv(networkResult)
        let seqId = networkResult.seqId
        if seqId < 0 or seqId >= runtimeConfig.selectedCount:
          logWarn("network returned out-of-range seq_id; synthesizing ordered error")
          if not pendingBySeq.hasKey(nextToWrite):
            pendingBySeq[nextToWrite] = renderFailureResult(
              nextToWrite,
              runtimeConfig.selectedPages[nextToWrite],
              NetworkError,
              "network returned invalid seq_id"
            )
        elif pendingBySeq.hasKey(seqId):
          logWarn("network returned duplicate seq_id result; dropping duplicate")
        else:
          pendingBySeq[seqId] = networkResult
        flushReady()
      elif nextToRender >= runtimeConfig.selectedCount:
        raise newException(IOError, "orchestrator stalled with no outstanding work")

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
