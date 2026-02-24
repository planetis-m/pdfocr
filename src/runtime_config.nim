import std/[envvars, parseopt, paths, files]
from std/os import getAppDir
import jsonx
import ./[constants, logging, page_selection, pdfium_wrap, types]

{.define: jsonxLenient.}

type
  CliArgs = object
    inputPath: string
    pagesSpec: string
    allPages: bool

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
  pdfocr INPUT.pdf --pages:"1,4-6,12"
  pdfocr INPUT.pdf --all-pages

Options:
  --pages:<spec>   Comma-separated page selectors (1-based).
  --all-pages      OCR every page in INPUT.pdf.
  --help, -h       Show this help and exit.
"""

proc cliError(message: string) =
  quit(message & "\n\n" & HelpText, ExitFatalRuntime)

proc parseCliArgs(cliArgs: seq[string]): CliArgs =
  result = CliArgs(inputPath: "", pagesSpec: "", allPages: false)
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
      of "all-pages":
        result.allPages = true
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
  if result.pagesSpec.len == 0 and not result.allPages:
    cliError("must provide exactly one of --pages or --all-pages")
  if result.pagesSpec.len > 0 and result.allPages:
    cliError("cannot combine --pages with --all-pages")

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
  if value.len > 0: value
  else: fallback

template ifPositive(value, fallback: untyped): untyped =
  if value > 0: value
  else: fallback

template ifNonNegative(value, fallback: untyped): untyped =
  if value >= 0: value
  else: fallback

template ifInRange(value, minValue, maxValue, fallback: untyped): untyped =
  if value >= minValue and value <= maxValue: value
  else: fallback

proc buildRuntimeConfig*(cliArgs: seq[string]): RuntimeConfig =
  let parsed = parseCliArgs(cliArgs)
  if not fileExists(Path(parsed.inputPath)):
    raise newException(IOError, "input PDF not found: " & parsed.inputPath)
  let configPath = Path(getAppDir()) / Path(DefaultConfigPath)
  let rawConfig = loadOptionalJsonRuntimeConfig(configPath)

  let totalPages = getPdfPageCount(parsed.inputPath)
  let selectedPages =
    if parsed.allPages:
      allPagesSelection(totalPages)
    else:
      normalizePageSelection(parsed.pagesSpec, totalPages)
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
      totalTimeoutMs: ifPositive(rawConfig.total_timeout_ms, TotalTimeoutMs),
      maxRetries: ifNonNegative(rawConfig.max_retries, MaxRetries)
    ),
    renderConfig: RenderConfig(
      renderScale: ifPositive(rawConfig.render_scale, RenderScale),
      webpQuality: ifInRange(rawConfig.webp_quality, 0'f32, 100'f32, WebpQuality)
    )
  )
