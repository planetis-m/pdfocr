import std/[atomics, options]
import threading/channels
import ./[constants, curl, errors, json_codec, logging, network_scheduler,
         page_selection, pdfium, types, webp]

type
  RenderPageOutcome = object
    ok: bool
    webpBytes: seq[byte]
    errorKind: ErrorKind
    errorMessage: string

  PendingEntry = object
    result: PageResult
    fromNetwork: bool

proc initGlobalLibraries() =
  initPdfium()
  initCurlGlobal()

proc cleanupGlobalLibraries() =
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

proc renderPageToWebp(doc: PdfDocument; page: int): RenderPageOutcome =
  result = RenderPageOutcome(
    ok: false,
    webpBytes: @[],
    errorKind: NoError,
    errorMessage: ""
  )
  var bitmap: PdfBitmap
  var renderOk = false
  try:
    var pdfPage = loadPage(doc, page - 1)
    bitmap = renderPageAtScale(
      pdfPage,
      RenderScale,
      rotate = RenderRotate,
      flags = RenderFlags
    )
    renderOk = true
  except CatchableError:
    result = RenderPageOutcome(
      ok: false,
      webpBytes: @[],
      errorKind: PdfError,
      errorMessage: boundedErrorMessage(getCurrentExceptionMsg())
    )

  if renderOk:
    let bitmapWidth = width(bitmap)
    let bitmapHeight = height(bitmap)
    let pixels = buffer(bitmap)
    let rowStride = stride(bitmap)
    if bitmapWidth <= 0 or bitmapHeight <= 0 or pixels.isNil or rowStride <= 0:
      result = RenderPageOutcome(
        ok: false,
        webpBytes: @[],
        errorKind: PdfError,
        errorMessage: "invalid bitmap state from renderer"
      )
    else:
      try:
        let webpBytes = compressBgr(
          bitmapWidth,
          bitmapHeight,
          pixels,
          rowStride,
          WebpQuality
        )
        if webpBytes.len == 0:
          result = RenderPageOutcome(
            ok: false,
            webpBytes: @[],
            errorKind: EncodeError,
            errorMessage: "encoded WebP output was empty"
          )
        else:
          result = RenderPageOutcome(
            ok: true,
            webpBytes: webpBytes,
            errorKind: NoError,
            errorMessage: ""
          )
      except CatchableError:
        result = RenderPageOutcome(
          ok: false,
          webpBytes: @[],
          errorKind: EncodeError,
          errorMessage: boundedErrorMessage(getCurrentExceptionMsg())
        )

proc runOrchestratorWithConfig(runtimeConfig: RuntimeConfig): int =
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
    taskCh = newChan[OcrTask](MaxInflight)
    resultCh = newChan[PageResult](MaxInflight)

    createThread(networkThread, runNetworkWorker, NetworkWorkerContext(
      taskCh: taskCh,
      resultCh: resultCh,
      apiKey: runtimeConfig.apiKey
    ))
    networkStarted = true

    logInfo("startup: selected_count=" & $runtimeConfig.selectedCount &
      " first_page=" & $runtimeConfig.selectedPages[0] &
      " last_page=" & $runtimeConfig.selectedPages[^1])

    let k = MaxInflight
    var pending = newSeq[Option[PendingEntry]](k)
    var stagedTask = none(OcrTask)

    template slotIndex(seqId: int): int =
      seqId mod k

    template canStore(seqId: int): bool =
      seqId >= nextToWrite and seqId < nextToWrite + k

    proc storePending(resultForSeq: PageResult; fromNetwork: bool): bool =
      doAssert canStore(resultForSeq.seqId),
        "seq_id outside pending window: seq=" & $resultForSeq.seqId &
        " next_write=" & $nextToWrite &
        " k=" & $k
      let idx = slotIndex(resultForSeq.seqId)
      if pending[idx].isSome():
        let existing = pending[idx].get()
        if existing.result.seqId == resultForSeq.seqId:
          result = false
        else:
          raise newException(IOError,
            "ring slot collision: slot=" & $idx &
            " existing_seq=" & $existing.result.seqId &
            " incoming_seq=" & $resultForSeq.seqId)
      else:
        pending[idx] = some(PendingEntry(result: resultForSeq, fromNetwork: fromNetwork))
        result = true

    proc nextReady(): bool =
      let idx = slotIndex(nextToWrite)
      if pending[idx].isSome():
        let entry = pending[idx].get()
        result = entry.result.seqId == nextToWrite
      else:
        result = false

    proc writeResult(resultForSeq: PageResult; fromNetwork: bool) =
      stdout.write(encodeResultLine(resultForSeq))
      stdout.write('\n')

      if resultForSeq.status == psOk:
        inc okCount
      else:
        inc errCount
        anyError = true

      if fromNetwork:
        dec outstanding
        doAssert outstanding >= 0, "outstanding underflow"

      inc written
      inc nextToWrite

    proc flushReady() =
      while nextToWrite < runtimeConfig.selectedCount and nextReady():
        let idx = slotIndex(nextToWrite)
        let entry = pending[idx].get()
        pending[idx] = none(PendingEntry)
        var pageResult = entry.result
        let mappedPage = runtimeConfig.selectedPages[nextToWrite]
        if pageResult.seqId != nextToWrite:
          logWarn("corrected mismatched seq_id before ordered write")
          pageResult.seqId = nextToWrite
        if pageResult.page != mappedPage:
          logWarn("corrected mismatched page before ordered write")
          pageResult.page = mappedPage
        writeResult(pageResult, entry.fromNetwork)

    proc onNetworkResult(networkResult: PageResult) =
      let seqId = networkResult.seqId
      if seqId < 0 or seqId >= runtimeConfig.selectedCount:
        raise newException(IOError, "network returned out-of-range seq_id: " & $seqId)
      elif not canStore(seqId):
        raise newException(IOError,
          "network returned seq_id outside pending window: seq=" & $seqId &
          " next_write=" & $nextToWrite &
          " k=" & $k)
      elif not storePending(networkResult, fromNetwork = true):
        raise newException(IOError, "network returned duplicate seq_id result: " & $seqId)

    while nextToWrite < runtimeConfig.selectedCount:
      var submissionBlocked = false
      while true:
        if stagedTask.isSome():
          if outstanding >= k:
            break
          let task = stagedTask.get()
          if taskCh.trySend(task):
            stagedTask = none(OcrTask)
            inc outstanding
            doAssert outstanding <= k, "outstanding overflow"
          else:
            submissionBlocked = true
            break
        else:
          if nextToRender >= runtimeConfig.selectedCount:
            break
          if (nextToRender - nextToWrite) >= k:
            break
          if outstanding >= k:
            break

          let seqId = nextToRender
          let page = runtimeConfig.selectedPages[seqId]
          let rendered = renderPageToWebp(doc, page)

          if rendered.ok:
            doAssert canStore(seqId), "rendered seq_id outside pending window"
            let task = OcrTask(
              kind: otkPage,
              seqId: seqId,
              page: page,
              webpBytes: rendered.webpBytes
            )
            if taskCh.trySend(task):
              inc outstanding
              doAssert outstanding <= k, "outstanding overflow"
            else:
              stagedTask = some(task)
              submissionBlocked = true
            inc nextToRender
          else:
            discard storePending(
              renderFailureResult(
                seqId,
                page,
                rendered.errorKind,
                rendered.errorMessage
              ),
              fromNetwork = false
            )
            inc nextToRender

          flushReady()
          if submissionBlocked:
            break

      if nextToWrite >= runtimeConfig.selectedCount:
        break

      if not nextReady():
        if outstanding > 0:
          var networkResult: PageResult
          resultCh.recv(networkResult)
          onNetworkResult(networkResult)
        elif submissionBlocked or stagedTask.isSome():
          raise newException(IOError, "task submission blocked but no outstanding network work")
        elif nextToRender >= runtimeConfig.selectedCount:
          raise newException(IOError, "orchestrator stalled with no outstanding work")
      else:
        var networkResult: PageResult
        while resultCh.tryRecv(networkResult):
          onNetworkResult(networkResult)

      flushReady()

      if not nextReady() and outstanding > 0:
        var networkResult: PageResult
        while resultCh.tryRecv(networkResult):
          onNetworkResult(networkResult)
        flushReady()

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

proc runOrchestrator*(cliArgs: seq[string]): int =
  try:
    let runtimeConfig = buildRuntimeConfig(cliArgs)
    result = runOrchestratorWithConfig(runtimeConfig)
  except CatchableError:
    logError(getCurrentExceptionMsg())
    result = ExitFatalRuntime
