import std/[monotimes, os, random, times]
import jsonx/streams
import relay
import openai, openai_retry
import ./[ocr_client, pdf_render, pdfium_wrap, request_id_codec,
  retry_and_errors, retry_queue, types]

const
  RetryPollSliceMs = 25

type
  CachedPayload = object
    webpBytes: seq[byte]

  PipelineState = object
    inFlightCount: int
    activeCount: int
    staged: seq[PageResult]
    cachedPayloads: seq[CachedPayload]
    retryQueue: RetryQueue
    nextSubmitSeqId: int
    nextEmitSeqId: int
    remaining: int
    submitBatch: RequestBatch
    allSucceeded: bool
    rng: Rand
    output: Stream

proc okPageResult(page, attempts: int; text: sink string): PageResult {.inline.} =
  PageResult(
    page: page,
    attempts: attempts,
    status: PageOk,
    text: text,
    errorKind: NoError,
    errorMessage: "",
    httpStatus: 0
  )

proc errorPageResult(page, attempts: int; kind: PageErrorKind;
    message: sink string; httpStatus = 0): PageResult {.inline.} =
  PageResult(
    page: page,
    attempts: attempts,
    status: PageError,
    text: "",
    errorKind: kind,
    errorMessage: message,
    httpStatus: httpStatus
  )

proc initPipelineState(total: int): PipelineState =
  PipelineState(
    inFlightCount: 0,
    activeCount: 0,
    staged: newSeq[PageResult](total),
    cachedPayloads: newSeq[CachedPayload](total),
    retryQueue: initRetryQueue(),
    nextSubmitSeqId: 0,
    nextEmitSeqId: 0,
    remaining: total,
    submitBatch: RequestBatch(),
    allSucceeded: true,
    rng: initRand(getMonoTime().ticks),
    output: streams.open(stdout)
  )

proc emitPageResult(output: Stream; value: PageResult): bool =
  output.writeJson(value)
  streams.write(output, '\n')
  result = value.status == PageOk

proc flushOrderedResults(state: var PipelineState) =
  while state.nextEmitSeqId < state.staged.len and
      state.staged[state.nextEmitSeqId].status != PagePending:
    if not emitPageResult(state.output, state.staged[state.nextEmitSeqId]):
      state.allSucceeded = false
    state.staged[state.nextEmitSeqId] = default(PageResult)
    inc state.nextEmitSeqId
    dec state.remaining

proc startBatchIfAny(client: Relay; state: var PipelineState) =
  if state.submitBatch.len > 0:
    client.startRequests(state.submitBatch)

proc prepareFreshPayload(cfg: RuntimeConfig; doc: PdfDocument; seqId: int;
    state: var PipelineState): bool =
  let pageNumber = cfg.selectedPages[seqId]
  try:
    let webp = renderPageToWebp(doc, pageNumber, cfg.renderConfig)
    state.cachedPayloads[seqId] = CachedPayload(webpBytes: webp)
    result = true
  except IOError:
    state.staged[seqId] = errorPageResult(
      page = pageNumber,
      attempts = 1,
      kind = PdfError,
      message = getCurrentExceptionMsg()
    )
  except ValueError:
    state.staged[seqId] = errorPageResult(
      page = pageNumber,
      attempts = 1,
      kind = EncodeError,
      message = getCurrentExceptionMsg()
    )

proc queueAttemptFromPayload(cfg: RuntimeConfig; seqId, attempt: int;
    state: var PipelineState): bool =
  let pageNumber = cfg.selectedPages[seqId]
  let requestId = packRequestId(seqId, attempt)

  try:
    chatAdd(
      state.submitBatch, 
      cfg.openaiConfig,
      params = buildOcrParams(cfg.networkConfig, state.cachedPayloads[seqId].webpBytes),
      requestId = requestId,
      timeoutMs = cfg.networkConfig.totalTimeoutMs
    )
    inc state.inFlightCount
    result = true
  except CatchableError:
    state.staged[seqId] = errorPageResult(
      page = pageNumber,
      attempts = attempt,
      kind = NetworkError,
      message = getCurrentExceptionMsg()
    )
    state.cachedPayloads[seqId] = default(CachedPayload)

proc submitDueRetries(cfg: RuntimeConfig; maxInFlight: int;
    state: var PipelineState) =
  if state.inFlightCount < maxInFlight:
    let now = getMonoTime()
    var retryItem: RetryItem
    while state.inFlightCount < maxInFlight and
        popDueRetry(state.retryQueue, now, retryItem):
      if not queueAttemptFromPayload(cfg, retryItem.seqId, retryItem.attempt, state):
        dec state.activeCount

proc submitFreshAttempts(cfg: RuntimeConfig; doc: PdfDocument; maxInFlight: int;
    state: var PipelineState) =
  if state.activeCount < maxInFlight and state.nextSubmitSeqId < state.staged.len:
    let capacity = maxInFlight - state.activeCount
    var added = 0
    while added < capacity and state.nextSubmitSeqId < state.staged.len:
      if prepareFreshPayload(cfg, doc, state.nextSubmitSeqId, state):
        inc state.activeCount
        if queueAttemptFromPayload(cfg, state.nextSubmitSeqId, 1, state):
          inc added
        else:
          dec state.activeCount
      inc state.nextSubmitSeqId

proc processResult(cfg: RuntimeConfig; item: RequestResult; maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState) =
  let requestId = item.response.request.requestId
  let meta = unpackRequestId(requestId)
  let seqId = meta.seqId
  let attempt = meta.attempt
  dec state.inFlightCount

  if shouldRetry(item, attempt, maxAttempts):
    let delayMs = retryDelayMs(state.rng, attempt, retryPolicy)
    state.retryQueue.addRetry(RetryItem(
      seqId: seqId,
      attempt: attempt + 1,
      dueAt: getMonoTime() + initDuration(milliseconds = delayMs)
    ))
  else:
    let pageNumber = cfg.selectedPages[seqId]
    if item.error.kind != teNone or not isHttpSuccess(item.response.code):
      let finalError = classifyFinalError(item)
      state.staged[seqId] = errorPageResult(
        page = pageNumber,
        attempts = attempt,
        kind = finalError.kind,
        message = finalError.message,
        httpStatus = finalError.httpStatus
      )
    else:
      var text = ""
      if parseOcrText(item.response.body, text):
        state.staged[seqId] = okPageResult(
          page = pageNumber,
          attempts = attempt,
          text = text
        )
      else:
        state.staged[seqId] = errorPageResult(
          page = pageNumber,
          attempts = attempt,
          kind = ParseError,
          message = "failed to parse OCR response"
        )
    state.cachedPayloads[seqId] = default(CachedPayload)
    dec state.activeCount

proc drainReadyResults(cfg: RuntimeConfig; client: Relay; maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState): bool =
  var item: RequestResult
  while client.pollForResult(item):
    processResult(cfg, item, maxAttempts, retryPolicy, state)
    result = true

proc waitForSingleResult(cfg: RuntimeConfig; client: Relay; maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState) =
  var item: RequestResult
  if not client.waitForResult(item):
    raise newException(IOError, "relay worker stopped before all results arrived")
  processResult(cfg, item, maxAttempts, retryPolicy, state)

proc waitForProgress(cfg: RuntimeConfig; client: Relay; maxInFlight, maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState) =
  if state.inFlightCount == 0:
    let sleepMs = nextRetryDelayMs(state.retryQueue)
    if sleepMs < 0:
      raise newException(ValueError, "pipeline stalled before all results arrived")
    if sleepMs > 0:
      sleep(sleepMs)
  else:
    let nextRetryMs = nextRetryDelayMs(state.retryQueue)
    if nextRetryMs < 0:
      waitForSingleResult(cfg, client, maxAttempts, retryPolicy, state)
    elif nextRetryMs == 0 and state.inFlightCount == maxInFlight:
      waitForSingleResult(cfg, client, maxAttempts, retryPolicy, state)
    elif nextRetryMs > 0:
      sleep(min(RetryPollSliceMs, nextRetryMs))

proc runPipeline*(cfg: RuntimeConfig; client: Relay): bool =
  let total = cfg.selectedPages.len
  let maxInFlight = max(1, cfg.networkConfig.maxInflight)
  let maxAttempts = max(1, cfg.networkConfig.maxRetries + 1)
  let retryPolicy = defaultRetryPolicy(maxAttempts = maxAttempts)
  ensureRequestIdCapacity(total, maxAttempts)

  var state = initPipelineState(total)

  initPdfium()
  defer: destroyPdfium()
  let doc = loadDocument(cfg.inputPath)

  while state.remaining > 0:
    submitDueRetries(cfg, maxInFlight, state)
    submitFreshAttempts(cfg, doc, maxInFlight, state)
    startBatchIfAny(client, state)
    flushOrderedResults(state)

    let drained = drainReadyResults(cfg, client, maxAttempts, retryPolicy, state)
    flushOrderedResults(state)

    if state.remaining > 0 and not drained:
      waitForProgress(cfg, client, maxInFlight, maxAttempts, retryPolicy, state)
      flushOrderedResults(state)

  result = state.allSucceeded
