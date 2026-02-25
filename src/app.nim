import std/os
import relay
import ./[constants, logging, pipeline, runtime_config]

proc logMemoryUsage(stage: string) =
  when defined(debug):
    logInfo("memory " & stage & ": occupied=" & $getOccupiedMem() &
      " free=" & $getFreeMem() & " total=" & $getTotalMem())

proc logRelayUsage(stage: string; client: Relay) =
  when defined(debug):
    if client.isNil:
      logInfo("relay_mem " & stage & ": client=nil")
    else:
      let snap = client.debugSnapshot()
      logInfo("relay_mem " & stage &
        ": queue=" & $snap.queueLen &
        " inflight=" & $snap.inFlightLen &
        " ready=" & $snap.readyLen &
        " easy_idle=" & $snap.availableEasyLen &
        " queue_body_bytes=" & $snap.queueBodyBytes &
        " inflight_body_bytes=" & $snap.inFlightBodyBytes &
        " ready_resp_body_bytes=" & $snap.readyResponseBodyBytes &
        " ready_resp_header_bytes=" & $snap.readyResponseHeaderBytes &
        " ready_error_msg_bytes=" & $snap.readyErrorMessageBytes)

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

    logMemoryUsage("startup")
    logMemoryUsage("before_newRelay")
    logRelayUsage("before_newRelay", client)

    client = newRelay(
      maxInFlight = cfg.networkConfig.maxInflight,
      defaultTimeoutMs = cfg.networkConfig.totalTimeoutMs
    )
    logMemoryUsage("after_newRelay")
    logRelayUsage("after_newRelay", client)

    let allSucceeded = runPipeline(cfg, client)
    logMemoryUsage("after_pipeline.before_trim_idle")
    logRelayUsage("after_pipeline.before_trim_idle", client)
    logMemoryUsage("after_pipeline")
    result = if allSucceeded: ExitAllOk else: ExitPartialFailure
  except CatchableError:
    logError(getCurrentExceptionMsg())
    logMemoryUsage("after_exception")
    shouldAbort = true
    result = ExitFatalRuntime
  finally:
    logMemoryUsage("shutdown.begin")
    if not client.isNil:
      logMemoryUsage("shutdown.before_relay_close")
      logRelayUsage("shutdown.before_relay_close", client)
      shutdownRelay(client, shouldAbort)
      logMemoryUsage("shutdown.after_relay_close")
      logRelayUsage("shutdown.after_relay_close", client)

when isMainModule:
  quit(runApp())
