import std/[atomics, base64, deques, monotimes, os, random, tables, times]
import threading/channels
import ./bindings/curl
import ./[constants, curl, errors, json_codec, logging, types]

const
  OCR_INSTRUCTION = "Extract all readable text exactly."
  MAX_WRITER_PENDING = WINDOW + MAX_INFLIGHT
  RETRY_JITTER_DIVISOR = 2
  RESPONSE_EXCERPT_LIMIT = 240

proc slidingWindowAllows*(seqId: int; nextToWrite: int): bool {.inline.} =
  seqId < nextToWrite + WINDOW

proc classifyCurlErrorKind*(curlCode: CURLcode): ErrorKind {.inline.} =
  if curlCode == CURLE_OPERATION_TIMEDOUT: TIMEOUT else: NETWORK_ERROR

proc httpStatusRetryable*(httpStatus: int): bool {.inline.} =
  httpStatus == 429 or (httpStatus >= 500 and httpStatus < 600)

proc backoffBaseMs*(attempt: int; baseDelayMs: int = RETRY_BASE_DELAY_MS;
                    maxDelayMs: int = RETRY_MAX_DELAY_MS): int =
  let exponent = if attempt <= 1: 0 else: attempt - 1
  var raw = baseDelayMs.int64
  for _ in 0 ..< exponent:
    raw = raw * 2
    if raw >= maxDelayMs.int64:
      raw = maxDelayMs.int64
      break
  min(raw, maxDelayMs.int64).int

proc backoffWithJitterMs*(attempt: int; seed: int;
                          baseDelayMs: int = RETRY_BASE_DELAY_MS;
                          maxDelayMs: int = RETRY_MAX_DELAY_MS): int =
  let capped = backoffBaseMs(attempt, baseDelayMs, maxDelayMs)
  let jitterMax = max(1, capped div RETRY_JITTER_DIVISOR)
  var rng = initRand(seed)
  capped + rng.rand(jitterMax)

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
  csize_t(total)

proc responseExcerpt(body: string): string =
  if body.len <= RESPONSE_EXCERPT_LIMIT:
    return body
  body[0 ..< RESPONSE_EXCERPT_LIMIT] & "..."

proc sendFatal(ctx: SchedulerContext; kind: ErrorKind; message: string) =
  SCHEDULER_STOP_REQUESTED.store(true, moRelaxed)
  ctx.fatalCh.send(FatalEvent(
    source: fesScheduler,
    errorKind: kind,
    message: boundedErrorMessage(message)
  ))

proc updateInflightCount(state: SchedulerState) =
  INFLIGHT_COUNT.store(state.activeTransfers.len, moRelaxed)

proc windowLimitExclusive(): int =
  NEXT_TO_WRITE.load(moRelaxed) + WINDOW

proc newErrorResult(seqId: SeqId; page: int; attempts: int; kind: ErrorKind; message: string): PageResult =
  PageResult(
    seqId: seqId,
    page: page,
    status: psError,
    attempts: attempts,
    text: "",
    errorKind: kind,
    errorMessage: boundedErrorMessage(message),
    httpStatus: 0,
    hasHttpStatus: false
  )

proc newHttpErrorResult(seqId: SeqId; page: int; attempts: int; kind: ErrorKind;
                        message: string; httpStatus: int): PageResult =
  PageResult(
    seqId: seqId,
    page: page,
    status: psError,
    attempts: attempts,
    text: "",
    errorKind: kind,
    errorMessage: boundedErrorMessage(message),
    httpStatus: httpStatus,
    hasHttpStatus: true
  )

proc newSuccessResult(seqId: SeqId; page: int; attempts: int; text: string): PageResult =
  PageResult(
    seqId: seqId,
    page: page,
    status: psOk,
    attempts: attempts,
    text: text,
    errorKind: PARSE_ERROR,
    errorMessage: "",
    httpStatus: 0,
    hasHttpStatus: false
  )

proc enqueueWriterResult(state: var SchedulerState; ctx: SchedulerContext; pageResult: PageResult): bool =
  if not state.finalGuard.tryFinalizeSeqId(pageResult.seqId):
    logWarn("scheduler dropped duplicate final result")
    return true

  inc state.finalCount

  discard flushPendingSends(ctx.writerInCh, state.writerPending, MAX_WRITER_PENDING)
  if ctx.writerInCh.trySend(pageResult):
    return true
  if state.writerPending.len >= MAX_WRITER_PENDING:
    ctx.sendFatal(NETWORK_ERROR, "writer pending buffer exceeded bound")
    return false
  state.writerPending.addLast(pageResult)
  true

proc scheduleRetry(state: var SchedulerState; task: RenderedTask; delayMs: int) =
  state.retryQueue.add(RetryItem(
    readyAt: getMonoTime() + initDuration(milliseconds = delayMs),
    task: task
  ))

proc retryDelayMs(state: var SchedulerState; attempt: int): int =
  let capped = backoffBaseMs(attempt)
  let jitterMax = max(1, capped div RETRY_JITTER_DIVISOR)
  let jitter = state.rng.rand(jitterMax)
  capped + jitter

proc maybeRetry(state: var SchedulerState; ctx: SchedulerContext; req: RequestContext;
                kind: ErrorKind; message: string; retryable: bool;
                hasHttpStatus: bool = false; httpStatus: int = 0): bool =
  let maxAttempts = 1 + MAX_RETRIES
  let isWindowEligible = req.seqId < windowLimitExclusive()
  if retryable and req.attempt < maxAttempts and isWindowEligible and
     not SCHEDULER_STOP_REQUESTED.load(moRelaxed):
    let nextAttempt = req.attempt + 1
    let delayMs = retryDelayMs(state, nextAttempt)
    scheduleRetry(state, RenderedTask(
      seqId: req.seqId,
      page: req.page,
      webpBytes: req.webpBytes,
      attempt: nextAttempt
    ), delayMs)
    discard RETRY_COUNT.fetchAdd(1, moRelaxed)
    return true

  let finalResult =
    if hasHttpStatus:
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
  let body = buildChatCompletionRequest(OCR_INSTRUCTION, imageDataUrl)

  result.easy = initEasy()
  result.headers.addHeader("Authorization: Bearer " & apiKey)
  result.headers.addHeader("Content-Type: application/json")
  result.easy.setUrl(API_URL)
  result.easy.setWriteCallback(writeResponseCb, cast[pointer](addr result.response))
  result.easy.setPostFields(body)
  result.easy.setHeaders(result.headers)
  result.easy.setTimeoutMs(TOTAL_TIMEOUT_MS)
  result.easy.setConnectTimeoutMs(CONNECT_TIMEOUT_MS)
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
  if SCHEDULER_STOP_REQUESTED.load(moRelaxed):
    return
  if state.renderPendingCount >= LOW_WATER:
    return
  var sendMisses = 0
  while state.renderPendingCount < HIGH_WATER and state.nextSeqToRequestRender < ctx.selectedCount:
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
  discard flushPendingSends(ctx.writerInCh, state.writerPending, MAX_WRITER_PENDING)

proc drainRendererOutputs(state: var SchedulerState; ctx: SchedulerContext): bool =
  discard tryRecvBatch(ctx.renderOutCh, state.renderOutBatch, HIGH_WATER)
  while state.renderOutBatch.len > 0:
    let output = state.renderOutBatch.popFirst()
    if state.renderPendingCount > 0:
      dec state.renderPendingCount
    case output.kind
    of rokRenderedTask:
      if not SCHEDULER_STOP_REQUESTED.load(moRelaxed):
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
    if msg.msg != CURLMSG_DONE:
      continue

    let key = handleKey(msg)
    if not state.activeTransfers.hasKey(key):
      logWarn("scheduler completion had unknown easy handle")
      continue

    let req = state.activeTransfers[key]
    try:
      multi.removeHandle(req.easy)
    except CatchableError as exc:
      ctx.sendFatal(NETWORK_ERROR, exc.msg)
      return false

    state.activeTransfers.del(key)
    updateInflightCount(state)

    let curlCode = msg.data.result
    if curlCode != CURLE_OK:
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
        RATE_LIMIT,
        "HTTP 429 rate limited",
        retryable = true,
        hasHttpStatus = true,
        httpStatus = int(httpCode)
      ):
        return false
      continue

    if httpStatusRetryable(int(httpCode)) and httpCode != Http429:
      let msg500 = "HTTP " & $httpCode & ": " & responseExcerpt(req.response.body)
      if not maybeRetry(
        state,
        ctx,
        req,
        HTTP_ERROR,
        msg500,
        retryable = true,
        hasHttpStatus = true,
        httpStatus = int(httpCode)
      ):
        return false
      continue

    if httpCode < Http200 or httpCode >= Http300:
      if not enqueueWriterResult(state, ctx, newHttpErrorResult(
        req.seqId,
        req.page,
        req.attempt,
        HTTP_ERROR,
        "HTTP " & $httpCode & ": " & responseExcerpt(req.response.body),
        int(httpCode)
      )):
        return false
      continue

    let parsed = parseChatCompletionResponse(req.response.body)
    if not parsed.ok:
      if not enqueueWriterResult(state, ctx, newErrorResult(
        req.seqId,
        req.page,
        req.attempt,
        PARSE_ERROR,
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
  if SCHEDULER_STOP_REQUESTED.load(moRelaxed):
    return true
  while state.writerPending.len == 0 and state.activeTransfers.len < MAX_INFLIGHT:
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
        NETWORK_ERROR,
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
      NETWORK_ERROR,
      "cancelled before completion"
    )):
      return false

  sendRendererStop(state, ctx)
  true

proc schedulerDone(state: SchedulerState; selectedCount: int): bool =
  if SCHEDULER_STOP_REQUESTED.load(moRelaxed):
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
            ctx.writerInCh.send(newErrorResult(seqId, page, 1, HTTP_ERROR, "synthetic mixed failure"))
        ctx.renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))
      of "fatal":
        ctx.sendFatal(NETWORK_ERROR, "synthetic fatal scheduler failure")
        ctx.renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))
      else:
        discard
      return

  var multi: CurlMulti
  try:
    multi = initMulti()
  except CatchableError as exc:
    ctx.sendFatal(NETWORK_ERROR, exc.msg)
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
    if SCHEDULER_STOP_REQUESTED.load(moRelaxed):
      if not cancelAndFinalizeMissing(state, ctx, multi):
        break

    flushWriterPending(state, ctx)

    if not drainRendererOutputs(state, ctx):
      SCHEDULER_STOP_REQUESTED.store(true, moRelaxed)
      if not cancelAndFinalizeMissing(state, ctx, multi):
        break
      continue

    promoteReadyRetries(state)
    refillRenderRequests(state, ctx)

    if not dispatchRequests(state, ctx, multi):
      SCHEDULER_STOP_REQUESTED.store(true, moRelaxed)
      if not cancelAndFinalizeMissing(state, ctx, multi):
        break
      continue

    if state.activeTransfers.len > 0:
      try:
        discard multi.perform()
        discard multi.poll(MULTI_WAIT_MAX_MS)
      except CatchableError as exc:
        ctx.sendFatal(NETWORK_ERROR, exc.msg)
        continue
      if not processCompletions(state, ctx, multi):
        SCHEDULER_STOP_REQUESTED.store(true, moRelaxed)
        if not cancelAndFinalizeMissing(state, ctx, multi):
          break
        continue
    elif state.writerPending.len > 0:
      sleep(1)

    if schedulerDone(state, ctx.selectedCount):
      sendRendererStop(state, ctx)
      break
