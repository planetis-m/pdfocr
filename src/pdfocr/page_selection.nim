import std/[algorithm, os, parseopt, parseutils, strutils]
import ./[constants, pdfium, types]

type
  CliArgs = object
    inputPath: string
    pagesSpec: string

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

proc parsePageAt(spec: string; idx: var int): int =
  let consumed = parseInt(spec, result, idx)
  if consumed <= 0 or result < 1:
    raise newException(ValueError, "invalid page token")
  inc(idx, consumed)

proc normalizePageSelection*(spec: string; totalPages: int): seq[int] =
  result = @[]
  if spec.len == 0: return
  var idx = 0
  while idx < spec.len:
    let first = parsePageAt(spec, idx)
    var last = first
    if idx < spec.len and spec[idx] == '-':
      inc idx
      if idx < spec.len:
        last = parsePageAt(spec, idx)
      if first > last:
        raise newException(ValueError, "invalid --pages selection")
    for page in countup(first, last):
      # Insert while maintaining sorted order and uniqueness
      let pos = result.lowerBound(page)
      if pos >= result.len or result[pos] != page:
        result.insert(page, pos)
    if idx < spec.len and spec[idx] == ',':
      inc idx

proc getPdfPageCount(path: string): int =
  result = 0
  initPdfium()
  try:
    let doc = loadDocument(path)
    result = pageCount(doc)
  finally:
    destroyPdfium()

proc buildRuntimeConfig*(cliArgs: seq[string]): RuntimeConfig =
  let parsed = parseCliArgs(cliArgs)
  let apiKey = getEnv("DEEPINFRA_API_KEY")
  if apiKey.len == 0:
    raise newException(ValueError, "DEEPINFRA_API_KEY is required")

  let totalPages = getPdfPageCount(parsed.inputPath)
  let selectedPages = normalizePageSelection(parsed.pagesSpec, totalPages)
  if selectedPages.len == 0:
    raise newException(ValueError, "no valid pages selected")
  if selectedPages[^1] > totalPages:
    raise newException(ValueError, "selected page exceeds PDF page count")

  result = RuntimeConfig(
    inputPath: parsed.inputPath,
    apiKey: apiKey,
    selectedPages: selectedPages,
    selectedCount: selectedPages.len
  )
