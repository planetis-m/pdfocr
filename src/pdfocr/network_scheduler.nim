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
  result = if curlCode == CURLE_OPERATION_TIMEDOUT: Timeout else: NetworkError

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
  RequestContext {.acyclic.} = ref object
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
    idleEasy: seq[CurlEasy]
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
    result = true
  elif state.writerPending.len >= MaxWriterPending:
    ctx.sendFatal(NetworkError, "writer pending buffer exceeded bound")
    result = false
  else:
    state.writerPending.addLast(pageResult)
    result = true

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

proc acquireEasy(state: var SchedulerState): CurlEasy =
  if state.idleEasy.len == 0:
    return initEasy()
  result = state.idleEasy.pop()
  result.reset()

proc recycleEasy(state: var SchedulerState; easy: sink CurlEasy) =
  state.idleEasy.add(easy)

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
    result = true
  else:
    let finalResult =
      if httpStatus != HttpNone:
        newHttpErrorResult(req.seqId, req.page, req.attempt, kind, message, httpStatus)
      else:
        newErrorResult(req.seqId, req.page, req.attempt, kind, message)
    result = enqueueWriterResult(state, ctx, finalResult)

proc requestToCtx(task: RenderedTask; apiKey: string; easy: var CurlEasy): RequestContext =
  result = RequestContext(
    seqId: task.seqId,
    page: task.page,
    attempt: task.attempt,
    webpBytes: task.webpBytes,
    response: RequestResponseBuffer(body: "")
  )

  let imageDataUrl = "data:image/webp;base64," & base64.encode(task.webpBytes)
  let body = buildChatCompletionRequest(OCRInstruction, imageDataUrl)

  result.headers.addHeader("Authorization: Bearer " & apiKey)
  result.headers.addHeader("Content-Type: application/json")
  easy.setUrl(ApiUrl)
  easy.setWriteCallback(writeResponseCb, cast[pointer](addr result.response))
  easy.setPostFields(body)
  easy.setHeaders(result.headers)
  easy.setTimeoutMs(TotalTimeoutMs)
  easy.setConnectTimeoutMs(ConnectTimeoutMs)
  easy.setSslVerify(true, true)
  easy.setAcceptEncoding("gzip, deflate")

proc takeNextDispatchTask(state: var SchedulerState; seqId: var SeqId; task: var RenderedTask): bool =
  let limit = windowLimitExclusive()
  var chosen = high(int)
  for key in state.renderedReady.keys:
    if key < limit and key < chosen:
      chosen = key
  if chosen == high(int):
    return false
  seqId = chosen
  task = state.renderedReady[chosen]
  state.renderedReady.del(chosen)
  result = true

proc promoteReadyRetries(state: var SchedulerState) =
  if state.retryQueue.len == 0:
    return
  let now = getMonoTime()
  let limit = windowLimitExclusive()
  var remaining = newSeqOfCap[RetryItem](state.retryQueue.len)
  for item in state.retryQueue:
    if item.readyAt <= now and item.task.seqId < limit:
      state.renderedReady[item.task.seqId] = item.task
    else:
      remaining.add(item)
  state.retryQueue = ensureMove(remaining)

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
  result = true
  discard tryRecvBatch(ctx.renderOutCh, state.renderOutBatch, HighWater)
  while result and state.renderOutBatch.len > 0:
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
        result = false

proc processCompletions(state: var SchedulerState; ctx: SchedulerContext; multi: var CurlMulti): bool =
  result = true
  var msg: CURLMsg
  var msgsInQueue = 0
  while result and multi.tryInfoRead(msg, msgsInQueue):
    if msg.msg == CURLMSG_DONE:
      let key = handleKey(msg)
      if not state.activeTransfers.hasKey(key):
        logWarn("scheduler completion had unknown easy handle")
      else:
        var removeOk = true
        try:
          multi.removeHandle(msg)
        except CatchableError:
          ctx.sendFatal(NetworkError, getCurrentExceptionMsg())
          removeOk = false
          result = false

        if removeOk:
          var req: RequestContext
          if not state.activeTransfers.pop(key, req):
            logWarn("scheduler completion missing active transfer during pop")
            result = false
            removeOk = false
          updateInflightCount(state)
          if removeOk:
            try:
              let curlCode = msg.data.result
              if curlCode != CURLE_OK:
                let errorKind = classifyCurlErrorKind(curlCode)
                let errMsg = "curl transfer failed code=" & $int(curlCode)
                result = maybeRetry(state, ctx, req, errorKind, errMsg, retryable = true)
              else:
                let httpCode = req.easy.responseCode()
                if httpCode == Http429:
                  result = maybeRetry(
                    state,
                    ctx,
                    req,
                    RateLimit,
                    "HTTP 429 rate limited",
                    retryable = true,
                    httpStatus = httpCode
                  )
                elif httpStatusRetryable(httpCode) and httpCode != Http429:
                  let msg500 = "HTTP " & $httpCode & ": " & responseExcerpt(req.response.body)
                  result = maybeRetry(
                    state,
                    ctx,
                    req,
                    HttpError,
                    msg500,
                    retryable = true,
                    httpStatus = httpCode
                  )
                elif httpCode < Http200 or httpCode >= Http300:
                  result = enqueueWriterResult(state, ctx, newHttpErrorResult(
                    req.seqId,
                    req.page,
                    req.attempt,
                    HttpError,
                    "HTTP " & $httpCode & ": " & responseExcerpt(req.response.body),
                    httpCode
                  ))
                else:
                  let parsed = parseChatCompletionResponse(req.response.body)
                  if not parsed.ok:
                    result = enqueueWriterResult(state, ctx, newErrorResult(
                      req.seqId,
                      req.page,
                      req.attempt,
                      ParseError,
                      parsed.error_message
                    ))
                  else:
                    result = enqueueWriterResult(state, ctx, newSuccessResult(
                      req.seqId,
                      req.page,
                      req.attempt,
                      parsed.text
                    ))
            finally:
              state.recycleEasy(req.easy)

proc dispatchRequests(state: var SchedulerState; ctx: SchedulerContext; multi: var CurlMulti): bool =
  if SchedulerStopRequested.load(moRelaxed):
    return true
  result = true
  while result and state.writerPending.len == 0 and state.activeTransfers.len < MaxInflight:
    var seqId: SeqId
    var task: RenderedTask
    if not takeNextDispatchTask(state, seqId, task):
      break
    try:
      var easy = state.acquireEasy()
      let req = requestToCtx(task, ctx.apiKey, easy)
      req.easy = easy
      multi.addHandle(easy)
      let key = handleKey(easy)
      state.activeTransfers[key] = req
      updateInflightCount(state)
    except CatchableError:
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
        getCurrentExceptionMsg(),
        retryable = true
      ):
        result = false

proc sendRendererStop(state: var SchedulerState; ctx: SchedulerContext) =
  if state.rendererStopSent:
    return
  ctx.renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))
  state.rendererStopSent = true

proc cancelAndFinalizeMissing(state: var SchedulerState; ctx: SchedulerContext; multi: var CurlMulti): bool =
  if state.cancelFinalized:
    return true
  state.cancelFinalized = true
  result = true

  var activeKeys = newSeqOfCap[uint](state.activeTransfers.len)
  for key in state.activeTransfers.keys:
    activeKeys.add(key)
  for key in activeKeys:
    var req: RequestContext
    if state.activeTransfers.pop(key, req):
      try:
        multi.removeHandle(req.easy)
      except CatchableError:
        discard
      state.recycleEasy(req.easy)
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
      result = false
      break

  if result:
    sendRendererStop(state, ctx)

proc schedulerDone(state: SchedulerState; selectedCount: int): bool =
  let baseDone = state.finalCount == selectedCount and
    state.activeTransfers.len == 0 and
    state.retryQueue.len == 0 and
    state.writerPending.len == 0
  if SchedulerStopRequested.load(moRelaxed):
    result = baseDone
  else:
    result = baseDone and
      state.renderedReady.len == 0 and
      state.renderPendingCount == 0

proc runNetworkScheduler*(ctx: SchedulerContext) {.thread.} =
  var multi: CurlMulti
  try:
    multi = initMulti()
  except CatchableError:
    ctx.sendFatal(NetworkError, getCurrentExceptionMsg())
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
    idleEasy: @[],
    writerPending: initDeque[PageResult](),
    renderOutBatch: initDeque[RendererOutput](),
    rng: initRand(int(getMonoTime().ticks))
  )
  updateInflightCount(state)

  while true:
    var continueLoop = true

    if SchedulerStopRequested.load(moRelaxed):
      if not cancelAndFinalizeMissing(state, ctx, multi):
        break

    flushWriterPending(state, ctx)

    if continueLoop and not drainRendererOutputs(state, ctx):
      SchedulerStopRequested.store(true, moRelaxed)
      if not cancelAndFinalizeMissing(state, ctx, multi):
        break
      continueLoop = false

    if continueLoop:
      promoteReadyRetries(state)
      refillRenderRequests(state, ctx)

      if not dispatchRequests(state, ctx, multi):
        SchedulerStopRequested.store(true, moRelaxed)
        if not cancelAndFinalizeMissing(state, ctx, multi):
          break
        continueLoop = false

    if continueLoop:
      if state.activeTransfers.len > 0:
        try:
          discard multi.perform()
          discard multi.poll(MultiWaitMaxMs)
        except CatchableError:
          ctx.sendFatal(NetworkError, getCurrentExceptionMsg())
          continueLoop = false
        if continueLoop and not processCompletions(state, ctx, multi):
          SchedulerStopRequested.store(true, moRelaxed)
          if not cancelAndFinalizeMissing(state, ctx, multi):
            break
          continueLoop = false
      else:
        let waitMs = min(MultiWaitMaxMs, msUntilNextRetry(state))
        if waitMs > 0:
          sleep(waitMs)

    if continueLoop and schedulerDone(state, ctx.selectedCount):
      sendRendererStop(state, ctx)
      break
