import std/[atomics, os, strutils]
import threading/channels
import ./[constants, curl, errors, global3batch_engine, logging, network_scheduler,
         page_selection, pdfium, renderer, types, writer]

type
  EngineKind = enum
    ekComplex,
    ekGlobal3Batch

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

proc parseEngineValue(value: string): EngineKind =
  case value.toLowerAscii()
  of "complex":
    ekComplex
  of "global3batch":
    ekGlobal3Batch
  else:
    raise newException(ValueError, "invalid --engine value: " & value)

proc extractEngineArgs(cliArgs: seq[string]): tuple[engine: EngineKind, filtered: seq[string]] =
  result.engine = ekComplex
  result.filtered = @[]

  var seenEngine = false
  var i = 0
  while i < cliArgs.len:
    let arg = cliArgs[i]
    var handled = false
    var value = ""

    if arg.startsWith("--engine="):
      handled = true
      value = arg.substr("--engine=".len)
    elif arg.startsWith("--engine:"):
      handled = true
      value = arg.substr("--engine:".len)
    elif arg == "--engine":
      handled = true
      if i + 1 >= cliArgs.len:
        raise newException(ValueError, "missing value for --engine")
      inc i
      value = cliArgs[i]

    if handled:
      if value.len == 0:
        raise newException(ValueError, "missing value for --engine")
      let parsed = parseEngineValue(value)
      if seenEngine and parsed != result.engine:
        raise newException(ValueError, "conflicting --engine options")
      result.engine = parsed
      seenEngine = true
    else:
      result.filtered.add(arg)

    inc i

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

proc runComplexEngine(runtimeConfig: RuntimeConfig): int =
  OrchSigintRequested.store(false, moRelaxed)
  resetSharedAtomics()
  setControlCHook(ctrlCHook)

  var
    fatalDetected = false
    sigintDetected = false
    rendererStopSent = false

    writerThread: Thread[WriterContext]
    rendererThread: Thread[RendererContext]
    schedulerThread: Thread[SchedulerContext]

  try:
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
        logError("fatal event: source=" & $ev.source &
          " kind=" & $ev.errorKind &
          " message=" & ev.message)

    let
      okCount = OkCount.load(moRelaxed)
      errCount = ErrCount.load(moRelaxed)
      written = NextToWrite.load(moRelaxed)
    logInfo("completion: written=" & $written &
      " ok=" & $okCount &
      " err=" & $errCount &
      " retries=" & $RetryCount.load(moRelaxed))

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

proc runOrchestrator*(cliArgs: seq[string]): int =
  var
    engine = ekComplex
    effectiveArgs = cliArgs

  try:
    let parsed = extractEngineArgs(cliArgs)
    engine = parsed.engine
    effectiveArgs = parsed.filtered
  except CatchableError:
    logError(getCurrentExceptionMsg())
    return ExitFatalRuntime

  var runtimeConfig: RuntimeConfig
  try:
    runtimeConfig = buildRuntimeConfig(effectiveArgs)
  except CatchableError:
    logError(getCurrentExceptionMsg())
    return ExitFatalRuntime

  var globalsInitialized = false
  try:
    initGlobalLibraries()
    globalsInitialized = true

    case engine
    of ekComplex:
      result = runComplexEngine(runtimeConfig)
    of ekGlobal3Batch:
      result = runGlobal3BatchEngine(runtimeConfig)
  except CatchableError:
    logError(getCurrentExceptionMsg())
    result = ExitFatalRuntime
  finally:
    if globalsInitialized:
      cleanupGlobalLibraries()
