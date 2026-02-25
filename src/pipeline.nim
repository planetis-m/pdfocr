import std/[monotimes, os, random, times]
import jsonx/streams
import relay
import openai, openai_retry
import ./[ocr_client, pdf_render, pdfium_wrap, request_id_codec,
  retry_and_errors, retry_queue, types, logging]

const
  RetryPollSliceMs = 25

type
  PipelineState = object
    inFlightCount: int
    activeCount: int
    staged: seq[PageResult]
    retryQueue: RetryQueue
    nextSubmitSeqId: int
    nextEmitSeqId: int
    remaining: int
    submitBatch: RequestBatch
    rng: Rand
    output: Stream
    allSucceeded: bool
    when defined(debug):
      memLastOccupied: int
      memPeakOccupied: int
      memSamples: int
      loopIterations: int

proc logPipelineMemory(stage: string; state: var PipelineState;
    details = "") =
  when defined(debug):
    let occupied = getOccupiedMem()
    let freeMem = getFreeMem()
    let totalMem = getTotalMem()
    let delta = occupied - state.memLastOccupied
    if occupied > state.memPeakOccupied:
      state.memPeakOccupied = occupied
    inc state.memSamples
    let suffix =
      if details.len > 0:
        " " & details
      else:
        ""
    logInfo("pipeline_mem " & stage &
      ": occupied=" & $occupied &
      " delta=" & $delta &
      " peak=" & $state.memPeakOccupied &
      " free=" & $freeMem &
      " total=" & $totalMem &
      " samples=" & $state.memSamples &
      " in_flight=" & $state.inFlightCount &
      " active=" & $state.activeCount &
      " remaining=" & $state.remaining &
      " batch=" & $state.submitBatch.len &
      suffix)
    state.memLastOccupied = occupied

proc logRelaySnapshot(stage: string; client: Relay; details = "") =
  when defined(debug):
    let snap = client.debugSnapshot()
    let suffix =
      if details.len > 0:
        " " & details
      else:
        ""
    logInfo("relay_mem " & stage &
      ": queue=" & $snap.queueLen &
      " inflight=" & $snap.inFlightLen &
      " ready=" & $snap.readyLen &
      " easy_idle=" & $snap.availableEasyLen &
      " queue_body_bytes=" & $snap.queueBodyBytes &
      " inflight_body_bytes=" & $snap.inFlightBodyBytes &
      " ready_resp_body_bytes=" & $snap.readyResponseBodyBytes &
      " ready_resp_header_bytes=" & $snap.readyResponseHeaderBytes &
      " ready_error_msg_bytes=" & $snap.readyErrorMessageBytes &
      suffix)

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
  result = PipelineState(
    inFlightCount: 0,
    activeCount: 0,
    staged: newSeq[PageResult](total),
    retryQueue: initRetryQueue(),
    nextSubmitSeqId: 0,
    nextEmitSeqId: 0,
    remaining: total,
    submitBatch: RequestBatch(),
    rng: initRand(getMonoTime().ticks),
    output: streams.open(stdout),
    allSucceeded: true
  )
  when defined(debug):
    let occupied = getOccupiedMem()
    result.memLastOccupied = occupied
    result.memPeakOccupied = occupied
    result.memSamples = 0
    result.loopIterations = 0

proc emitPageResult(output: Stream; value: PageResult): bool =
  output.writeJson(value)
  streams.write(output, '\n')
  result = value.status == PageOk

proc flushOrderedResults(state: var PipelineState) =
  var emitted = 0
  while state.nextEmitSeqId < state.staged.len and
      state.staged[state.nextEmitSeqId].status != PagePending:
    let pageResult = state.staged[state.nextEmitSeqId]
    if not emitPageResult(state.output, pageResult):
      state.allSucceeded = false
    state.staged[state.nextEmitSeqId] = PageResult(status: PagePending)
    inc state.nextEmitSeqId
    dec state.remaining
    inc emitted
  if emitted > 0:
    logPipelineMemory("flush_ordered", state, "emitted=" & $emitted)

proc startBatchIfAny(client: Relay; state: var PipelineState) =
  if state.submitBatch.len > 0:
    logPipelineMemory("start_batch.before", state)
    logRelaySnapshot("start_batch.before", client)
    client.startRequests(state.submitBatch)
    logPipelineMemory("start_batch.after", state)
    logRelaySnapshot("start_batch.after", client)

proc queueAttempt(cfg: RuntimeConfig; doc: PdfDocument; seqId, attempt: int;
    state: var PipelineState): bool =
  let pageNumber = cfg.selectedPages[seqId]
  let requestId = packRequestId(seqId, attempt)
  logPipelineMemory("queue_attempt.begin", state,
    "seq=" & $seqId & " page=" & $pageNumber & " attempt=" & $attempt)

  try:
    let webp = renderPageToWebp(doc, pageNumber, cfg.renderConfig)
    logPipelineMemory("queue_attempt.after_render", state,
      "seq=" & $seqId & " webp_bytes=" & $webp.len)
    let params = buildOcrParams(cfg.networkConfig, webp)
    let encodedLen = ((webp.len + 2) div 3) * 4
    logPipelineMemory("queue_attempt.after_params", state,
      "seq=" & $seqId & " base64_est=" & $encodedLen)
    chatAdd(
      state.submitBatch,
      cfg.openaiConfig,
      params = params,
      requestId = requestId,
      timeoutMs = cfg.networkConfig.totalTimeoutMs
    )
    logPipelineMemory("queue_attempt.after_chat_add", state,
      "seq=" & $seqId)
    inc state.inFlightCount
    result = true
  except IOError:
    state.staged[seqId] = errorPageResult(
      page = pageNumber,
      attempts = attempt,
      kind = PdfError,
      message = getCurrentExceptionMsg()
    )
    logPipelineMemory("queue_attempt.pdf_error", state,
      "seq=" & $seqId & " attempt=" & $attempt)
  except ValueError:
    state.staged[seqId] = errorPageResult(
      page = pageNumber,
      attempts = attempt,
      kind = EncodeError,
      message = getCurrentExceptionMsg()
    )
    logPipelineMemory("queue_attempt.encode_error", state,
      "seq=" & $seqId & " attempt=" & $attempt)
  except CatchableError:
    state.staged[seqId] = errorPageResult(
      page = pageNumber,
      attempts = attempt,
      kind = NetworkError,
      message = getCurrentExceptionMsg()
    )
    logPipelineMemory("queue_attempt.network_error", state,
      "seq=" & $seqId & " attempt=" & $attempt)
    result = false

proc submitDueRetries(cfg: RuntimeConfig; doc: PdfDocument; maxInFlight: int;
    state: var PipelineState) =
  if state.inFlightCount < maxInFlight:
    logPipelineMemory("submit_due_retries.begin", state)
    let now = getMonoTime()
    var retryItem: RetryItem
    while state.inFlightCount < maxInFlight and
        popDueRetry(state.retryQueue, now, retryItem):
      if not queueAttempt(cfg, doc, retryItem.seqId, retryItem.attempt, state):
        dec state.activeCount
    logPipelineMemory("submit_due_retries.end", state)

proc submitFreshAttempts(cfg: RuntimeConfig; doc: PdfDocument; maxInFlight: int;
    state: var PipelineState) =
  if state.activeCount < maxInFlight and state.nextSubmitSeqId < state.staged.len:
    logPipelineMemory("submit_fresh.begin", state)
    let capacity = maxInFlight - state.activeCount
    var added = 0
    while added < capacity and state.nextSubmitSeqId < state.staged.len:
      inc state.activeCount
      if queueAttempt(cfg, doc, state.nextSubmitSeqId, 1, state):
        inc added
      else:
        dec state.activeCount
      inc state.nextSubmitSeqId
    logPipelineMemory("submit_fresh.end", state)

proc processResult(cfg: RuntimeConfig; item: RequestResult; maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState) =
  let requestId = item.response.request.requestId
  let meta = unpackRequestId(requestId)
  let seqId = meta.seqId
  let attempt = meta.attempt
  logPipelineMemory("process_result.begin", state,
    "seq=" & $seqId & " attempt=" & $attempt &
    " code=" & $item.response.code &
    " transport=" & $ord(item.error.kind))
  dec state.inFlightCount

  if shouldRetry(item, attempt, maxAttempts):
    let delayMs = retryDelayMs(state.rng, attempt, retryPolicy)
    state.retryQueue.addRetry(RetryItem(
      seqId: seqId,
      attempt: attempt + 1,
      dueAt: getMonoTime() + initDuration(milliseconds = delayMs)
    ))
    logPipelineMemory("process_result.retry_scheduled", state,
      "seq=" & $seqId & " next_attempt=" & $(attempt + 1))
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
    dec state.activeCount
    logPipelineMemory("process_result.finalized", state,
      "seq=" & $seqId & " attempt=" & $attempt)

proc drainReadyResults(cfg: RuntimeConfig; client: Relay; maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState): bool =
  var item: RequestResult
  var drainedCount = 0
  while client.pollForResult(item):
    processResult(cfg, item, maxAttempts, retryPolicy, state)
    inc drainedCount
    result = true
  if drainedCount > 0:
    logPipelineMemory("drain_ready", state, "count=" & $drainedCount)
    logRelaySnapshot("drain_ready", client, "count=" & $drainedCount)

proc waitForSingleResult(cfg: RuntimeConfig; client: Relay; maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState) =
  logPipelineMemory("wait_single.before", state)
  logRelaySnapshot("wait_single.before", client)
  var item: RequestResult
  if not client.waitForResult(item):
    raise newException(IOError, "relay worker stopped before all results arrived")
  processResult(cfg, item, maxAttempts, retryPolicy, state)
  logPipelineMemory("wait_single.after", state)
  logRelaySnapshot("wait_single.after", client)

proc waitForProgress(cfg: RuntimeConfig; client: Relay; maxInFlight, maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState) =
  logPipelineMemory("wait_progress.begin", state)
  if state.inFlightCount == 0:
    let sleepMs = nextRetryDelayMs(state.retryQueue)
    if sleepMs < 0:
      raise newException(ValueError, "pipeline stalled before all results arrived")
    if sleepMs > 0:
      sleep(sleepMs)
      logPipelineMemory("wait_progress.sleep_no_inflight", state, "sleep_ms=" & $sleepMs)
  else:
    let nextRetryMs = nextRetryDelayMs(state.retryQueue)
    if nextRetryMs < 0:
      waitForSingleResult(cfg, client, maxAttempts, retryPolicy, state)
    elif nextRetryMs == 0 and state.inFlightCount == maxInFlight:
      waitForSingleResult(cfg, client, maxAttempts, retryPolicy, state)
    elif nextRetryMs > 0:
      sleep(min(RetryPollSliceMs, nextRetryMs))
      logPipelineMemory("wait_progress.sleep_poll", state,
        "next_retry_ms=" & $nextRetryMs)

proc runPipeline*(cfg: RuntimeConfig; client: Relay): bool =
  let total = cfg.selectedPages.len
  let maxInFlight = max(1, cfg.networkConfig.maxInflight)
  let maxAttempts = max(1, cfg.networkConfig.maxRetries + 1)
  let retryPolicy = defaultRetryPolicy(maxAttempts = maxAttempts)
  ensureRequestIdCapacity(total, maxAttempts)

  var state = initPipelineState(total)
  logPipelineMemory("run_pipeline.init_state", state, "total_pages=" & $total)
  logRelaySnapshot("run_pipeline.init_state", client, "total_pages=" & $total)

  initPdfium()
  logPipelineMemory("run_pipeline.after_init_pdfium", state)
  logRelaySnapshot("run_pipeline.after_init_pdfium", client)
  defer: destroyPdfium()
  let doc = loadDocument(cfg.inputPath)
  logPipelineMemory("run_pipeline.after_load_document", state)
  logRelaySnapshot("run_pipeline.after_load_document", client)

  while state.remaining > 0:
    when defined(debug):
      inc state.loopIterations
    logPipelineMemory("run_pipeline.loop_begin", state,
      "iter=" & $state.loopIterations)
    logRelaySnapshot("run_pipeline.loop_begin", client, "iter=" & $state.loopIterations)
    submitDueRetries(cfg, doc, maxInFlight, state)
    submitFreshAttempts(cfg, doc, maxInFlight, state)
    startBatchIfAny(client, state)
    flushOrderedResults(state)

    let drained = drainReadyResults(cfg, client, maxAttempts, retryPolicy, state)
    flushOrderedResults(state)

    if state.remaining > 0 and not drained:
      waitForProgress(cfg, client, maxInFlight, maxAttempts, retryPolicy, state)
      flushOrderedResults(state)
    logPipelineMemory("run_pipeline.loop_end", state,
      "iter=" & $state.loopIterations)
    logRelaySnapshot("run_pipeline.loop_end", client, "iter=" & $state.loopIterations)

  logPipelineMemory("run_pipeline.done", state)
  logRelaySnapshot("run_pipeline.done", client)
  result = state.allSucceeded
