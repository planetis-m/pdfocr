import std/[atomics, deques, monotimes, os, random, tables, times]
import threading/channels
import ./bindings/curl
import ./[constants, curl, errors, http_batch_client, json_codec, logging, types]

const
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

  SchedulerState = object
    nextSeqToRequestRender: int
    renderPendingCount: int
    finalCount: int
    rendererStopSent: bool
    cancelFinalized: bool
    finalGuard: FinalizationGuard
    renderedReady: Table[int, RenderedTask]
    retryQueue: seq[RetryItem]
    batchClient: HttpBatchClient
    writerPending: Deque[PageResult]
    renderOutBatch: Deque[RendererOutput]
    rng: Rand

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
  InflightCount.store(state.batchClient.inflightCount(), moRelaxed)

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

proc maybeRetry(state: var SchedulerState; ctx: SchedulerContext; seqId: SeqId; page: int;
                attempt: int; webpBytes: seq[byte]; kind: ErrorKind;
                message: string; retryable: bool; httpStatus = HttpCode(0)): bool =
  let maxAttempts = 1 + MaxRetries
  let isWindowEligible = seqId < windowLimitExclusive()
  if retryable and attempt < maxAttempts and isWindowEligible and
      not SchedulerStopRequested.load(moRelaxed):
    let nextAttempt = attempt + 1
    let delayMs = retryDelayMs(state, nextAttempt)
    scheduleRetry(state, RenderedTask(
      seqId: seqId,
      page: page,
      webpBytes: webpBytes,
      attempt: nextAttempt
    ), delayMs)
    discard RetryCount.fetchAdd(1, moRelaxed)
    return true

  let finalResult =
    if httpStatus != HttpNone:
      newHttpErrorResult(seqId, page, attempt, kind, message, httpStatus)
    else:
      newErrorResult(seqId, page, attempt, kind, message)
  enqueueWriterResult(state, ctx, finalResult)

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

proc processCompletions(state: var SchedulerState; ctx: SchedulerContext): bool =
  result = true
  var completion: BatchCompletion
  while result:
    let status =
      try:
        state.batchClient.tryReadCompletion(completion)
      except CatchableError:
        ctx.sendFatal(NetworkError, getCurrentExceptionMsg())
        return false

    case status
    of bcsNone:
      break
    of bcsUnknownHandle:
      logWarn("scheduler completion had unknown easy handle")
    of bcsDone:
      let req = completion.request
      updateInflightCount(state)
      try:
        let curlCode = completion.curlCode
        if curlCode != CURLE_OK:
          let errorKind = classifyCurlErrorKind(curlCode)
          let errMsg = "curl transfer failed code=" & $int(curlCode)
          result = maybeRetry(
            state,
            ctx,
            req.seqId,
            req.page,
            req.attempt,
            req.webpBytes,
            errorKind,
            errMsg,
            retryable = true
          )
        else:
          let httpCode = req.easy.responseCode()
          if httpCode == Http429:
            result = maybeRetry(
              state,
              ctx,
              req.seqId,
              req.page,
              req.attempt,
              req.webpBytes,
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
              req.seqId,
              req.page,
              req.attempt,
              req.webpBytes,
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
        state.batchClient.recycleEasy(req.easy)

proc dispatchRequests(state: var SchedulerState; ctx: SchedulerContext): bool =
  if SchedulerStopRequested.load(moRelaxed):
    return true
  while state.writerPending.len == 0 and state.batchClient.inflightCount() < MaxInflight:
    var seqId: SeqId
    var task: RenderedTask
    if not takeNextDispatchTask(state, seqId, task):
      break
    try:
      state.batchClient.submitRenderedTask(task, ctx.apiKey)
      updateInflightCount(state)
    except CatchableError:
      if not maybeRetry(
        state,
        ctx,
        task.seqId,
        task.page,
        task.attempt,
        task.webpBytes,
        NetworkError,
        getCurrentExceptionMsg(),
        retryable = true
      ):
        return false
  true

proc sendRendererStop(state: var SchedulerState; ctx: SchedulerContext) =
  if state.rendererStopSent:
    return
  ctx.renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))
  state.rendererStopSent = true

proc cancelAndFinalizeMissing(state: var SchedulerState; ctx: SchedulerContext): bool =
  if state.cancelFinalized:
    return true
  state.cancelFinalized = true

  state.batchClient.cancelAllActive()
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
      state.batchClient.inflightCount() == 0 and
      state.retryQueue.len == 0 and
      state.writerPending.len == 0
  state.finalCount == selectedCount and
    state.batchClient.inflightCount() == 0 and
    state.retryQueue.len == 0 and
    state.writerPending.len == 0 and
    state.renderedReady.len == 0 and
    state.renderPendingCount == 0

proc runNetworkScheduler*(ctx: SchedulerContext) {.thread.} =
  var state: SchedulerState
  try:
    state = SchedulerState(
      nextSeqToRequestRender: 0,
      renderPendingCount: 0,
      finalCount: 0,
      rendererStopSent: false,
      cancelFinalized: false,
      finalGuard: initFinalizationGuard(ctx.selectedCount),
      renderedReady: initTable[int, RenderedTask](),
      retryQueue: @[],
      batchClient: initHttpBatchClient(),
      writerPending: initDeque[PageResult](),
      renderOutBatch: initDeque[RendererOutput](),
      rng: initRand(int(getMonoTime().ticks))
    )
  except CatchableError:
    ctx.sendFatal(NetworkError, getCurrentExceptionMsg())
    return
  updateInflightCount(state)

  while true:
    if SchedulerStopRequested.load(moRelaxed):
      if not cancelAndFinalizeMissing(state, ctx):
        break

    flushWriterPending(state, ctx)

    if not drainRendererOutputs(state, ctx):
      SchedulerStopRequested.store(true, moRelaxed)
      if not cancelAndFinalizeMissing(state, ctx):
        break
      continue

    promoteReadyRetries(state)
    refillRenderRequests(state, ctx)

    if not dispatchRequests(state, ctx):
      SchedulerStopRequested.store(true, moRelaxed)
      if not cancelAndFinalizeMissing(state, ctx):
        break
      continue

    if state.batchClient.inflightCount() > 0:
      try:
        state.batchClient.performAndPoll(MultiWaitMaxMs)
      except CatchableError:
        ctx.sendFatal(NetworkError, getCurrentExceptionMsg())
        continue
      if not processCompletions(state, ctx):
        SchedulerStopRequested.store(true, moRelaxed)
        if not cancelAndFinalizeMissing(state, ctx):
          break
        continue
    else:
      let waitMs = min(MultiWaitMaxMs, msUntilNextRetry(state))
      if waitMs > 0:
        sleep(waitMs)

    if schedulerDone(state, ctx.selectedCount):
      sendRendererStop(state, ctx)
      break
