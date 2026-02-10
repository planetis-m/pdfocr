import std/[algorithm, os, parseopt, sets, strutils]
import ./pdfium
import ./types

type
  CliArgs = object
    inputPath: string
    pagesSpec: string

proc parsePositiveInt(raw: string): int =
  let stripped = raw.strip()
  if stripped.len == 0:
    raise newException(ValueError, "empty page token")
  for ch in stripped:
    if ch < '0' or ch > '9':
      raise newException(ValueError, "malformed page token: " & raw)
  result = parseInt(stripped)
  if result < 1:
    raise newException(ValueError, "page must be >= 1: " & $result)

proc parseCliArgs(cliArgs: seq[string]): CliArgs =
  var parser = initOptParser(cliArgs)
  var positional: seq[string] = @[]
  var pagesSeen = 0
  var parseError = ""

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      positional.add(key)
    of cmdLongOption:
      case key
      of "pages":
        inc pagesSeen
        if val.len > 0:
          result.pagesSpec = val
        else:
          parseError = "missing value for --pages (use --pages:<spec>)"
      else:
        parseError = "unknown argument: --" & key
    of cmdShortOption:
      parseError = "unknown argument: -" & key
    of cmdEnd:
      discard

    if parseError.len > 0:
      break

  if parseError.len == 0:
    case positional.len
    of 0:
      parseError = "missing required INPUT.pdf argument"
    of 1:
      result.inputPath = positional[0]
    else:
      parseError = "unexpected extra positional argument: " & positional[1]

  if parseError.len == 0 and pagesSeen == 0:
    parseError = "missing required --pages argument"

  if parseError.len == 0 and pagesSeen > 1:
    parseError = "--pages provided more than once"

  if parseError.len > 0:
    raise newException(ValueError, parseError)

proc normalizePageSelection*(spec: string; totalPages: int): seq[int] =
  if totalPages < 1:
    raise newException(ValueError, "PDF has no pages")
  if spec.strip().len == 0:
    raise newException(ValueError, "--pages must not be empty")

  var selected = initHashSet[int]()

  for rawToken in spec.split(','):
    let token = rawToken.strip()
    if token.len == 0:
      raise newException(ValueError, "malformed page selector in --pages: empty token")

    let dashCount = token.count('-')
    if dashCount == 0:
      let page = parsePositiveInt(token)
      if page > totalPages:
        raise newException(ValueError, "selected page exceeds PDF page count: " & $page)
      selected.incl(page)
      continue

    if dashCount != 1:
      raise newException(ValueError, "malformed range selector: " & token)

    let parts = token.split('-', maxsplit = 1)
    if parts.len != 2:
      raise newException(ValueError, "malformed range selector: " & token)
    let firstPage = parsePositiveInt(parts[0])
    let lastPage = parsePositiveInt(parts[1])
    if firstPage > lastPage:
      raise newException(ValueError, "range start must be <= end: " & token)
    if lastPage > totalPages:
      raise newException(ValueError, "selected page exceeds PDF page count: " & $lastPage)
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
