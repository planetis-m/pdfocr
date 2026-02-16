import std/[base64, tables]
import ./bindings/curl
import ./[constants, curl, json_codec, types]

const
  OCRInstruction = "Extract all readable text exactly."

type
  RequestResponseBuffer* = object
    body*: string

  BatchRequestContext* = ref object
    seqId*: SeqId
    page*: int
    attempt*: int
    webpBytes*: seq[byte]
    response*: RequestResponseBuffer
    easy*: CurlEasy
    headers*: CurlSlist

  BatchCompletionStatus* = enum
    bcsNone,
    bcsDone,
    bcsUnknownHandle

  BatchCompletion* = object
    curlCode*: CURLcode
    request*: BatchRequestContext

  HttpBatchClient* = object
    multi: CurlMulti
    activeTransfers: Table[uint, BatchRequestContext]
    idleEasy: seq[CurlEasy]

proc writeResponseCb(buffer: ptr char; size: csize_t; nitems: csize_t; userdata: pointer): csize_t {.cdecl.} =
  let total = int(size * nitems)
  if total > 0:
    let state = cast[ptr RequestResponseBuffer](userdata)
    if state != nil:
      let start = state.body.len
      state.body.setLen(start + total)
      copyMem(addr state.body[start], buffer, total)
    result = csize_t(total)
  else:
    result = 0

proc acquireEasy(client: var HttpBatchClient): CurlEasy =
  if client.idleEasy.len == 0:
    result = initEasy()
  else:
    result = client.idleEasy.pop()
    result.reset()

proc recycleEasy*(client: var HttpBatchClient; easy: sink CurlEasy) =
  if easy != nil:
    client.idleEasy.add(easy)

proc requestToCtx(task: RenderedTask; apiKey: string; easy: var CurlEasy): BatchRequestContext =
  result = BatchRequestContext(
    seqId: task.seqId,
    page: task.page,
    attempt: task.attempt,
    webpBytes: task.webpBytes,
    response: RequestResponseBuffer(body: "")
  )

  let imageDataUrl = "data:image/webp;base64," & base64.encode(task.webpBytes)
  let body = buildChatCompletionRequest(OCRInstruction, imageDataUrl)

  result.headers.addHeader("Authorization: Bearer " & apiKey)
  result.headers.addHeader("Content-Type: application/json")
  easy.setUrl(ApiUrl)
  easy.setWriteCallback(writeResponseCb, cast[pointer](addr result.response))
  easy.setPostFields(body)
  easy.setHeaders(result.headers)
  easy.setTimeoutMs(TotalTimeoutMs)
  easy.setConnectTimeoutMs(ConnectTimeoutMs)
  easy.setSslVerify(true, true)
  easy.setAcceptEncoding("gzip, deflate")

proc initHttpBatchClient*(): HttpBatchClient =
  result = HttpBatchClient(
    multi: initMulti(),
    activeTransfers: initTable[uint, BatchRequestContext](),
    idleEasy: @[]
  )

proc inflightCount*(client: HttpBatchClient): int {.inline.} =
  client.activeTransfers.len

proc submitRenderedTask*(client: var HttpBatchClient; task: RenderedTask; apiKey: string) =
  var easy: CurlEasy
  var added = false
  try:
    easy = client.acquireEasy()
    let req = requestToCtx(task, apiKey, easy)
    req.easy = easy
    client.multi.addHandle(easy)
    added = true
    client.activeTransfers[handleKey(easy)] = req
  except CatchableError:
    if added:
      try:
        client.multi.removeHandle(easy)
      except CatchableError:
        discard
    client.recycleEasy(easy)
    raise

proc performAndPoll*(client: var HttpBatchClient; timeoutMs: int) =
  discard client.multi.perform()
  discard client.multi.poll(timeoutMs)

proc tryReadCompletion*(client: var HttpBatchClient; completion: var BatchCompletion): BatchCompletionStatus =
  var msg: CURLMsg
  var msgsInQueue = 0
  result = bcsNone
  while result == bcsNone and client.multi.tryInfoRead(msg, msgsInQueue):
    if msg.msg == CURLMSG_DONE:
      let key = handleKey(msg)
      if not client.activeTransfers.hasKey(key):
        result = bcsUnknownHandle
      else:
        client.multi.removeHandle(msg)
        var req: BatchRequestContext
        if client.activeTransfers.pop(key, req):
          completion = BatchCompletion(
            curlCode: msg.data.result,
            request: req
          )
          result = bcsDone
        else:
          result = bcsUnknownHandle

proc cancelAllActive*(client: var HttpBatchClient) =
  var activeKeys = newSeqOfCap[uint](client.activeTransfers.len)
  for key in client.activeTransfers.keys:
    activeKeys.add(key)

  for key in activeKeys:
    var req: BatchRequestContext
    if client.activeTransfers.pop(key, req):
      try:
        client.multi.removeHandle(req.easy)
      except CatchableError:
        discard
      client.recycleEasy(req.easy)
