import threading/channels
import ./[config, logging, types]

type
  OutputContext* = object
    outputDir*: string
    config*: Config
    outputChan*: Chan[OutputMessage]

proc runOutputWriter*(ctx: OutputContext) {.thread.} =
  logInfo("Output writer thread started (placeholder).")
  var msg: OutputMessage
  ctx.outputChan.recv(msg)
  if msg.kind == omOutputDone:
    logInfo("Output writer received completion signal.")
