import std/[atomics, options]
import threading/channels
import ./[constants, curl, errors, json_codec, logging, network_scheduler,
         pdfium, runtime_config, types, webp]

type
  PendingEntry = object
    result: PageResult
    fromNetwork: bool

  OrchestratorState = object
    anyError: bool
    written, okCount, errCount: int
    nextToRender, nextToWrite: int
    outstanding, windowSize: int
    pending: seq[Option[PendingEntry]]
    stagedTask: Option[OcrTask]

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
    kind: kind,
    errorMessage: boundedErrorMessage(message),
    httpStatus: HttpNone
  )

proc renderBitmap(doc: PdfDocument; page: int; config: RenderConfig): PdfBitmap =
  var pdfPage = loadPage(doc, page - 1)
  result = renderPageAtScale(pdfPage, config.renderScale, rotate = RenderRotate,
    flags = RenderFlags)
  let bitmapWidth = result.width
  let bitmapHeight = result.height
  let pixels = result.buffer
  let rowStride = result.stride
  if bitmapWidth <= 0 or bitmapHeight <= 0 or pixels.isNil or rowStride <= 0:
    raise newException(IOError, "invalid bitmap state from renderer")

proc encodeBitmap(bitmap: PdfBitmap; config: RenderConfig): seq[byte] =
  let bitmapWidth = bitmap.width
  let bitmapHeight = bitmap.height
  let pixels = bitmap.buffer
  let rowStride = bitmap.stride

  result = compressBgr(bitmapWidth, bitmapHeight, pixels, rowStride, config.webpQuality)
  if result.len == 0:
    raise newException(IOError, "encoded WebP output was empty")

proc initOrchestratorState(windowSize: int): OrchestratorState =
  OrchestratorState(
    anyError: false,
    written: 0,
    okCount: 0,
    errCount: 0,
    nextToRender: 0,
    nextToWrite: 0,
    outstanding: 0,
    pending: newSeq[Option[PendingEntry]](windowSize),
    stagedTask: none(OcrTask),
    windowSize: windowSize
  )

proc slotIndex(state: OrchestratorState; seqId: int): int {.inline.} =
  seqId mod state.windowSize

proc canStore(state: OrchestratorState; seqId: int): bool {.inline.} =
  seqId >= state.nextToWrite and seqId < state.nextToWrite + state.windowSize

proc storePending(state: var OrchestratorState; resultForSeq: PageResult; fromNetwork: bool): bool =
  doAssert state.canStore(resultForSeq.seqId),
    "seq_id outside pending window: seq=" & $resultForSeq.seqId &
    " next_write=" & $state.nextToWrite &
    " k=" & $state.windowSize
  let idx = state.slotIndex(resultForSeq.seqId)
  if state.pending[idx].isSome():
    let existing = state.pending[idx].get()
    if existing.result.seqId == resultForSeq.seqId:
      result = false
    else:
      raise newException(IOError,
        "ring slot collision: slot=" & $idx &
        " existing_seq=" & $existing.result.seqId &
        " incoming_seq=" & $resultForSeq.seqId)
  else:
    state.pending[idx] = some(PendingEntry(result: resultForSeq, fromNetwork: fromNetwork))
    result = true

proc nextReady(state: OrchestratorState): bool =
  let idx = state.slotIndex(state.nextToWrite)
  if state.pending[idx].isSome():
    let entry = state.pending[idx].get()
    result = entry.result.seqId == state.nextToWrite
  else:
    result = false

proc writeResult(state: var OrchestratorState; resultForSeq: PageResult; fromNetwork: bool) =
  stdout.write(encodeResultLine(resultForSeq))
  stdout.write('\n')

  if resultForSeq.status == psOk:
    inc state.okCount
  else:
    inc state.errCount
    state.anyError = true

  if fromNetwork:
    dec state.outstanding
    doAssert state.outstanding >= 0, "outstanding underflow"

  inc state.written
  inc state.nextToWrite

proc flushReady(state: var OrchestratorState; runtimeConfig: RuntimeConfig) =
  while state.nextToWrite < runtimeConfig.selectedCount and state.nextReady():
    let idx = state.slotIndex(state.nextToWrite)
    let entry = state.pending[idx].get()
    state.pending[idx] = none(PendingEntry)
    var pageResult = entry.result
    let mappedPage = runtimeConfig.selectedPages[state.nextToWrite]
    if pageResult.seqId != state.nextToWrite:
      logWarn("corrected mismatched seq_id before ordered write")
      pageResult.seqId = state.nextToWrite
    if pageResult.page != mappedPage:
      logWarn("corrected mismatched page before ordered write")
      pageResult.page = mappedPage
    state.writeResult(pageResult, entry.fromNetwork)

proc onNetworkResult(state: var OrchestratorState; runtimeConfig: RuntimeConfig;
    networkResult: PageResult) =
  let seqId = networkResult.seqId
  if seqId < 0 or seqId >= runtimeConfig.selectedCount:
    raise newException(IOError, "network returned out-of-range seq_id: " & $seqId)
  elif not state.canStore(seqId):
    raise newException(IOError,
      "network returned seq_id outside pending window: seq=" & $seqId &
      " next_write=" & $state.nextToWrite &
      " k=" & $state.windowSize)
  elif not state.storePending(networkResult, fromNetwork = true):
    raise newException(IOError, "network returned duplicate seq_id result: " & $seqId)

proc runOrchestratorWithConfig(runtimeConfig: RuntimeConfig): int =
  resetSharedAtomics()

  var
    globalsInitialized = false
    networkStarted = false
    stopSent = false

    taskCh: Chan[OcrTask]
    resultCh: Chan[PageResult]
    networkThread: Thread[NetworkWorkerContext]

  try:
    initGlobalLibraries()
    globalsInitialized = true

    let doc = loadDocument(runtimeConfig.inputPath)
    let k = runtimeConfig.networkConfig.maxInflight
    var state = initOrchestratorState(k)
    taskCh = newChan[OcrTask](k)
    resultCh = newChan[PageResult](k)

    createThread(networkThread, runNetworkWorker, NetworkWorkerContext(
      taskCh: taskCh,
      resultCh: resultCh,
      apiKey: runtimeConfig.apiKey,
      config: runtimeConfig.networkConfig
    ))
    networkStarted = true

    logInfo("startup: selected_count=" & $runtimeConfig.selectedCount &
      " first_page=" & $runtimeConfig.selectedPages[0] &
      " last_page=" & $runtimeConfig.selectedPages[^1])

    while state.nextToWrite < runtimeConfig.selectedCount:
      var submissionBlocked = false
      while true:
        if state.stagedTask.isSome():
          if state.outstanding >= k:
            break
          let task = state.stagedTask.get()
          if taskCh.trySend(task):
            state.stagedTask = none(OcrTask)
            inc state.outstanding
            doAssert state.outstanding <= k, "outstanding overflow"
          else:
            submissionBlocked = true
            break
        else:
          if state.nextToRender >= runtimeConfig.selectedCount:
            break
          if (state.nextToRender - state.nextToWrite) >= k:
            break
          if state.outstanding >= k:
            break

          let seqId = state.nextToRender
          let page = runtimeConfig.selectedPages[seqId]
          var bitmap: PdfBitmap
          var renderedOk = false
          try:
            bitmap = renderBitmap(doc, page, runtimeConfig.renderConfig)
            renderedOk = true
          except CatchableError:
            discard state.storePending(renderFailureResult(seqId, page, PdfError,
              boundedErrorMessage(getCurrentExceptionMsg())), fromNetwork = false)

          if renderedOk:
            try:
              let webpBytes = encodeBitmap(bitmap, runtimeConfig.renderConfig)
              doAssert state.canStore(seqId), "rendered seq_id outside pending window"
              let task = OcrTask(
                kind: otkPage,
                seqId: seqId,
                page: page,
                webpBytes: webpBytes
              )
              if taskCh.trySend(task):
                inc state.outstanding
                doAssert state.outstanding <= k, "outstanding overflow"
              else:
                state.stagedTask = some(task)
                submissionBlocked = true
            except CatchableError:
              discard state.storePending(renderFailureResult(seqId, page, EncodeError,
                boundedErrorMessage(getCurrentExceptionMsg())), fromNetwork = false)
          inc state.nextToRender

          state.flushReady(runtimeConfig)
          if submissionBlocked:
            break

      if state.nextToWrite >= runtimeConfig.selectedCount:
        break

      if not state.nextReady():
        if state.outstanding > 0:
          var networkResult: PageResult
          resultCh.recv(networkResult)
          state.onNetworkResult(runtimeConfig, networkResult)
        elif submissionBlocked or state.stagedTask.isSome():
          raise newException(IOError, "task submission blocked but no outstanding network work")
        elif state.nextToRender >= runtimeConfig.selectedCount:
          raise newException(IOError, "orchestrator stalled with no outstanding work")
      else:
        var networkResult: PageResult
        while resultCh.tryRecv(networkResult):
          state.onNetworkResult(runtimeConfig, networkResult)

      state.flushReady(runtimeConfig)

      if not state.nextReady() and state.outstanding > 0:
        var networkResult: PageResult
        while resultCh.tryRecv(networkResult):
          state.onNetworkResult(runtimeConfig, networkResult)
        state.flushReady(runtimeConfig)

    flushFile(stdout)
    taskCh.send(OcrTask(kind: otkStop, seqId: -1, page: 0, webpBytes: @[]))
    stopSent = true
    joinThread(networkThread)
    networkStarted = false

    logInfo("completion: written=" & $state.written &
      " ok=" & $state.okCount &
      " err=" & $state.errCount &
      " retries=" & $RetryCount.load(moRelaxed))

    if state.anyError:
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
