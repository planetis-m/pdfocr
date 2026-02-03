import threading/channels
import ./[config, logging, types]

type
  NetworkContext* = object
    apiKey*: string
    config*: Config
    inputChan*: Chan[InputMessage]
    outputChan*: Chan[OutputMessage]

proc runNetworkWorker*(ctx: NetworkContext) {.thread.} =
  logWarn("Network worker stub enabled (thread sanitizer mode). No HTTP requests will be made.")
  var msg: InputMessage
  while true:
    ctx.inputChan.recv(msg)
    case msg.kind
    of imTaskBatch:
      for task in msg.tasks:
        ctx.outputChan.send(OutputMessage(
          kind: omPageResult,
          result: Result(
            pageId: task.pageId,
            pageNumberUser: task.pageNumberUser,
            status: rsFailure,
            text: "",
            errorKind: ekNetworkError,
            errorMessage: "network worker stub (tsan)",
            httpStatus: 0,
            attemptCount: task.attempt + 1,
            startedAt: task.createdAt,
            finishedAt: task.createdAt
          )
        ))
    of imInputDone:
      ctx.outputChan.send(OutputMessage(kind: omOutputDone))
      break
