import std/[algorithm, os, parseopt, sets, strutils]
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

proc parsePositiveInt(raw: string): int =
  let token = raw.strip()
  try:
    result = parseInt(token)
  except ValueError:
    raise newException(ValueError, "invalid page token: " & raw)
  if result < 1:
    raise newException(ValueError, "page must be >= 1")

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

  for rawToken in spec.split(','):
    let token = rawToken.strip()
    if token.len == 0:
      continue

    if '-' notin token:
      let page = parsePositiveInt(token)
      if page > totalPages:
        raise newException(ValueError, "selected page exceeds PDF page count")
      selected.incl(page)
      continue

    let parts = token.split('-', maxsplit = 1)
    if parts.len != 2:
      raise newException(ValueError, "malformed range selector")
    let firstPage = parsePositiveInt(parts[0])
    let lastPage = parsePositiveInt(parts[1])
    if firstPage > lastPage:
      raise newException(ValueError, "range start must be <= end")
    if lastPage > totalPages:
      raise newException(ValueError, "selected page exceeds PDF page count")
    for page in firstPage .. lastPage:
      selected.incl(page)

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
