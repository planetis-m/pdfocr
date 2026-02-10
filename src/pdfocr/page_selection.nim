import std/[algorithm, os, parseopt, parseutils, sets, strutils]
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

proc cliError(message: string) {.noreturn.} =
  quit(message & "\n\n" & HELP_TEXT, EXIT_FATAL_RUNTIME)

proc skipSpaces(spec: string; idx: var int) =
  while idx < spec.len and spec[idx].isSpaceAscii:
    inc idx

proc parsePageNumberAt(spec: string; idx: var int): int =
  skipSpaces(spec, idx)
  var parsed = 0
  let consumed = parseInt(spec, parsed, idx)
  if consumed <= 0:
    raise newException(ValueError, "invalid page token")
  idx += consumed
  skipSpaces(spec, idx)
  if parsed < 1:
    raise newException(ValueError, "page must be >= 1")
  result = parsed

proc parseCliArgs(cliArgs: seq[string]): CliArgs =
  var parser = initOptParser(cliArgs)
  var positional: seq[string] = @[]
  var pagesSpec = ""

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      positional.add(key)
    of cmdLongOption:
      case key
      of "pages":
        pagesSpec = val
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

  if positional.len == 0:
    cliError("missing required INPUT.pdf argument")
  if pagesSpec.len == 0:
    cliError("missing required --pages argument")

  result.inputPath = positional[0]
  result.pagesSpec = pagesSpec

proc normalizePageSelection*(spec: string; totalPages: int): seq[int] =
  if totalPages < 1:
    raise newException(ValueError, "PDF has no pages")
  if spec.strip().len == 0:
    raise newException(ValueError, "--pages must not be empty")

  var selected = initHashSet[int]()
  var idx = 0

  while idx < spec.len:
    skipSpaces(spec, idx)
    while idx < spec.len and spec[idx] == ',':
      inc idx
      skipSpaces(spec, idx)
    if idx >= spec.len:
      break

    let firstPage = parsePageNumberAt(spec, idx)
    var lastPage = firstPage

    if idx < spec.len and spec[idx] == '-':
      inc idx
      lastPage = parsePageNumberAt(spec, idx)

    if firstPage > lastPage:
      raise newException(ValueError, "range start must be <= end")
    if lastPage > totalPages:
      raise newException(ValueError, "selected page exceeds PDF page count")

    for page in firstPage .. lastPage:
      selected.incl(page)

    if idx < spec.len and spec[idx] == ',':
      inc idx
    elif idx < spec.len:
      raise newException(ValueError, "malformed page selector")

  result = newSeqOfCap[int](selected.len)
  for page in selected:
    result.add(page)
  result.sort()

  if result.len == 0:
    raise newException(ValueError, "page selection resolved to empty set")

proc buildRuntimeConfig*(cliArgs: seq[string]): RuntimeConfig =
  let parsed = parseCliArgs(cliArgs)
  let apiKey = getEnv("DEEPINFRA_API_KEY").strip()
  if apiKey.len == 0:
    raise newException(ValueError, "DEEPINFRA_API_KEY is required")

  var totalPages = 0
  initPdfium()
  try:
    let doc = loadDocument(parsed.inputPath)
    totalPages = pageCount(doc)
  finally:
    destroyPdfium()

  let selectedPages = normalizePageSelection(parsed.pagesSpec, totalPages)
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
