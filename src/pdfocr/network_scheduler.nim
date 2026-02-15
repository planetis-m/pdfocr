import std/[atomics, base64, deques, monotimes, os, random, tables, times]
import threading/channels
import ./bindings/curl
import ./[constants, curl, errors, json_codec, logging, types]

const
  OCRInstruction = "Extract all readable text exactly."
  MaxWriterPending = Window + MaxInflight
  RetryJitterDivisor = 2
  ResponseExcerptLimit = 240

proc slidingWindowAllows*(seqId: int; nextToWrite: int): bool {.inline.} =
  result = seqId < nextToWrite + Window

proc classifyCurlErrorKind*(curlCode: CURLcode): ErrorKind {.inline.} =
  result = if curlCode == CurleOperationTimedout: Timeout else: NetworkError

proc httpStatusRetryable*(httpStatus: HttpCode): bool {.inline.} =
  result = httpStatus == Http429 or (httpStatus >= Http500 and httpStatus < Http600)

proc backoffBaseMs*(attempt: int): int =
  # Safe from overflow: MaxRetries=5 yields max shift of 5 (500*32=16000 < 2^31).
  let exponent = if attempt <= 1: 0 else: attempt - 1
  let raw = RetryBaseDelayMs shl exponent
  result = min(raw, RetryMaxDelayMs)

type
  RetryItem = object
    readyAt: MonoTime
    task: RenderedTask

  RequestResponseBuffer = object
    body: string

  # Keep this `ref object` acyclic for ARC/atomicArc correctness.
  # Callback userdata points to `response` (plain object), not this ref itself.
  RequestContext = ref object
    seqId: SeqId
    page: int
    attempt: int
    webpBytes: seq[byte]
    response: RequestResponseBuffer
    easy: CurlEasy
    headers: CurlSlist

  SchedulerState = object
    nextSeqToRequestRender: int
    renderPendingCount: int
    finalCount: int
    rendererStopSent: bool
    cancelFinalized: bool
    finalGuard: FinalizationGuard
    renderedReady: Table[int, RenderedTask]
    retryQueue: seq[RetryItem]
    activeTransfers: Table[uint, RequestContext]
    writerPending: Deque[PageResult]
    renderOutBatch: Deque[RendererOutput]
    rng: Rand

proc writeResponseCb(buffer: ptr char; size: csize_t; nitems: csize_t; userdata: pointer): csize_t {.cdecl.} =
  let total = int(size * nitems)
  if total <= 0:
    return 0
  let state = cast[ptr RequestResponseBuffer](userdata)
  if state != nil:
    let start = state.body.len
    state.body.setLen(start + total)
    copyMem(addr state.body[start], buffer, total)
  result = csize_t(total)

proc responseExcerpt(body: string): string {.inline.} =
  if body.len <= ResponseExcerptLimit:
    result = body
  else:
    result = body.substr(0, ResponseExcerptLimit - 1) & "..."

proc sendFatal(ctx: SchedulerContext; kind: ErrorKind; message: string) =
  SchedulerStopRequested.store(true, moRelaxed)
  ctx.fatalCh.send(FatalEvent(
    source: fesScheduler,
    errorKind: kind,
    message: boundedErrorMessage(message)
  ))

proc updateInflightCount(state: SchedulerState) =
  InflightCount.store(state.activeTransfers.len, moRelaxed)

proc windowLimitExclusive(): int =
  NextToWrite.load(moRelaxed) + Window

proc newErrorResult(seqId: SeqId; page: int; attempts: int; kind: ErrorKind; message: string): PageResult =
  PageResult(
    seqId: seqId,
    page: page,
    status: psError,
    attempts: attempts,
    text: "",
    errorKind: kind,
    errorMessage: boundedErrorMessage(message),
    httpStatus: HttpNone
  )

proc newHttpErrorResult(seqId: SeqId; page: int; attempts: int; kind: ErrorKind;
                        message: string; httpStatus: HttpCode): PageResult =
  PageResult(
    seqId: seqId,
    page: page,
    status: psError,
    attempts: attempts,
    text: "",
    errorKind: kind,
    errorMessage: boundedErrorMessage(message),
    httpStatus: httpStatus
  )

proc newSuccessResult(seqId: SeqId; page: int; attempts: int; text: string): PageResult =
  PageResult(
    seqId: seqId,
    page: page,
    status: psOk,
    attempts: attempts,
    text: text,
    errorKind: NoError,
    errorMessage: "",
    httpStatus: HttpNone
  )

proc enqueueWriterResult(state: var SchedulerState; ctx: SchedulerContext; pageResult: PageResult): bool =
  if not state.finalGuard.tryFinalizeSeqId(pageResult.seqId):
    logWarn("scheduler dropped duplicate final result")
    return true

  inc state.finalCount

  discard flushPendingSends(ctx.writerInCh, state.writerPending, MaxWriterPending)
  if ctx.writerInCh.trySend(pageResult):
    return true
  if state.writerPending.len >= MaxWriterPending:
    ctx.sendFatal(NetworkError, "writer pending buffer exceeded bound")
    return false
  state.writerPending.addLast(pageResult)
  true

proc scheduleRetry(state: var SchedulerState; task: RenderedTask; delayMs: int) =
  state.retryQueue.add(RetryItem(
    readyAt: getMonoTime() + initDuration(milliseconds = delayMs),
    task: task
  ))

proc msUntilNextRetry(state: SchedulerState): int =
  if state.retryQueue.len == 0:
    return MultiWaitMaxMs

  let now = getMonoTime()
  var minMs = MultiWaitMaxMs
  for item in state.retryQueue:
    let remaining = item.readyAt - now
    if remaining <= DurationZero:
      return 0

    var remainingMs = int(remaining.inMilliseconds)
    if remainingMs <= 0:
      remainingMs = 1
    minMs = min(minMs, remainingMs)
  result = minMs

proc retryDelayMs(state: var SchedulerState; attempt: int): int =
  let capped = backoffBaseMs(attempt)
  let jitterMax = max(1, capped div RetryJitterDivisor)
  let jitter = state.rng.rand(jitterMax)
  result = capped + jitter

proc maybeRetry(state: var SchedulerState; ctx: SchedulerContext; req: RequestContext;
                kind: ErrorKind; message: string; retryable: bool; httpStatus = HttpCode(0)): bool =
  let maxAttempts = 1 + MaxRetries
  let isWindowEligible = req.seqId < windowLimitExclusive()
  if retryable and req.attempt < maxAttempts and isWindowEligible and
      not SchedulerStopRequested.load(moRelaxed):
    let nextAttempt = req.attempt + 1
    let delayMs = retryDelayMs(state, nextAttempt)
    scheduleRetry(state, RenderedTask(
      seqId: req.seqId,
      page: req.page,
      webpBytes: req.webpBytes,
      attempt: nextAttempt
    ), delayMs)
    discard RetryCount.fetchAdd(1, moRelaxed)
    return true

  let finalResult =
    if httpStatus != HttpNone:
      newHttpErrorResult(req.seqId, req.page, req.attempt, kind, message, httpStatus)
    else:
      newErrorResult(req.seqId, req.page, req.attempt, kind, message)
  enqueueWriterResult(state, ctx, finalResult)

proc requestToCtx(task: RenderedTask; apiKey: string): RequestContext =
  result = RequestContext(
    seqId: task.seqId,
    page: task.page,
    attempt: task.attempt,
    webpBytes: task.webpBytes,
    response: RequestResponseBuffer(body: "")
  )

  let imageDataUrl = "data:image/webp;base64," & base64.encode(task.webpBytes)
  let body = buildChatCompletionRequest(OCRInstruction, imageDataUrl)

  result.easy = initEasy()
  result.headers.addHeader("Authorization: Bearer " & apiKey)
  result.headers.addHeader("Content-Type: application/json")
  result.easy.setUrl(ApiUrl)
  result.easy.setWriteCallback(writeResponseCb, cast[pointer](addr result.response))
  result.easy.setPostFields(body)
  result.easy.setHeaders(result.headers)
  result.easy.setTimeoutMs(TotalTimeoutMs)
  result.easy.setConnectTimeoutMs(ConnectTimeoutMs)
  result.easy.setSslVerify(true, true)
  result.easy.setAcceptEncoding("gzip, deflate")

proc takeNextDispatchTask(state: var SchedulerState; seqId: var SeqId; task: var RenderedTask): bool =
  let limit = windowLimitExclusive()
  var found = false
  var chosen = high(int)
  for key in state.renderedReady.keys:
    if key < limit and key < chosen:
      chosen = key
      found = true
  if not found:
    return false
  seqId = chosen
  task = state.renderedReady[chosen]
  state.renderedReady.del(chosen)
  true

proc promoteReadyRetries(state: var SchedulerState) =
  if state.retryQueue.len == 0:
    return
  let now = getMonoTime()
  let limit = windowLimitExclusive()
  var remaining: seq[RetryItem] = @[]
  remaining.setLen(0)
  for item in state.retryQueue:
    if item.readyAt <= now and item.task.seqId < limit:
      state.renderedReady[item.task.seqId] = item.task
    else:
      remaining.add(item)
  state.retryQueue = move remaining

proc refillRenderRequests(state: var SchedulerState; ctx: SchedulerContext) =
  if SchedulerStopRequested.load(moRelaxed):
    return
  if state.renderPendingCount >= LowWater:
    return
  var sendMisses = 0
  while state.renderPendingCount < HighWater and state.nextSeqToRequestRender < ctx.selectedCount:
    let seqId = state.nextSeqToRequestRender
    if seqId >= windowLimitExclusive():
      break
    if ctx.renderReqCh.trySend(RenderRequest(kind: rrkPage, seqId: seqId)):
      inc state.renderPendingCount
      inc state.nextSeqToRequestRender
      sendMisses = 0
    else:
      inc sendMisses
      if sendMisses >= 4:
        break

proc flushWriterPending(state: var SchedulerState; ctx: SchedulerContext) =
  discard flushPendingSends(ctx.writerInCh, state.writerPending, MaxWriterPending)

proc drainRendererOutputs(state: var SchedulerState; ctx: SchedulerContext): bool =
  discard tryRecvBatch(ctx.renderOutCh, state.renderOutBatch, HighWater)
  while state.renderOutBatch.len > 0:
    let output = state.renderOutBatch.popFirst()
    if state.renderPendingCount > 0:
      dec state.renderPendingCount
    case output.kind
    of rokRenderedTask:
      if not SchedulerStopRequested.load(moRelaxed):
        state.renderedReady[output.task.seqId] = output.task
    of rokRenderFailure:
      if not enqueueWriterResult(state, ctx, newErrorResult(
        output.failure.seqId,
        output.failure.page,
        output.failure.attempts,
        output.failure.errorKind,
        output.failure.errorMessage
      )):
        return false
  true

proc processCompletions(state: var SchedulerState; ctx: SchedulerContext; multi: var CurlMulti): bool =
  var msg: CURLMsg
  var msgsInQueue = 0
  while multi.tryInfoRead(msg, msgsInQueue):
    if msg.msg != CurlmsgDone:
      continue

    let key = handleKey(msg)
    if not state.activeTransfers.hasKey(key):
      logWarn("scheduler completion had unknown easy handle")
      continue

    let req = state.activeTransfers[key]
    try:
      multi.removeHandle(req.easy)
    except CatchableError as exc:
      ctx.sendFatal(NetworkError, exc.msg)
      return false

    state.activeTransfers.del(key)
    updateInflightCount(state)

    let curlCode = msg.data.result
    if curlCode != CurleOk:
      let errorKind = classifyCurlErrorKind(curlCode)
      let errMsg = "curl transfer failed code=" & $int(curlCode)
      if not maybeRetry(state, ctx, req, errorKind, errMsg, retryable = true):
        return false
      continue

    let httpCode = req.easy.responseCode()
    if httpCode == Http429:
      if not maybeRetry(
        state,
        ctx,
        req,
        RateLimit,
        "HTTP 429 rate limited",
        retryable = true,
        httpStatus = httpCode
      ):
        return false
      continue

    if httpStatusRetryable(httpCode) and httpCode != Http429:
      let msg500 = "HTTP " & $httpCode & ": " & responseExcerpt(req.response.body)
      if not maybeRetry(
        state,
        ctx,
        req,
        HttpError,
        msg500,
        retryable = true,
        httpStatus = httpCode
      ):
        return false
      continue

    if httpCode < Http200 or httpCode >= Http300:
      if not enqueueWriterResult(state, ctx, newHttpErrorResult(
        req.seqId,
        req.page,
        req.attempt,
        HttpError,
        "HTTP " & $httpCode & ": " & responseExcerpt(req.response.body),
        httpCode
      )):
        return false
      continue

    let parsed = parseChatCompletionResponse(req.response.body)
    if not parsed.ok:
      if not enqueueWriterResult(state, ctx, newErrorResult(
        req.seqId,
        req.page,
        req.attempt,
        ParseError,
        parsed.error_message
      )):
        return false
      continue

    if not enqueueWriterResult(state, ctx, newSuccessResult(
      req.seqId,
      req.page,
      req.attempt,
      parsed.text
    )):
      return false
  true

proc dispatchRequests(state: var SchedulerState; ctx: SchedulerContext; multi: var CurlMulti): bool =
  if SchedulerStopRequested.load(moRelaxed):
    return true
  while state.writerPending.len == 0 and state.activeTransfers.len < MaxInflight:
    var seqId: SeqId
    var task: RenderedTask
    if not takeNextDispatchTask(state, seqId, task):
      break
    try:
      let req = requestToCtx(task, ctx.apiKey)
      multi.addHandle(req.easy)
      state.activeTransfers[handleKey(req.easy)] = req
      updateInflightCount(state)
    except CatchableError as exc:
      if not maybeRetry(
        state,
        ctx,
        RequestContext(
          seqId: task.seqId,
          page: task.page,
          attempt: task.attempt,
          webpBytes: task.webpBytes,
          response: RequestResponseBuffer(body: "")
        ),
        NetworkError,
        exc.msg,
        retryable = true
      ):
        return false
  true

proc sendRendererStop(state: var SchedulerState; ctx: SchedulerContext) =
  if state.rendererStopSent:
    return
  ctx.renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))
  state.rendererStopSent = true

proc cancelAndFinalizeMissing(state: var SchedulerState; ctx: SchedulerContext; multi: var CurlMulti): bool =
  if state.cancelFinalized:
    return true
  state.cancelFinalized = true

  for _, req in state.activeTransfers.pairs:
    try:
      multi.removeHandle(req.easy)
    except CatchableError:
      discard
  state.activeTransfers.clear()
  updateInflightCount(state)
  state.retryQueue.setLen(0)
  state.renderedReady.clear()
  state.renderPendingCount = 0

  for seqId in 0 ..< ctx.selectedCount:
    let page =
      if seqId < ctx.selectedPages.len: ctx.selectedPages[seqId]
      else: seqId + 1
    if not enqueueWriterResult(state, ctx, newErrorResult(
      seqId,
      page,
      1,
      NetworkError,
      "cancelled before completion"
    )):
      return false

  sendRendererStop(state, ctx)
  true

proc schedulerDone(state: SchedulerState; selectedCount: int): bool =
  if SchedulerStopRequested.load(moRelaxed):
    return state.finalCount == selectedCount and
      state.activeTransfers.len == 0 and
      state.retryQueue.len == 0 and
      state.writerPending.len == 0
  state.finalCount == selectedCount and
    state.activeTransfers.len == 0 and
    state.retryQueue.len == 0 and
    state.writerPending.len == 0 and
    state.renderedReady.len == 0 and
    state.renderPendingCount == 0

proc runNetworkScheduler*(ctx: SchedulerContext) {.thread.} =
  when defined(testing):
    let testMode = getEnv("PDFOCR_TEST_MODE")
    if testMode.len > 0:
      case testMode
      of "all_ok":
        for seqId in 0 ..< ctx.selectedCount:
          let page =
            if seqId < ctx.selectedPages.len: ctx.selectedPages[seqId]
            else: seqId + 1
          ctx.writerInCh.send(newSuccessResult(seqId, page, 1, "ok"))
        ctx.renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))
      of "mixed":
        for seqId in 0 ..< ctx.selectedCount:
          let page =
            if seqId < ctx.selectedPages.len: ctx.selectedPages[seqId]
            else: seqId + 1
          if seqId mod 2 == 0:
            ctx.writerInCh.send(newSuccessResult(seqId, page, 1, "ok"))
          else:
            ctx.writerInCh.send(newErrorResult(seqId, page, 1, HttpError, "synthetic mixed failure"))
        ctx.renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))
      of "fatal":
        ctx.sendFatal(NetworkError, "synthetic fatal scheduler failure")
        ctx.renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))
      else:
        discard
      return

  var multi: CurlMulti
  try:
    multi = initMulti()
  except CatchableError as exc:
    ctx.sendFatal(NetworkError, exc.msg)
    return

  var state = SchedulerState(
    nextSeqToRequestRender: 0,
    renderPendingCount: 0,
    finalCount: 0,
    rendererStopSent: false,
    cancelFinalized: false,
    finalGuard: initFinalizationGuard(ctx.selectedCount),
    renderedReady: initTable[int, RenderedTask](),
    retryQueue: @[],
    activeTransfers: initTable[uint, RequestContext](),
    writerPending: initDeque[PageResult](),
    renderOutBatch: initDeque[RendererOutput](),
    rng: initRand(int(getMonoTime().ticks))
  )
  updateInflightCount(state)

  while true:
    if SchedulerStopRequested.load(moRelaxed):
      if not cancelAndFinalizeMissing(state, ctx, multi):
        break

    flushWriterPending(state, ctx)

    if not drainRendererOutputs(state, ctx):
      SchedulerStopRequested.store(true, moRelaxed)
      if not cancelAndFinalizeMissing(state, ctx, multi):
        break
      continue

    promoteReadyRetries(state)
    refillRenderRequests(state, ctx)

    if not dispatchRequests(state, ctx, multi):
      SchedulerStopRequested.store(true, moRelaxed)
      if not cancelAndFinalizeMissing(state, ctx, multi):
        break
      continue

    if state.activeTransfers.len > 0:
      try:
        discard multi.perform()
        discard multi.poll(MultiWaitMaxMs)
      except CatchableError as exc:
        ctx.sendFatal(NetworkError, exc.msg)
        continue
      if not processCompletions(state, ctx, multi):
        SchedulerStopRequested.store(true, moRelaxed)
        if not cancelAndFinalizeMissing(state, ctx, multi):
          break
        continue
    else:
      let waitMs = min(MultiWaitMaxMs, msUntilNextRetry(state))
      if waitMs > 0:
        sleep(waitMs)

    if schedulerDone(state, ctx.selectedCount):
      sendRendererStop(state, ctx)
      break
