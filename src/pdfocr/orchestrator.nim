import std/[atomics, monotimes, os, times]
import threading/channels
import ./[constants, curl, errors, logging, network_scheduler,
         page_selection, pdfium, renderer, types, writer]

var
  OrchSigintRequested: Atomic[bool]
  WriterDone: Atomic[bool]
  RendererDone: Atomic[bool]
  SchedulerDone: Atomic[bool]
  RuntimeChannels: RuntimeChannels

proc ctrlCHook() {.noconv.} =
  OrchSigintRequested.store(true, moRelaxed)

proc writerThreadMain(ctx: WriterContext) {.thread.} =
  try:
    runWriter(ctx)
  finally:
    WriterDone.store(true, moRelaxed)

proc rendererThreadMain(ctx: RendererContext) {.thread.} =
  try:
    runRenderer(ctx)
  finally:
    RendererDone.store(true, moRelaxed)

proc schedulerThreadMain(ctx: SchedulerContext) {.thread.} =
  try:
    runNetworkScheduler(ctx)
  finally:
    SchedulerDone.store(true, moRelaxed)

proc initGlobalLibraries*() =
  initPdfium()
  initCurlGlobal()

proc cleanupGlobalLibraries*() =
  cleanupCurlGlobal()
  destroyPdfium()

proc requestCancel(rendererStopSent: var bool) =
  SchedulerStopRequested.store(true, moRelaxed)
  if not rendererStopSent:
    RuntimeChannels.renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))
    rendererStopSent = true

proc fallbackResult(runtimeConfig: RuntimeConfig; seqId: int; reason: string): PageResult =
  PageResult(
    seqId: seqId,
    page: runtimeConfig.selectedPages[seqId],
    status: psError,
    attempts: 1,
    text: "",
    errorKind: NetworkError,
    errorMessage: boundedErrorMessage(reason),
    httpStatus: HttpNone
  )

proc runOrchestrator*(cliArgs: seq[string]): int =
  var runtimeConfig: RuntimeConfig
  try:
    runtimeConfig = buildRuntimeConfig(cliArgs)
  except CatchableError:
    logError(getCurrentExceptionMsg())
    return ExitFatalRuntime

  OrchSigintRequested.store(false, moRelaxed)
  resetSharedAtomics()
  setControlCHook(ctrlCHook)

  var
    globalsInitialized = false
    fatalDetected = false
    sigintDetected = false
    rendererStopSent = false
    firstFatal: FatalEvent

    writerThread: Thread[WriterContext]
    rendererThread: Thread[RendererContext]
    schedulerThread: Thread[SchedulerContext]
  let runStartedAt = getMonoTime()

  try:
    initGlobalLibraries()
    globalsInitialized = true

    RuntimeChannels = initRuntimeChannels()
    logInfo("startup: selected_count=" & $runtimeConfig.selectedCount &
      " first_page=" & $runtimeConfig.selectedPages[0] &
      " last_page=" & $runtimeConfig.selectedPages[^1])

    createThread(writerThread, writerThreadMain, WriterContext(
      selectedCount: runtimeConfig.selectedCount,
      selectedPages: runtimeConfig.selectedPages,
      writerInCh: RuntimeChannels.writerInCh,
      fatalCh: RuntimeChannels.fatalCh
    ))

    createThread(rendererThread, rendererThreadMain, RendererContext(
      pdfPath: runtimeConfig.inputPath,
      selectedPages: runtimeConfig.selectedPages,
      renderReqCh: RuntimeChannels.renderReqCh,
      renderOutCh: RuntimeChannels.renderOutCh,
      fatalCh: RuntimeChannels.fatalCh
    ))

    createThread(schedulerThread, schedulerThreadMain, SchedulerContext(
      selectedCount: runtimeConfig.selectedCount,
      selectedPages: runtimeConfig.selectedPages,
      renderReqCh: RuntimeChannels.renderReqCh,
      renderOutCh: RuntimeChannels.renderOutCh,
      writerInCh: RuntimeChannels.writerInCh,
      fatalCh: RuntimeChannels.fatalCh,
      apiKey: runtimeConfig.apiKey
    ))

    while not SchedulerDone.load(moRelaxed):
      if OrchSigintRequested.load(moRelaxed) and not sigintDetected:
        sigintDetected = true
        logWarn("SIGINT received; stopping scheduling and finalizing unfinished pages")
        requestCancel(rendererStopSent)

      var ev: FatalEvent
      while RuntimeChannels.fatalCh.tryRecv(ev):
        if not fatalDetected:
          fatalDetected = true
          firstFatal = ev
          logError("fatal event: source=" & $ev.source &
            " kind=" & $ev.errorKind &
            " message=" & ev.message)
        requestCancel(rendererStopSent)

      if fatalDetected:
        requestCancel(rendererStopSent)
      sleep(1)

    joinThread(schedulerThread)
    if fatalDetected:
      requestCancel(rendererStopSent)
    joinThread(rendererThread)

    if fatalDetected or sigintDetected:
      let reason =
        if fatalDetected: "fatal shutdown before completion"
        else: "interrupted by SIGINT"
      let nextSeq = NextToWrite.load(moRelaxed)
      for seqId in nextSeq ..< runtimeConfig.selectedCount:
        RuntimeChannels.writerInCh.send(fallbackResult(runtimeConfig, seqId, reason))

    joinThread(writerThread)

    var ev: FatalEvent
    while RuntimeChannels.fatalCh.tryRecv(ev):
      if not fatalDetected:
        fatalDetected = true
        firstFatal = ev
        logError("fatal event: source=" & $ev.source &
          " kind=" & $ev.errorKind &
          " message=" & ev.message)

    let
      okCount = OkCount.load(moRelaxed)
      errCount = ErrCount.load(moRelaxed)
      written = NextToWrite.load(moRelaxed)
      runtimeMs = max(1, int((getMonoTime() - runStartedAt).inMilliseconds))
      requestCount = TotalRequestCount.load(moRelaxed)
      totalRequestLatencyMs = TotalRequestLatencyMs.load(moRelaxed)
    logInfo("completion: written=" & $written &
      " ok=" & $okCount &
      " err=" & $errCount &
      " retries=" & $RetryCount.load(moRelaxed))
    if requestCount > 0:
      let
        avgRequestMs = float(totalRequestLatencyMs) / float(requestCount)
        serialTheoreticalMs = float(totalRequestLatencyMs)
        idealParallelMs = serialTheoreticalMs / float(MaxInflight)
        speedupVsSerial = serialTheoreticalMs / float(runtimeMs)
        efficiencyVsMaxInflight = speedupVsSerial / float(MaxInflight)
      logInfo("performance: runtime_ms=" & $runtimeMs &
        " request_count=" & $requestCount &
        " avg_request_ms=" & $avgRequestMs &
        " serial_theoretical_ms=" & $serialTheoreticalMs &
        " max_inflight=" & $MaxInflight &
        " ideal_parallel_ms=" & $idealParallelMs &
        " effective_concurrency=" & $speedupVsSerial &
        " efficiency_vs_max_inflight=" & $efficiencyVsMaxInflight)
    else:
      logInfo("performance: runtime_ms=" & $runtimeMs &
        " request_count=0 avg_request_ms=0 serial_theoretical_ms=0 ideal_parallel_ms=0")

    if fatalDetected:
      result = ExitFatalRuntime
    elif sigintDetected:
      result = ExitHasPageErrors
    elif errCount > 0:
      result = ExitHasPageErrors
    else:
      result = ExitAllOk
  except CatchableError:
    logError(getCurrentExceptionMsg())
    result = ExitFatalRuntime
  finally:
    unsetControlCHook()
    if globalsInitialized:
      cleanupGlobalLibraries()
