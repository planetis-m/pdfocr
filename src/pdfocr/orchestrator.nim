import ./constants
import ./curl
import ./logging
import ./page_selection
import ./pdfium

proc initGlobalLibraries*() =
  initPdfium()
  initCurlGlobal()

proc cleanupGlobalLibraries*() =
  cleanupCurlGlobal()
  destroyPdfium()

proc runOrchestrator*(cliArgs: seq[string]): int =
  try:
    let runtimeConfig = buildRuntimeConfig(cliArgs)
    discard runtimeConfig
    # Phase 02 ends after validated preflight + normalized selection mapping.
    result = EXIT_ALL_OK
  except CatchableError as exc:
    logError(exc.msg)
    result = EXIT_FATAL_RUNTIME
