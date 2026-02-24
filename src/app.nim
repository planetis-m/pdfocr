import std/os
import relay
import ./[constants, logging, pipeline, runtime_config]

proc shutdownRelay(client: Relay; shouldAbort: bool) =
  if shouldAbort:
    client.abort()
  else:
    client.close()

proc runApp*(): int =
  var client: Relay = nil
  var shouldAbort = false

  try:
    let cfg = buildRuntimeConfig(commandLineParams())
    if cfg.openaiConfig.apiKey.len == 0:
      raise newException(ValueError,
        "missing API key; set DEEPINFRA_API_KEY or api_key in config.json")

    client = newRelay(
      maxInFlight = cfg.networkConfig.maxInflight,
      defaultTimeoutMs = cfg.networkConfig.totalTimeoutMs
    )

    let allSucceeded = runPipeline(cfg, client)
    result = if allSucceeded: ExitAllOk else: ExitPartialFailure
  except CatchableError:
    logError(getCurrentExceptionMsg())
    shouldAbort = true
    result = ExitFatalRuntime
  finally:
    if not client.isNil:
      shutdownRelay(client, shouldAbort)

when isMainModule:
  quit(runApp())
