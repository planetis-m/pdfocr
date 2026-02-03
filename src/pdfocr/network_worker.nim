import std/[base64, deques, heapqueue, json, monotimes, random, strformat, tables, times]
import threading/channels
import ./bindings/curl
import ./[config, curl, logging, types]

type
  NetworkContext* = object
    apiKey*: string
    config*: Config
    inputChan*: Chan[InputMessage]
    outputChan*: Chan[OutputMessage]

  RequestState = object
    task: Task
    attempt: int
    response: string
    startedAt: MonoTime
    headers: CurlSlist

  RequestStateRef = ref RequestState

  RetryItem = object
    due: MonoTime
    task: Task
    attempt: int

proc `<`(a, b: RetryItem): bool =
  a.due < b.due

proc writeCb(buffer: ptr char; size: csize_t; nitems: csize_t; userdata: pointer): csize_t {.cdecl.} =
  let total = int(size * nitems)
  if total <= 0:
    return 0
  let state = cast[RequestStateRef](userdata)
  if state != nil:
    let start = state.response.len
    state.response.setLen(start + total)
    copyMem(addr state.response[start], buffer, total)
  csize_t(total)

proc base64FromBytes(data: seq[byte]): string =
  if data.len == 0:
    return ""
  var raw = newString(data.len)
  copyMem(addr raw[0], unsafeAddr data[0], data.len)
  encode(raw)

proc buildRequestBody(task: Task): string =
  let b64 = base64FromBytes(task.jpegBytes)
  let payload = %*{
    "model": "allenai/olmOCR-2-7B-1025",
    "input": %*{
      "image": "data:image/jpeg;base64," & b64
    }
  }
  $payload

proc parseOcrText(body: string): tuple[ok: bool, text: string, err: string] =
  try:
    let node = parseJson(body)
    if node.kind == JObject:
      if node.hasKey("text") and node["text"].kind == JString:
        return (true, node["text"].getStr(), "")
      if node.hasKey("output") and node["output"].kind == JString:
        return (true, node["output"].getStr(), "")
      if node.hasKey("results") and node["results"].kind == JArray and node["results"].len > 0:
        let first = node["results"][0]
        if first.kind == JObject and first.hasKey("text") and first["text"].kind == JString:
          return (true, first["text"].getStr(), "")
        if first.kind == JObject and first.hasKey("generated_text") and first["generated_text"].kind == JString:
          return (true, first["generated_text"].getStr(), "")
  except CatchableError as err:
    return (false, "", err.msg)
  (false, "", "missing expected text field")

proc computeBackoffMs(attempt: int; baseMs: int; maxMs: int): int =
  if attempt <= 0:
    return baseMs
  var delay = baseMs shl (attempt - 1)
  if delay > maxMs:
    delay = maxMs
  delay

proc enqueueResult(ctx: NetworkContext; pending: var seq[OutputMessage]; msg: OutputMessage) =
  if not ctx.outputChan.trySend(msg):
    pending.add(msg)

proc flushPending(ctx: NetworkContext; pending: var seq[OutputMessage]) =
  var idx = 0
  while idx < pending.len:
    if ctx.outputChan.trySend(pending[idx]):
      inc idx
    else:
      break
  if idx > 0:
    if idx >= pending.len:
      pending.setLen(0)
    else:
      pending = pending[idx..^1]

proc runNetworkWorker*(ctx: NetworkContext) {.thread.} =
  randomize()
  logInfo("Network worker thread started.")

  var multi = initMulti()
  defer:
    close(multi)

  var freeHandles = newSeq[CurlEasy](ctx.config.maxInflight)
  for i in 0..<ctx.config.maxInflight:
    var easy = initEasy()
    easy.setSslVerify(true, true)
    easy.setAcceptEncoding("gzip, deflate")
    freeHandles[i] = easy

  defer:
    for i in 0..<freeHandles.len:
      var easy = freeHandles[i]
      easy.close()

  var inflight = initTable[pointer, RequestStateRef]()
  var reservoir = initDeque[Task]()
  var delayed = initHeapQueue[RetryItem]()
  var pendingResults: seq[OutputMessage] = @[]
  var inputDone = false

  proc refillReservoir() =
    if reservoir.len >= ctx.config.lowWater:
      return
    var msg: InputMessage
    while reservoir.len < ctx.config.highWater and ctx.inputChan.tryRecv(msg):
      case msg.kind
      of imTaskBatch:
        for task in msg.tasks:
          reservoir.addLast(task)
      of imInputDone:
        inputDone = true

  proc scheduleRetry(task: Task; attempt: int) =
    let delayMs = computeBackoffMs(attempt, ctx.config.retryBaseDelayMs, ctx.config.retryMaxDelayMs)
    let jitter = rand(delayMs div 2)
    let due = getMonoTime() + initDuration(milliseconds = delayMs + jitter)
    var nextTask = task
    nextTask.attempt = attempt
    delayed.push(RetryItem(due: due, task: nextTask, attempt: attempt))

  proc dispatchTasks() =
    while freeHandles.len > 0 and reservoir.len > 0:
      let task = reservoir.popFirst()
      var easy = freeHandles.pop()

      var state = RequestState(
        task: task,
        attempt: task.attempt,
        response: "",
        startedAt: getMonoTime(),
        headers: CurlSlist()
      )
      let body = buildRequestBody(task)
      state.headers.addHeader(&"Authorization: Bearer {ctx.apiKey}")
      state.headers.addHeader("Content-Type: application/json")

      easy.reset()
      easy.setSslVerify(true, true)
      easy.setAcceptEncoding("gzip, deflate")
      easy.setUrl("https://api.deepinfra.com/v1/inference/allenai/olmOCR-2-7B-1025")
      easy.setHeaders(state.headers)
      easy.setConnectTimeoutMs(ctx.config.connectTimeoutMs)
      easy.setTimeoutMs(ctx.config.totalTimeoutMs)
      let stateRef = new RequestState
      stateRef[] = state
      easy.setWriteCallback(writeCb, cast[pointer](stateRef))
      easy.setPostFields(body)

      inflight[cast[pointer](easy.raw)] = stateRef
      easy.setPrivate(cast[pointer](stateRef))
      multi.addHandle(easy)

  proc handleCompletion(easy: var CurlEasy; code: CURLcode) =
    let key = cast[pointer](easy.raw)
    if not inflight.hasKey(key):
      return
    let stateRef = inflight[key]
    inflight.del(key)

    let httpStatus =
      try:
        easy.responseCode()
      except CatchableError:
        0
    let finishedAt = getMonoTime()
    var retryable = false
    var errorKind = ekNetworkError
    var errorMsg = ""

    if code != CURLE_OK:
      retryable = true
      if code == CURLE_OPERATION_TIMEDOUT:
        errorKind = ekTimeout
      else:
        errorKind = ekNetworkError
      errorMsg = "curl error"
    else:
      if httpStatus >= 200 and httpStatus < 300:
        let parsed = parseOcrText(stateRef.response)
        if parsed.ok:
          enqueueResult(ctx, pendingResults, OutputMessage(
            kind: omPageResult,
            result: Result(
              pageId: stateRef.task.pageId,
              pageNumberUser: stateRef.task.pageNumberUser,
              status: rsSuccess,
              text: parsed.text,
              errorKind: ekNetworkError,
              errorMessage: "",
              httpStatus: httpStatus,
              attemptCount: stateRef.attempt + 1,
              startedAt: stateRef.startedAt,
              finishedAt: finishedAt
            )
          ))
        else:
          enqueueResult(ctx, pendingResults, OutputMessage(
            kind: omPageResult,
            result: Result(
              pageId: stateRef.task.pageId,
              pageNumberUser: stateRef.task.pageNumberUser,
              status: rsFailure,
              text: "",
              errorKind: ekParseError,
              errorMessage: parsed.err,
              httpStatus: httpStatus,
              attemptCount: stateRef.attempt + 1,
              startedAt: stateRef.startedAt,
              finishedAt: finishedAt
            )
          ))
        stateRef.headers.free()
        return
      if httpStatus == 429:
        retryable = true
        errorKind = ekRateLimit
        errorMsg = "http 429"
      elif httpStatus >= 500:
        retryable = true
        errorKind = ekHttpError
        errorMsg = "http 5xx"
      elif httpStatus >= 400:
        retryable = false
        errorKind = ekHttpError
        errorMsg = "http 4xx"

    if retryable:
      if stateRef.attempt >= ctx.config.maxRetries:
        enqueueResult(ctx, pendingResults, OutputMessage(
          kind: omPageResult,
          result: Result(
            pageId: stateRef.task.pageId,
            pageNumberUser: stateRef.task.pageNumberUser,
            status: rsFailure,
            text: "",
            errorKind: errorKind,
            errorMessage: errorMsg,
            httpStatus: httpStatus,
            attemptCount: stateRef.attempt + 1,
            startedAt: stateRef.startedAt,
            finishedAt: finishedAt
          )
        ))
      else:
        let nextAttempt = stateRef.attempt + 1
        scheduleRetry(stateRef.task, nextAttempt)
    else:
      enqueueResult(ctx, pendingResults, OutputMessage(
        kind: omPageResult,
        result: Result(
          pageId: stateRef.task.pageId,
          pageNumberUser: stateRef.task.pageNumberUser,
          status: rsFailure,
          text: "",
          errorKind: errorKind,
          errorMessage: errorMsg,
          httpStatus: httpStatus,
          attemptCount: stateRef.attempt + 1,
          startedAt: stateRef.startedAt,
          finishedAt: finishedAt
        )
      ))

    stateRef.headers.free()

  proc drainDueRetries() =
    let now = getMonoTime()
    while delayed.len > 0:
      let next = delayed[0]
      if next.due > now:
        break
      discard delayed.pop()
      reservoir.addLast(next.task)

  var msg: CURLMsg
  var msgsInQueue = 0

  while true:
    refillReservoir()
    drainDueRetries()
    dispatchTasks()
    flushPending(ctx, pendingResults)

    var timeoutMs = ctx.config.multiWaitMaxMs
    if delayed.len > 0:
      let now = getMonoTime()
      let due = delayed[0].due
      if due > now:
        let delta = due - now
        let waitMs = int(delta.inMilliseconds)
        if waitMs < timeoutMs:
          timeoutMs = max(waitMs, 0)
      else:
        timeoutMs = 0

    discard multi.poll(timeoutMs)
    discard multi.perform()
    while multi.tryInfoRead(msg, msgsInQueue):
      if msg.msg != CURLMSG_DONE:
        continue
      let easyHandle = CurlEasy(raw: msg.easy_handle)
      var easy = easyHandle
      handleCompletion(easy, msg.data.result)
      multi.removeHandle(easy)
      easy.reset()
      freeHandles.add(easy)

    if inputDone and reservoir.len == 0 and delayed.len == 0 and inflight.len == 0 and pendingResults.len == 0:
      break

  ctx.outputChan.send(OutputMessage(kind: omOutputDone))
