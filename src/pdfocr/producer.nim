import threading/channels
import ./[config, logging, types]

type
  ProducerContext* = object
    pdfPath*: string
    pageStart*: int
    pageEnd*: int
    outputDir*: string
    config*: Config
    inputChan*: Chan[InputMessage]

proc runProducer*(ctx: ProducerContext) {.thread.} =
  logInfo("Producer thread started (placeholder).")
  ctx.inputChan.send(InputMessage(kind: imInputDone))
