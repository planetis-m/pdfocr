import std/[algorithm, os, parseopt, parseutils, sequtils, strutils]
import ./constants
import ./pdfium
import ./types

type
  CliArgs = object
    inputPath: string
    pagesSpec: string

const HELP_TEXT = """
Usage:
  pdf-olmocr INPUT.pdf --pages:"1,4-6,12"

Options:
  --pages:<spec>   Comma-separated page selectors (1-based).
  --help, -h       Show this help and exit.
"""

template cliError(message) =
  quit(message & "\n\n" & HELP_TEXT, EXIT_FATAL_RUNTIME)

proc parseCliArgs(cliArgs: seq[string]): CliArgs =
  result = CliArgs(inputPath: "", pagesSpec: "")
  var parser = initOptParser(cliArgs)

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      if inputPath.len == 0:
        result.inputPath = parser.key
      else:
        cliError("multiple input files specified")
    of cmdLongOption:
      case key
      of "pages":
        result.pagesSpec = val
      of "help":
        quit(HELP_TEXT, EXIT_ALL_OK)
      else:
        cliError("unknown option: --" & key)
    of cmdShortOption:
      if key == "h":
        quit(HELP_TEXT, EXIT_ALL_OK)
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
  if spec.len == 0:
    return

  var idx = 0
  while idx < spec.len:
    let first = parsePageAt(spec, idx)
    var last = first

    if idx < spec.len and spec[idx] == '-':
      inc idx
      if idx < spec.len:
        last = parsePageAt(spec, idx)

    let lo = min(first, last)
    let hi = max(first, last)
    for page in lo .. hi:
      result.add(page)

    if idx < spec.len and spec[idx] == ',':
      inc idx

  result.sort()
  result = deduplicate(result, isSorted = true)

proc getPdfPageCount(path: string): int =
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

  stderr.writeLine(
    "preflight: total_pages=", totalPages,
    " selected_count=", selectedPages.len,
    " first_page=", selectedPages[0],
    " last_page=", selectedPages[^1]
  )

  RuntimeConfig(
    inputPath: parsed.inputPath,
    apiKey: apiKey,
    selectedPages: selectedPages,
    selectedCount: selectedPages.len
  )
