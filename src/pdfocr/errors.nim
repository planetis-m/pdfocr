type
  ErrorKind* = enum
    Success,
    PdfError,
    EncodeError,
    NetworkError,
    Timeout,
    RateLimit,
    HttpError,
    ParseError

const
  MaxErrorMessageLen* = 512

proc boundedErrorMessage*(message: sink string): string =
  if message.len <= MaxErrorMessageLen:
    result = message
  else:
    result = substr(message, 0, MaxErrorMessageLen - 4)
    result.add("...")
