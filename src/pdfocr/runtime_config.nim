import std/[envvars, parseopt, paths, files]
import jsonx
import ./[constants, logging, page_selection, pdfium, types]

{.define: jsonxLenient.}

type
  CliArgs = object
    inputPath: string
    pagesSpec: string

  JsonRuntimeConfig = object
    api_key: string
    api_url: string
    model: string
    prompt: string
    max_inflight: int
    total_timeout_ms: int
    max_retries: int
    render_scale: float
    webp_quality: float32

const HelpText = """
Usage:
  pdf-olmocr INPUT.pdf --pages:"1,4-6,12"

Options:
  --pages:<spec>   Comma-separated page selectors (1-based).
  --help, -h       Show this help and exit.
"""

template cliError(message) =
  quit(message & "\n\n" & HelpText, ExitFatalRuntime)

proc parseCliArgs(cliArgs: seq[string]): CliArgs =
  result = CliArgs(inputPath: "", pagesSpec: "")
  var parser = initOptParser(cliArgs)

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      if result.inputPath.len == 0:
        result.inputPath = parser.key
      else:
        cliError("multiple input files specified")
    of cmdLongOption:
      case key
      of "pages":
        result.pagesSpec = val
      of "help":
        quit(HelpText, ExitAllOk)
      else:
        cliError("unknown option: --" & key)
    of cmdShortOption:
      if key == "h":
        quit(HelpText, ExitAllOk)
      else:
        cliError("unknown option: -" & key)
    of cmdEnd:
      discard

  if result.inputPath.len == 0:
    cliError("missing required INPUT.pdf argument")
  if result.pagesSpec.len == 0:
    cliError("missing required --pages argument")

proc getPdfPageCount(path: string): int =
  result = 0
  initPdfium()
  try:
    let doc = loadDocument(path)
    result = pageCount(doc)
  finally:
    destroyPdfium()

proc defaultJsonRuntimeConfig(): JsonRuntimeConfig =
  JsonRuntimeConfig(
    api_key: "",
    api_url: ApiUrl,
    model: Model,
    prompt: Prompt,
    max_inflight: MaxInflight,
    total_timeout_ms: TotalTimeoutMs,
    max_retries: MaxRetries,
    render_scale: RenderScale,
    webp_quality: WebpQuality
  )

proc loadOptionalJsonRuntimeConfig(path: Path): JsonRuntimeConfig =
  result = defaultJsonRuntimeConfig()
  if fileExists(path):
    try:
      jsonx.fromFile(path, result)
      logInfo("loaded config from " & $absolutePath(path))
    except CatchableError:
      logWarn("failed to parse config file at " & $absolutePath(path) &
        "; using built-in defaults")
  else:
    logInfo("config file not found at " & $absolutePath(path) & "; using built-in defaults")

proc resolveApiKey(configApiKey: string): string =
  let envApiKey = getEnv("DEEPINFRA_API_KEY")
  if envApiKey.len > 0:
    result = envApiKey
  else:
    result = configApiKey

template ifNonEmpty(value, fallback: untyped): untyped =
  if value.len > 0: value else: fallback

template ifPositive(value, fallback: untyped): untyped =
  if value > 0: value else: fallback

template ifNonNegative(value, fallback: untyped): untyped =
  if value >= 0: value else: fallback

template ifInRange(value, minValue, maxValue, fallback: untyped): untyped =
  if value >= minValue and value <= maxValue: value else: fallback

proc buildRuntimeConfig*(cliArgs: seq[string]): RuntimeConfig =
  let parsed = parseCliArgs(cliArgs)
  let rawConfig = loadOptionalJsonRuntimeConfig(Path(DefaultConfigPath))

  let totalPages = getPdfPageCount(parsed.inputPath)
  let selectedPages = normalizePageSelection(parsed.pagesSpec, totalPages)
  if selectedPages.len == 0:
    raise newException(ValueError, "no valid pages selected")
  if selectedPages[^1] > totalPages:
    raise newException(ValueError, "selected page exceeds PDF page count")

  result = RuntimeConfig(
    inputPath: parsed.inputPath,
    apiKey: resolveApiKey(rawConfig.api_key),
    selectedPages: selectedPages,
    selectedCount: selectedPages.len,
    networkConfig: NetworkConfig(
      apiUrl: ifNonEmpty(rawConfig.api_url, ApiUrl),
      model: ifNonEmpty(rawConfig.model, Model),
      prompt: ifNonEmpty(rawConfig.prompt, Prompt),
      maxInflight: ifPositive(rawConfig.max_inflight, MaxInflight),
      connectTimeoutMs: ConnectTimeoutMs,
      totalTimeoutMs: ifPositive(rawConfig.total_timeout_ms, TotalTimeoutMs),
      maxRetries: ifNonNegative(rawConfig.max_retries, MaxRetries),
      retryBaseDelayMs: RetryBaseDelayMs,
      retryMaxDelayMs: RetryMaxDelayMs
    ),
    renderConfig: RenderConfig(
      renderScale: ifPositive(rawConfig.render_scale, RenderScale),
      webpQuality: ifInRange(rawConfig.webp_quality, 0, 100, WebpQuality)
    )
  )
