import std/[atomics, base64, monotimes, os, random, tables, times]
import threading/channels
import ./bindings/curl
import ./[constants, curl, errors, json_codec, types]

const
  OCRInstruction = "Extract all readable text exactly."
  RetryJitterDivisor = 2
  ResponseExcerptLimit = 240

type
  RetryItem = object
    readyAt: MonoTime
    task: OcrTask
    attempt: int

  RequestResponseBuffer = object
    body: string

  RequestContext {.acyclic.} = ref object
    task: OcrTask
    attempt: int
    response: RequestResponseBuffer
    easy: CurlEasy
    headers: CurlSlist

proc writeResponseCb(buffer: ptr char; size: csize_t; nitems: csize_t; userdata: pointer): csize_t {.cdecl.} =
  let total = int(size * nitems)
  if total <= 0:
    result = 0
  else:
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

proc classifyCurlErrorKind*(curlCode: CURLcode): ErrorKind {.inline.} =
  result = if curlCode == CURLE_OPERATION_TIMEDOUT: Timeout else: NetworkError

proc httpStatusRetryable*(httpStatus: HttpCode): bool {.inline.} =
  result = httpStatus == Http429 or (httpStatus >= Http500 and httpStatus < Http600)

proc backoffBaseMs*(attempt: int): int =
  let exponent = if attempt <= 1: 0 else: attempt - 1
  let raw = RetryBaseDelayMs shl exponent
  result = min(raw, RetryMaxDelayMs)

proc retryDelayMs(rng: var Rand; attempt: int): int =
  let capped = backoffBaseMs(attempt)
  let jitterMax = max(1, capped div RetryJitterDivisor)
  let jitter = rng.rand(jitterMax)
  result = capped + jitter

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

proc scheduleRetry(retryQueue: var seq[RetryItem]; task: OcrTask; attempt: int; delayMs: int) =
  retryQueue.add(RetryItem(
    readyAt: getMonoTime() + initDuration(milliseconds = delayMs),
    task: task,
    attempt: attempt
  ))

proc acquireEasy(idleEasy: var seq[CurlEasy]): CurlEasy =
  if idleEasy.len == 0:
    result = initEasy()
  else:
    result = idleEasy.pop()
    result.reset()

proc recycleEasy(idleEasy: var seq[CurlEasy]; easy: sink CurlEasy) =
  idleEasy.add(easy)

proc shouldRetry(attempt: int): bool {.inline.} =
  attempt < (1 + MaxRetries)

proc msUntilNextRetry(retryQueue: seq[RetryItem]): int =
  if retryQueue.len == 0:
    result = MultiWaitMaxMs
  else:
    let now = getMonoTime()
    var minMs = MultiWaitMaxMs
    for item in retryQueue:
      let remaining = item.readyAt - now
      if remaining <= DurationZero:
        minMs = 0
        break
      var remainingMs = int(remaining.inMilliseconds)
      if remainingMs <= 0:
        remainingMs = 1
      minMs = min(minMs, remainingMs)
    result = minMs

proc popReadyRetry(retryQueue: var seq[RetryItem]; task: var OcrTask; attempt: var int): bool =
  if retryQueue.len == 0:
    result = false
  else:
    let now = getMonoTime()
    var chosen = -1
    for i, item in retryQueue:
      if item.readyAt <= now:
        chosen = i
        break

    if chosen < 0:
      result = false
    else:
      let selected = retryQueue[chosen]
      task = selected.task
      attempt = selected.attempt
      retryQueue[chosen] = retryQueue[^1]
      retryQueue.setLen(retryQueue.len - 1)
      result = true

proc enqueueFinalResult(ctx: NetworkWorkerContext; result: sink PageResult) =
  ctx.resultCh.send(result)

proc finalizeOrRetry(ctx: NetworkWorkerContext; retryQueue: var seq[RetryItem]; rng: var Rand;
                     task: OcrTask; attempt: int; retryable: bool;
                     kind: ErrorKind; message: string; httpStatus = HttpNone) =
  if retryable and shouldRetry(attempt):
    let nextAttempt = attempt + 1
    discard RetryCount.fetchAdd(1, moRelaxed)
    scheduleRetry(retryQueue, task, nextAttempt, retryDelayMs(rng, nextAttempt))
  else:
    if httpStatus == HttpNone:
      ctx.enqueueFinalResult(newErrorResult(task.seqId, task.page, attempt, kind, message))
    else:
      ctx.enqueueFinalResult(newHttpErrorResult(task.seqId, task.page, attempt, kind, message, httpStatus))

proc dispatchRequest(multi: var CurlMulti; active: var Table[uint, RequestContext];
                     idleEasy: var seq[CurlEasy];
                     task: OcrTask; attempt: int; apiKey: string): tuple[ok: bool, message: string] =
  var req: RequestContext
  try:
    let easy = acquireEasy(idleEasy)
    req = RequestContext(
      task: task,
      attempt: attempt,
      response: RequestResponseBuffer(body: ""),
      easy: easy
    )

    let imageDataUrl = "data:image/webp;base64," & base64.encode(task.webpBytes)
    let body = buildChatCompletionRequest(OCRInstruction, imageDataUrl)

    req.headers.addHeader("Authorization: Bearer " & apiKey)
    req.headers.addHeader("Content-Type: application/json")
    req.easy.setUrl(ApiUrl)
    req.easy.setWriteCallback(writeResponseCb, cast[pointer](addr req.response))
    req.easy.setPostFields(body)
    req.easy.setHeaders(req.headers)
    req.easy.setTimeoutMs(TotalTimeoutMs)
    req.easy.setConnectTimeoutMs(ConnectTimeoutMs)
    req.easy.setSslVerify(true, true)
    req.easy.setAcceptEncoding("gzip, deflate")
    multi.addHandle(req.easy)
    active[handleKey(req.easy)] = req
    result = (ok: true, message: "")
  except CatchableError:
    if req != nil and req.easy != nil:
      recycleEasy(idleEasy, req.easy)
    result = (ok: false, message: boundedErrorMessage(getCurrentExceptionMsg()))

proc processCompletions(ctx: NetworkWorkerContext; multi: var CurlMulti;
                        active: var Table[uint, RequestContext];
                        retryQueue: var seq[RetryItem];
                        idleEasy: var seq[CurlEasy];
                        rng: var Rand) =
  var msg: CURLMsg
  var msgsInQueue = 0
  while multi.tryInfoRead(msg, msgsInQueue):
    if msg.msg == CURLMSG_DONE:
      let key = handleKey(msg)
      if active.hasKey(key):
        var req: RequestContext
        if active.pop(key, req):
          var removed = false
          try:
            multi.removeHandle(msg)
            removed = true
          except CatchableError:
            finalizeOrRetry(
              ctx,
              retryQueue,
              rng,
              req.task,
              req.attempt,
              retryable = true,
              kind = NetworkError,
              message = boundedErrorMessage(getCurrentExceptionMsg())
            )

          if removed:
            try:
              let curlCode = msg.data.result
              if curlCode != CURLE_OK:
                finalizeOrRetry(
                  ctx,
                  retryQueue,
                  rng,
                  req.task,
                  req.attempt,
                  retryable = true,
                  kind = classifyCurlErrorKind(curlCode),
                  message = "curl transfer failed code=" & $int(curlCode)
                )
              else:
                let responseBody = req.response.body
                var httpCode = HttpNone
                var haveHttpCode = true
                try:
                  httpCode = req.easy.responseCode()
                except CatchableError:
                  finalizeOrRetry(
                    ctx,
                    retryQueue,
                    rng,
                    req.task,
                    req.attempt,
                    retryable = true,
                    kind = NetworkError,
                    message = boundedErrorMessage(getCurrentExceptionMsg())
                  )
                  haveHttpCode = false

                if haveHttpCode:
                  if httpCode == Http429:
                    finalizeOrRetry(
                      ctx,
                      retryQueue,
                      rng,
                      req.task,
                      req.attempt,
                      retryable = true,
                      kind = RateLimit,
                      message = "HTTP 429 rate limited",
                      httpStatus = httpCode
                    )
                  elif httpStatusRetryable(httpCode):
                    finalizeOrRetry(
                      ctx,
                      retryQueue,
                      rng,
                      req.task,
                      req.attempt,
                      retryable = true,
                      kind = HttpError,
                      message = "HTTP " & $httpCode & ": " & responseExcerpt(responseBody),
                      httpStatus = httpCode
                    )
                  elif httpCode < Http200 or httpCode >= Http300:
                    ctx.enqueueFinalResult(newHttpErrorResult(
                      req.task.seqId,
                      req.task.page,
                      req.attempt,
                      HttpError,
                      "HTTP " & $httpCode & ": " & responseExcerpt(responseBody),
                      httpCode
                    ))
                  else:
                    let parsed = parseChatCompletionResponse(responseBody)
                    if not parsed.ok:
                      ctx.enqueueFinalResult(newErrorResult(
                        req.task.seqId,
                        req.task.page,
                        req.attempt,
                        ParseError,
                        parsed.error_message
                      ))
                    else:
                      ctx.enqueueFinalResult(newSuccessResult(
                        req.task.seqId,
                        req.task.page,
                        req.attempt,
                        parsed.text
                      ))
            finally:
              recycleEasy(idleEasy, req.easy)

proc enterDrainErrorMode(ctx: NetworkWorkerContext; message: string; multi: var CurlMulti;
                         active: var Table[uint, RequestContext];
                         retryQueue: var seq[RetryItem];
                         idleEasy: var seq[CurlEasy]) =
  let bounded = boundedErrorMessage(message)
  for req in active.values:
    try:
      multi.removeHandle(req.easy)
    except CatchableError:
      discard
    recycleEasy(idleEasy, req.easy)
    ctx.enqueueFinalResult(newErrorResult(req.task.seqId, req.task.page, req.attempt, NetworkError, bounded))
  active.clear()

  for item in retryQueue:
    ctx.enqueueFinalResult(newErrorResult(item.task.seqId, item.task.page, item.attempt, NetworkError, bounded))
  retryQueue.setLen(0)

  while true:
    var task: OcrTask
    ctx.taskCh.recv(task)
    if task.kind == otkStop:
      break
    ctx.enqueueFinalResult(newErrorResult(task.seqId, task.page, 1, NetworkError, bounded))

proc runNetworkWorker*(ctx: NetworkWorkerContext) {.thread.} =
  var multi: CurlMulti
  var emptyActive = initTable[uint, RequestContext]()
  var emptyRetryQueue: seq[RetryItem] = @[]
  var emptyIdleEasy: seq[CurlEasy] = @[]
  var multiReady = false
  try:
    multi = initMulti()
    multiReady = true
  except CatchableError:
    enterDrainErrorMode(ctx, getCurrentExceptionMsg(), multi, emptyActive, emptyRetryQueue, emptyIdleEasy)
  if multiReady:
    var
      active = initTable[uint, RequestContext]()
      retryQueue: seq[RetryItem] = @[]
      idleEasy: seq[CurlEasy] = @[]
      rng = initRand(int(getMonoTime().ticks))
      stopRequested = false
      running = true

    while running:
      while active.len < MaxInflight:
        var
          task: OcrTask
          attempt = 1
          haveTask = false

        if popReadyRetry(retryQueue, task, attempt):
          haveTask = true
        elif not stopRequested:
          var incoming: OcrTask
          if ctx.taskCh.tryRecv(incoming):
            if incoming.kind == otkStop:
              stopRequested = true
            else:
              task = incoming
              haveTask = true

        if not haveTask:
          break

        let dispatched = dispatchRequest(multi, active, idleEasy, task, attempt, ctx.apiKey)
        if not dispatched.ok:
          finalizeOrRetry(
            ctx,
            retryQueue,
            rng,
            task,
            attempt,
            retryable = true,
            kind = NetworkError,
            message = dispatched.message
          )

      if stopRequested and active.len == 0 and retryQueue.len == 0:
        running = false
      elif active.len == 0:
        if retryQueue.len > 0:
          let waitMs = msUntilNextRetry(retryQueue)
          if waitMs > 0:
            sleep(waitMs)
        elif not stopRequested:
          var task: OcrTask
          ctx.taskCh.recv(task)
          if task.kind == otkStop:
            stopRequested = true
          else:
            let dispatched = dispatchRequest(multi, active, idleEasy, task, 1, ctx.apiKey)
            if not dispatched.ok:
              finalizeOrRetry(
                ctx,
                retryQueue,
                rng,
                task,
                1,
                retryable = true,
                kind = NetworkError,
                message = dispatched.message
              )
      else:
        try:
          discard multi.perform()
          discard multi.poll(min(MultiWaitMaxMs, msUntilNextRetry(retryQueue)))
          processCompletions(ctx, multi, active, retryQueue, idleEasy, rng)
        except CatchableError:
          enterDrainErrorMode(ctx, getCurrentExceptionMsg(), multi, active, retryQueue, idleEasy)
          running = false
