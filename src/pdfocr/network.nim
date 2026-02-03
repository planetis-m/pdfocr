import threading/channels
import ./[config, logging, types]

type
  NetworkContext* = object
    config*: Config
    inputChan*: Chan[InputMessage]
    outputChan*: Chan[OutputMessage]

proc runNetworkWorker*(ctx: NetworkContext) {.thread.} =
  logInfo("Network worker thread started (placeholder).")
  var msg: InputMessage
  ctx.inputChan.recv(msg)
  if msg.kind == imInputDone:
    ctx.outputChan.send(OutputMessage(kind: omOutputDone))
