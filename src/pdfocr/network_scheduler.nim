import std/[atomics, base64, monotimes, os, random]
import threading/channels
import ./bindings/curl
import ./[constants, curl, errors, json_codec, types]

const
  OCRInstruction = "Extract all readable text exactly."
  RetryJitterDivisor = 2
  ResponseExcerptLimit = 240

type
  RequestResponseBuffer = object
    body: string

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

proc slidingWindowAllows*(seqId: int; nextToWrite: int): bool {.inline.} =
  result = seqId < nextToWrite + Window

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

proc shouldRetry(attempts: int): bool {.inline.} =
  attempts < (1 + MaxRetries)

proc requestOnce(task: OcrTask; apiKey: string; responseBody: var string;
                 curlCode: var CURLcode; httpCode: var HttpCode) =
  var easy = initEasy()
  var headers: CurlSlist
  var response = RequestResponseBuffer(body: "")

  let imageDataUrl = "data:image/webp;base64," & base64.encode(task.webpBytes)
  let body = buildChatCompletionRequest(OCRInstruction, imageDataUrl)

  headers.addHeader("Authorization: Bearer " & apiKey)
  headers.addHeader("Content-Type: application/json")
  easy.setUrl(ApiUrl)
  easy.setWriteCallback(writeResponseCb, cast[pointer](addr response))
  easy.setPostFields(body)
  easy.setHeaders(headers)
  easy.setTimeoutMs(TotalTimeoutMs)
  easy.setConnectTimeoutMs(ConnectTimeoutMs)
  easy.setSslVerify(true, true)
  easy.setAcceptEncoding("gzip, deflate")

  try:
    InflightCount.store(1, moRelaxed)
    curlCode = easy.performCode()
  finally:
    InflightCount.store(0, moRelaxed)

  responseBody = response.body
  if curlCode == CURLE_OK:
    httpCode = easy.responseCode()
  else:
    httpCode = HttpNone

proc runTaskWithRetries(task: OcrTask; apiKey: string; rng: var Rand): PageResult =
  var attempts = 0
  while true:
    inc attempts
    try:
      var
        responseBody = ""
        curlCode = CURLE_OK
        httpCode = HttpNone
      requestOnce(task, apiKey, responseBody, curlCode, httpCode)

      if curlCode != CURLE_OK:
        let kind = classifyCurlErrorKind(curlCode)
        let errMsg = "curl transfer failed code=" & $int(curlCode)
        if shouldRetry(attempts):
          discard RetryCount.fetchAdd(1, moRelaxed)
          sleep(retryDelayMs(rng, attempts + 1))
          continue
        return newErrorResult(task.seqId, task.page, attempts, kind, errMsg)

      if httpCode == Http429:
        if shouldRetry(attempts):
          discard RetryCount.fetchAdd(1, moRelaxed)
          sleep(retryDelayMs(rng, attempts + 1))
          continue
        return newHttpErrorResult(task.seqId, task.page, attempts, RateLimit, "HTTP 429 rate limited", httpCode)

      if httpStatusRetryable(httpCode) and httpCode != Http429:
        let msg500 = "HTTP " & $httpCode & ": " & responseExcerpt(responseBody)
        if shouldRetry(attempts):
          discard RetryCount.fetchAdd(1, moRelaxed)
          sleep(retryDelayMs(rng, attempts + 1))
          continue
        return newHttpErrorResult(task.seqId, task.page, attempts, HttpError, msg500, httpCode)

      if httpCode < Http200 or httpCode >= Http300:
        return newHttpErrorResult(
          task.seqId,
          task.page,
          attempts,
          HttpError,
          "HTTP " & $httpCode & ": " & responseExcerpt(responseBody),
          httpCode
        )

      let parsed = parseChatCompletionResponse(responseBody)
      if not parsed.ok:
        return newErrorResult(task.seqId, task.page, attempts, ParseError, parsed.error_message)

      return newSuccessResult(task.seqId, task.page, attempts, parsed.text)
    except CatchableError:
      InflightCount.store(0, moRelaxed)
      let errMsg = boundedErrorMessage(getCurrentExceptionMsg())
      if shouldRetry(attempts):
        discard RetryCount.fetchAdd(1, moRelaxed)
        sleep(retryDelayMs(rng, attempts + 1))
        continue
      return newErrorResult(task.seqId, task.page, attempts, NetworkError, errMsg)

proc runNetworkWorker*(ctx: NetworkWorkerContext) {.thread.} =
  var rng = initRand(int(getMonoTime().ticks))
  InflightCount.store(0, moRelaxed)
  while true:
    var task: OcrTask
    ctx.taskCh.recv(task)
    if task.kind == otkStop:
      break
    let result = runTaskWithRetries(task, ctx.apiKey, rng)
    ctx.resultCh.send(result)
  InflightCount.store(0, moRelaxed)

proc runNetworkScheduler*(ctx: NetworkWorkerContext) {.thread.} =
  runNetworkWorker(ctx)
