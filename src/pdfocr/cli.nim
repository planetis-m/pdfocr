import std/[parseopt, strutils, os]
import ./config

type
  CliOptions* = object
    pdfPath*: string
    outputDir*: string
    pageStart*: int
    pageEnd*: int
    apiKey*: string
    config*: Config

proc usage*() =
  echo """Usage: pdfocr <pdf_path> [options]

Options:
  --pages:start-end           Page range (1-based, inclusive). Example: 1-10
  --output-dir:DIR            Output directory
  --api-key:KEY               DeepInfra API key (overrides env)
  --max-inflight:N            Max concurrent requests
  --high-water:N              Reservoir high-water mark
  --low-water:N               Reservoir low-water mark
  --producer-batch:N          Producer batch size
  --connect-timeout-ms:N      Connect timeout (ms)
  --total-timeout-ms:N        Total timeout (ms)
  --max-retries:N             Max retries
  --retry-base-delay-ms:N     Retry base delay (ms)
  --retry-max-delay-ms:N      Retry max delay (ms)
  --multi-wait-max-ms:N       curl_multi_poll max wait (ms)
  --render-dpi:N              Render DPI
  --render-scale:X            Render scale factor
  --jpeg-quality:N            JPEG quality (1-100)
  --ordering:MODE             input|completion
  --output-format:FORMAT      jsonl|per-page
  --max-queued-image-bytes:N  Optional cap for queued image bytes
  -h, --help                  Show help"""

proc parsePageRange*(value: string; startPage: var int; endPage: var int) =
  let parts = value.split("-", 1)
  if parts.len != 2:
    raise newException(ValueError, "Invalid page range. Expected start-end.")
  startPage = parseInt(parts[0])
  endPage = parseInt(parts[1])

proc parseOrdering*(value: string): OrderingMode =
  case value.toLowerAscii()
  of "input": omInputOrder
  of "completion": omCompletionOrder
  else:
    raise newException(ValueError, "Unknown ordering mode: " & value)

proc parseOutputFormat*(value: string): OutputFormat =
  case value.toLowerAscii()
  of "jsonl": ofJsonl
  of "per-page": ofPerPageFiles
  else:
    raise newException(ValueError, "Unknown output format: " & value)

proc parseArgs*(): CliOptions =
  result.config = defaultConfig()
  result.pageStart = 1
  result.pageEnd = 0
  for kind, key, value in getopt():
    case kind
    of cmdArgument:
      if result.pdfPath.len == 0:
        result.pdfPath = key
      elif result.pageEnd == 0:
        parsePageRange(key, result.pageStart, result.pageEnd)
      else:
        raise newException(ValueError, "Unexpected argument: " & key)
    of cmdLongOption, cmdShortOption:
      case key
      of "h", "help":
        usage()
        quit(0)
      of "pages":
        parsePageRange(value, result.pageStart, result.pageEnd)
      of "out", "output-dir":
        result.outputDir = value
      of "api-key":
        result.apiKey = value
      of "max-inflight":
        result.config.maxInflight = parseInt(value)
      of "high-water":
        result.config.highWater = parseInt(value)
      of "low-water":
        result.config.lowWater = parseInt(value)
      of "producer-batch":
        result.config.producerBatch = parseInt(value)
      of "connect-timeout-ms":
        result.config.connectTimeoutMs = parseInt(value)
      of "total-timeout-ms":
        result.config.totalTimeoutMs = parseInt(value)
      of "max-retries":
        result.config.maxRetries = parseInt(value)
      of "retry-base-delay-ms":
        result.config.retryBaseDelayMs = parseInt(value)
      of "retry-max-delay-ms":
        result.config.retryMaxDelayMs = parseInt(value)
      of "multi-wait-max-ms":
        result.config.multiWaitMaxMs = parseInt(value)
      of "render-dpi":
        result.config.renderDpi = parseInt(value)
      of "render-scale":
        result.config.renderScale = parseFloat(value)
      of "jpeg-quality":
        result.config.jpegQuality = parseInt(value)
      of "ordering":
        result.config.orderingMode = parseOrdering(value)
      of "output-format":
        result.config.outputFormat = parseOutputFormat(value)
      of "max-queued-image-bytes":
        result.config.maxQueuedImageBytes = parseInt(value)
      else:
        raise newException(ValueError, "Unknown option: " & key)
    of cmdEnd:
      discard

  if result.pdfPath.len == 0:
    raise newException(ValueError, "Missing required pdf_path.")

  if result.outputDir.len == 0:
    result.outputDir = getCurrentDir()

  if result.apiKey.len == 0:
    result.apiKey = getEnv("DEEPINFRA_API_KEY", "")

  if result.apiKey.len == 0:
    raise newException(IOError, "Missing DeepInfra API key. Set DEEPINFRA_API_KEY or use --api-key.")

  if result.config.highWater == 0 or result.config.lowWater == 0 or result.config.producerBatch == 0:
    result.config = defaultConfig(result.config)

  validateConfig(result.config)

