import jsonx
import jsonx/streams

type
  NetworkConfig* = object
    apiUrl*: string
    model*: string
    prompt*: string
    maxInflight*: int
    totalTimeoutMs*: int
    maxRetries*: int

  RenderConfig* = object
    renderScale*: float
    webpQuality*: float32

  RuntimeConfig* = object
    inputPath*: string
    apiKey*: string
    selectedPages*: seq[int] # seq_id -> selectedPages[seq_id]
    networkConfig*: NetworkConfig
    renderConfig*: RenderConfig

  PageErrorKind* = enum
    NoError,
    PdfError,
    EncodeError,
    NetworkError,
    Timeout,
    RateLimit,
    HttpError,
    ParseError

  PageResultStatus* = enum
    PagePending = "pending",
    PageOk = "ok",
    PageError = "error"

  PageResult* = object
    page*: int
    attempts*: int
    status*: PageResultStatus
    text*: string
    errorKind*: PageErrorKind
    errorMessage*: string
    httpStatus*: int

template writeJsonField(s: Stream; name: string; value: untyped) =
  if comma: streams.write(s, ",")
  else: comma = true
  escapeJson(s, name)
  streams.write(s, ":")
  writeJson(s, value)

proc writeJson*(s: Stream; x: PageResult) =
  var comma = false
  streams.write(s, "{")
  writeJsonField(s, "page", x.page)
  writeJsonField(s, "status", x.status)
  writeJsonField(s, "attempts", x.attempts)
  case x.status
  of PageOk:
    writeJsonField(s, "text", x.text)
  of PageError:
    writeJsonField(s, "error_kind", x.errorKind)
    writeJsonField(s, "error_message", x.errorMessage)
    if x.httpStatus != 0:
      writeJsonField(s, "http_status", x.httpStatus)
  of PagePending:
    discard
  streams.write(s, "}")
