type
  ErrorKind* = enum
    PDF_ERROR,
    ENCODE_ERROR,
    NETWORK_ERROR,
    TIMEOUT,
    RATE_LIMIT,
    HTTP_ERROR,
    PARSE_ERROR

const
  MAX_ERROR_MESSAGE_LEN* = 512

proc boundedErrorMessage*(message: string; maxLen: int = MAX_ERROR_MESSAGE_LEN): string =
  if maxLen <= 0:
    return ""
  if message.len <= maxLen:
    return message
  if maxLen <= 3:
    return message[0 ..< maxLen]
  result = message[0 ..< (maxLen - 3)]
  result.add("...")
