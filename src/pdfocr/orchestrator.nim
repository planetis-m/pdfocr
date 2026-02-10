import ./constants
import ./curl
import ./logging
import ./page_selection
import ./pdfium
import ./types

proc initGlobalLibraries*() =
  initPdfium()
  initCurlGlobal()

proc cleanupGlobalLibraries*() =
  cleanupCurlGlobal()
  destroyPdfium()

proc runOrchestrator*(cliArgs: seq[string]): int =
  try:
    let runtimeConfig = buildRuntimeConfig(cliArgs)
    resetSharedAtomics()
    let channels = initRuntimeChannels()
    var finalizationGuard = initFinalizationGuard(runtimeConfig.selectedCount)
    discard channels
    discard finalizationGuard
    discard runtimeConfig
    # Phase 03 ends after runtime contracts/channels are initialized.
    result = EXIT_ALL_OK
  except CatchableError as exc:
    logError(exc.msg)
    result = EXIT_FATAL_RUNTIME
