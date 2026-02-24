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
    selectedCount*: int
    networkConfig*: NetworkConfig
    renderConfig*: RenderConfig

  PageErrorKind* = enum
    PdfError,
    EncodeError,
    NetworkError,
    Timeout,
    RateLimit,
    HttpError,
    ParseError

  PageResultStatus* = enum
    PagePending,
    PageOk,
    PageError

  PageResult* = object
    page*: int
    attempts*: int
    status*: PageResultStatus
    text*: string
    errorKind*: PageErrorKind
    errorMessage*: string
    httpStatus*: int
