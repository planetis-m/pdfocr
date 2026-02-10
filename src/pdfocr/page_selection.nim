import std/[algorithm, os, sets, strutils]
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
  var i = 0
  while i < cliArgs.len:
    let arg = cliArgs[i]
    if arg == "--pages":
      if i + 1 >= cliArgs.len:
        raise newException(ValueError, "missing value for --pages")
      if result.pagesSpec.len > 0:
        raise newException(ValueError, "--pages provided more than once")
      result.pagesSpec = cliArgs[i + 1]
      i += 2
      continue

    if arg.startsWith("--"):
      raise newException(ValueError, "unknown argument: " & arg)

    if result.inputPath.len > 0:
      raise newException(ValueError, "unexpected extra positional argument: " & arg)
    result.inputPath = arg
    inc i

  if result.inputPath.len == 0:
    raise newException(ValueError, "missing required INPUT.pdf argument")
  if result.pagesSpec.len == 0:
    raise newException(ValueError, "missing required --pages argument")

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
