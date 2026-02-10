import std/atomics
import std/os
import threading/channels
import ./constants
import ./curl
import ./errors
import ./logging
import ./network_scheduler
import ./page_selection
import ./pdfium
import ./renderer
import ./types
import ./writer

var ORCH_SIGINT_REQUESTED: Atomic[bool]

type
  WriterThreadArg = object
    ctx: WriterContext
    done: ptr Atomic[bool]

  RendererThreadArg = object
    ctx: RendererContext
    done: ptr Atomic[bool]

  SchedulerThreadArg = object
    ctx: SchedulerContext
    done: ptr Atomic[bool]

proc ctrlCHook() {.noconv.} =
  ORCH_SIGINT_REQUESTED.store(true, moRelaxed)

proc writerThreadMain(arg: WriterThreadArg) {.thread.} =
  try:
    runWriter(arg.ctx)
  finally:
    arg.done[].store(true, moRelaxed)

proc rendererThreadMain(arg: RendererThreadArg) {.thread.} =
  try:
    runRenderer(arg.ctx)
  finally:
    arg.done[].store(true, moRelaxed)

proc schedulerThreadMain(arg: SchedulerThreadArg) {.thread.} =
  try:
    runNetworkScheduler(arg.ctx)
  finally:
    arg.done[].store(true, moRelaxed)

proc initGlobalLibraries*() =
  initPdfium()
  initCurlGlobal()

proc cleanupGlobalLibraries*() =
  cleanupCurlGlobal()
  destroyPdfium()

proc requestCancel(channels: RuntimeChannels; rendererStopSent: var bool) =
  SCHEDULER_STOP_REQUESTED.store(true, moRelaxed)
  if not rendererStopSent:
    channels.renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))
    rendererStopSent = true

proc fallbackResult(runtimeConfig: RuntimeConfig; seqId: int; reason: string): PageResult =
  PageResult(
    seqId: seqId,
    page: runtimeConfig.selectedPages[seqId],
    status: psError,
    attempts: 1,
    text: "",
    errorKind: NETWORK_ERROR,
    errorMessage: boundedErrorMessage(reason),
    httpStatus: 0,
    hasHttpStatus: false
  )

proc runOrchestrator*(cliArgs: seq[string]): int =
  var runtimeConfig: RuntimeConfig
  try:
    runtimeConfig = buildRuntimeConfig(cliArgs)
  except CatchableError as exc:
    logError(exc.msg)
    return EXIT_FATAL_RUNTIME

  ORCH_SIGINT_REQUESTED.store(false, moRelaxed)
  resetSharedAtomics()
  setControlCHook(ctrlCHook)

  var globalsInitialized = false
  var channels: RuntimeChannels
  var fatalDetected = false
  var sigintDetected = false
  var rendererStopSent = false
  var firstFatal: FatalEvent

  var writerDone: Atomic[bool]
  var rendererDone: Atomic[bool]
  var schedulerDone: Atomic[bool]
  writerDone.store(false, moRelaxed)
  rendererDone.store(false, moRelaxed)
  schedulerDone.store(false, moRelaxed)

  var writerThread: Thread[WriterThreadArg]
  var rendererThread: Thread[RendererThreadArg]
  var schedulerThread: Thread[SchedulerThreadArg]

  try:
    initGlobalLibraries()
    globalsInitialized = true

    channels = initRuntimeChannels()
    logInfo("startup: selected_count=" & $runtimeConfig.selectedCount &
      " first_page=" & $runtimeConfig.selectedPages[0] &
      " last_page=" & $runtimeConfig.selectedPages[^1])

    createThread(writerThread, writerThreadMain, WriterThreadArg(
      ctx: WriterContext(
        selectedCount: runtimeConfig.selectedCount,
        selectedPages: runtimeConfig.selectedPages,
        writerInCh: channels.writerInCh,
        fatalCh: channels.fatalCh
      ),
      done: addr writerDone
    ))

    createThread(rendererThread, rendererThreadMain, RendererThreadArg(
      ctx: RendererContext(
        pdfPath: runtimeConfig.inputPath,
        selectedPages: runtimeConfig.selectedPages,
        renderReqCh: channels.renderReqCh,
        renderOutCh: channels.renderOutCh,
        fatalCh: channels.fatalCh
      ),
      done: addr rendererDone
    ))

    createThread(schedulerThread, schedulerThreadMain, SchedulerThreadArg(
      ctx: SchedulerContext(
        selectedCount: runtimeConfig.selectedCount,
        selectedPages: runtimeConfig.selectedPages,
        renderReqCh: channels.renderReqCh,
        renderOutCh: channels.renderOutCh,
        writerInCh: channels.writerInCh,
        fatalCh: channels.fatalCh,
        apiKey: runtimeConfig.apiKey
      ),
      done: addr schedulerDone
    ))

    while not schedulerDone.load(moRelaxed):
      if ORCH_SIGINT_REQUESTED.load(moRelaxed) and not sigintDetected:
        sigintDetected = true
        logWarn("SIGINT received; stopping scheduling and finalizing unfinished pages")
        requestCancel(channels, rendererStopSent)

      var ev: FatalEvent
      while channels.fatalCh.tryRecv(ev):
        if not fatalDetected:
          fatalDetected = true
          firstFatal = ev
          logError("fatal event: source=" & $ev.source &
            " kind=" & $ev.errorKind &
            " message=" & ev.message)
        requestCancel(channels, rendererStopSent)

      if fatalDetected:
        requestCancel(channels, rendererStopSent)
      sleep(1)

    joinThread(schedulerThread)
    if fatalDetected:
      requestCancel(channels, rendererStopSent)
    joinThread(rendererThread)

    if fatalDetected or sigintDetected:
      let reason =
        if fatalDetected: "fatal shutdown before completion"
        else: "interrupted by SIGINT"
      let nextSeq = NEXT_TO_WRITE.load(moRelaxed)
      for seqId in nextSeq ..< runtimeConfig.selectedCount:
        channels.writerInCh.send(fallbackResult(runtimeConfig, seqId, reason))

    joinThread(writerThread)

    var ev: FatalEvent
    while channels.fatalCh.tryRecv(ev):
      if not fatalDetected:
        fatalDetected = true
        firstFatal = ev
        logError("fatal event: source=" & $ev.source &
          " kind=" & $ev.errorKind &
          " message=" & ev.message)

    let okCount = OK_COUNT.load(moRelaxed)
    let errCount = ERR_COUNT.load(moRelaxed)
    let written = NEXT_TO_WRITE.load(moRelaxed)
    logInfo("completion: written=" & $written &
      " ok=" & $okCount &
      " err=" & $errCount &
      " retries=" & $RETRY_COUNT.load(moRelaxed))

    if fatalDetected:
      return EXIT_FATAL_RUNTIME
    if sigintDetected:
      return EXIT_HAS_PAGE_ERRORS
    if errCount > 0:
      return EXIT_HAS_PAGE_ERRORS
    EXIT_ALL_OK
  except CatchableError as exc:
    logError(exc.msg)
    EXIT_FATAL_RUNTIME
  finally:
    when declared(unsetControlCHook):
      unsetControlCHook()
    if globalsInitialized:
      cleanupGlobalLibraries()
