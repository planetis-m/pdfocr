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
  let maxInflight = if seed.maxInflight > 0: seed.maxInflight else: DefaultMaxInflight
  let highWater = if seed.highWater > 0: seed.highWater else: maxInflight * DefaultHighWaterMultiplier
  let lowWater = if seed.lowWater > 0: seed.lowWater else: maxInflight * DefaultLowWaterMultiplier
  let producerBatch = if seed.producerBatch > 0: seed.producerBatch else: highWater - lowWater
  result = Config(
    maxInflight: maxInflight,
    highWater: highWater,
    lowWater: lowWater,
    producerBatch: producerBatch,
    connectTimeoutMs: if seed.connectTimeoutMs > 0: seed.connectTimeoutMs else: DefaultConnectTimeoutMs,
    totalTimeoutMs: if seed.totalTimeoutMs > 0: seed.totalTimeoutMs else: DefaultTotalTimeoutMs,
    maxRetries: if seed.maxRetries > 0: seed.maxRetries else: DefaultMaxRetries,
    retryBaseDelayMs: if seed.retryBaseDelayMs > 0: seed.retryBaseDelayMs else: DefaultRetryBaseDelayMs,
    retryMaxDelayMs: if seed.retryMaxDelayMs > 0: seed.retryMaxDelayMs else: DefaultRetryMaxDelayMs,
    multiWaitMaxMs: if seed.multiWaitMaxMs > 0: seed.multiWaitMaxMs else: DefaultMultiWaitMaxMs,
    renderDpi: if seed.renderDpi > 0: seed.renderDpi else: DefaultRenderDpi,
    renderScale: if seed.renderScale > 0: seed.renderScale else: DefaultRenderScale,
    jpegQuality: if seed.jpegQuality > 0: seed.jpegQuality else: DefaultJpegQuality,
    orderingMode: if seed.orderingMode != low(OrderingMode): seed.orderingMode else: DefaultOrderingMode,
    outputFormat: if seed.outputFormat != low(OutputFormat): seed.outputFormat else: DefaultOutputFormat,
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
