type
  OrderingMode* = enum
    omInputOrder,
    omCompletionOrder

  OutputFormat* = enum
    ofJsonl,
    ofPerPageFiles

  Config* = object
    maxInflight*: int
    highWater*: int
    lowWater*: int
    producerBatch*: int
    connectTimeoutMs*: int
    totalTimeoutMs*: int
    maxRetries*: int
    retryBaseDelayMs*: int
    retryMaxDelayMs*: int
    multiWaitMaxMs*: int
    renderDpi*: int
    renderScale*: float
    jpegQuality*: int
    orderingMode*: OrderingMode
    outputFormat*: OutputFormat
    maxQueuedImageBytes*: int

const
  DefaultMaxInflight* = 50
  DefaultHighWaterMultiplier* = 4
  DefaultLowWaterMultiplier* = 1
  DefaultConnectTimeoutMs* = 10_000
  DefaultTotalTimeoutMs* = 120_000
  DefaultMaxRetries* = 5
  DefaultRetryBaseDelayMs* = 500
  DefaultRetryMaxDelayMs* = 20_000
  DefaultMultiWaitMaxMs* = 500
  DefaultRenderDpi* = 144
  DefaultRenderScale* = 0.0
  DefaultJpegQuality* = 85
  DefaultOrderingMode* = omInputOrder
  DefaultOutputFormat* = ofJsonl
  DefaultMaxQueuedImageBytes* = 0

proc defaultConfig*(seed: Config = Config()): Config =
  template pickPos(val, fallback: untyped): untyped =
    (if val > 0: val else: fallback)
  template pickOrdering(val: OrderingMode): OrderingMode =
    (if val != omInputOrder: val else: DefaultOrderingMode)
  template pickOutput(val: OutputFormat): OutputFormat =
    (if val != ofJsonl: val else: DefaultOutputFormat)

  let maxInflight = pickPos(seed.maxInflight, DefaultMaxInflight)
  let highWater = pickPos(seed.highWater, maxInflight * DefaultHighWaterMultiplier)
  let lowWater = pickPos(seed.lowWater, maxInflight * DefaultLowWaterMultiplier)
  let producerBatch = pickPos(seed.producerBatch, highWater - lowWater)
  result = Config(
    maxInflight: maxInflight,
    highWater: highWater,
    lowWater: lowWater,
    producerBatch: producerBatch,
    connectTimeoutMs: pickPos(seed.connectTimeoutMs, DefaultConnectTimeoutMs),
    totalTimeoutMs: pickPos(seed.totalTimeoutMs, DefaultTotalTimeoutMs),
    maxRetries: pickPos(seed.maxRetries, DefaultMaxRetries),
    retryBaseDelayMs: pickPos(seed.retryBaseDelayMs, DefaultRetryBaseDelayMs),
    retryMaxDelayMs: pickPos(seed.retryMaxDelayMs, DefaultRetryMaxDelayMs),
    multiWaitMaxMs: pickPos(seed.multiWaitMaxMs, DefaultMultiWaitMaxMs),
    renderDpi: pickPos(seed.renderDpi, DefaultRenderDpi),
    renderScale: pickPos(seed.renderScale, DefaultRenderScale),
    jpegQuality: pickPos(seed.jpegQuality, DefaultJpegQuality),
    orderingMode: pickOrdering(seed.orderingMode),
    outputFormat: pickOutput(seed.outputFormat),
    maxQueuedImageBytes: seed.maxQueuedImageBytes
  )

proc validateConfig*(cfg: Config) {.noinline.} =
  if cfg.maxInflight < 1:
    raise newException(ValueError, "MAX_INFLIGHT must be >= 1")
  if cfg.highWater < cfg.lowWater:
    raise newException(ValueError, "HIGH_WATER must be >= LOW_WATER")
  if cfg.lowWater < cfg.maxInflight:
    raise newException(ValueError, "LOW_WATER must be >= MAX_INFLIGHT")
  if cfg.producerBatch < 1:
    raise newException(ValueError, "PRODUCER_BATCH must be >= 1")
  if cfg.connectTimeoutMs < 1 or cfg.totalTimeoutMs < 1:
    raise newException(ValueError, "Timeouts must be >= 1ms")
  if cfg.maxRetries < 0:
    raise newException(ValueError, "MAX_RETRIES must be >= 0")
  if cfg.retryBaseDelayMs < 1 or cfg.retryMaxDelayMs < 1:
    raise newException(ValueError, "Retry delays must be >= 1ms")
  if cfg.multiWaitMaxMs < 1:
    raise newException(ValueError, "MULTI_WAIT_MAX_MS must be >= 1ms")
  if cfg.jpegQuality < 1 or cfg.jpegQuality > 100:
    raise newException(ValueError, "JPEG_QUALITY must be 1-100")
