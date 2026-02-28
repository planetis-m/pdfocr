import relay
import openai_retry
import ./types

type
  FinalError* = object
    kind*: PageErrorKind
    httpStatus*: int
    message*: string

proc shouldRetry*(item: RequestResult; attempt: int; maxAttempts: int): bool =
  if attempt >= maxAttempts:
    result = false
  elif item.error.kind != teNone:
    result = isRetriableTransport(item.error.kind)
  else:
    result = isRetriableStatus(item.response.code)

proc classifyFinalError*(item: RequestResult): FinalError =
  if item.error.kind != teNone:
    let kind =
      case item.error.kind
      of teTimeout:
        Timeout
      else:
        NetworkError
    let message =
      if item.error.message.len > 0:
        item.error.message
      else:
        "transport error"
    result = FinalError(kind: kind, httpStatus: 0, message: message)
  else:
    let code = item.response.code
    if code == 429:
      result = FinalError(
        kind: RateLimit,
        httpStatus: code,
        message: "rate limited (http 429)"
      )
    elif code == 408 or code == 504:
      result = FinalError(
        kind: Timeout,
        httpStatus: code,
        message: "request timed out (http " & $code & ")"
      )
    else:
      result = FinalError(
        kind: HttpError,
        httpStatus: code,
        message: "http status " & $code
      )
