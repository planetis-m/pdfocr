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

proc parsePageValue(token: string): int =
  let raw = token.strip()
  let consumed = parseInt(raw, result, 0)
  if consumed != raw.len or result < 1:
    raise newException(ValueError, "invalid page token")

proc parseCliArgs(cliArgs: seq[string]): CliArgs =
  result = CliArgs()
  var parser = initOptParser(cliArgs)

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      if result.inputPath.len == 0:
        result.inputPath = key
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

proc normalizePageSelection*(spec: string; totalPages: int): seq[int] =
  if totalPages < 1:
    raise newException(ValueError, "PDF has no pages")
  if spec.len == 0:
    raise newException(ValueError, "--pages must not be empty")

  var selected = initHashSet[int]()

  for rawToken in spec.split(','):
    let token = rawToken.strip()
    if token.len == 0:
      continue

    let dash = token.find('-')
    if dash < 0:
      let page = parsePageValue(token)
      if page <= totalPages:
        selected.incl(page)
      continue

    let a = parsePageValue(token[0 ..< dash])
    let b = parsePageValue(token[dash + 1 .. ^1])
    let first = min(a, b)
    let last = max(a, b)
    for page in first .. last:
      if page <= totalPages:
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
