import relay
import ../src/[retry_and_errors, types]

proc makeResponse(code: int; requestId: int64): Response =
  Response(
    code: code,
    url: "",
    headers: @[],
    body: "",
    request: RequestInfo(verb: hvPost, url: "", requestId: requestId)
  )

proc main() =
  block:
    let item: RequestResult = (
      response: makeResponse(0, 1),
      error: TransportError(kind: teTimeout, message: "timeout", curlCode: 28)
    )
    doAssert shouldRetry(item, attempt = 1, maxAttempts = 3)
    let err = classifyFinalError(item)
    doAssert err.kind == Timeout
    doAssert err.httpStatus == 0

  block:
    let item: RequestResult = (
      response: makeResponse(429, 2),
      error: TransportError(kind: teNone, message: "", curlCode: 0)
    )
    doAssert shouldRetry(item, attempt = 1, maxAttempts = 3)
    let err = classifyFinalError(item)
    doAssert err.kind == RateLimit
    doAssert err.httpStatus == 429

  block:
    let item: RequestResult = (
      response: makeResponse(500, 3),
      error: TransportError(kind: teNone, message: "", curlCode: 0)
    )
    doAssert shouldRetry(item, attempt = 2, maxAttempts = 3)
    doAssert not shouldRetry(item, attempt = 3, maxAttempts = 3)
    let err = classifyFinalError(item)
    doAssert err.kind == HttpError
    doAssert err.httpStatus == 500

  block:
    let item: RequestResult = (
      response: makeResponse(0, 4),
      error: TransportError(kind: teNetwork, message: "connection reset", curlCode: 56)
    )
    let err = classifyFinalError(item)
    doAssert err.kind == NetworkError
    doAssert err.httpStatus == 0

when isMainModule:
  main()
