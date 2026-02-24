import std/[os, random, times]
import jsonx, jsonx/streams
import relay
import openai, openai_retry
import ./[ocr_client, pdf_render, pdfium_wrap, request_id_codec,
  retry_and_errors, types]

type
  PipelineState = object
    inFlightCount: int
    staged: seq[PageResult]
    nextSubmitSeqId: int
    nextEmitSeqId: int
    remaining: int
    submitBatch: RequestBatch
    allSucceeded: bool
    rng: Rand
    output: Stream

proc okPageResult(page: int; attempts: int; text: sink string): PageResult {.inline.} =
  PageResult(
    page: page,
    attempts: attempts,
    status: PageOk,
    text: text,
    errorKind: NoError,
    errorMessage: "",
    httpStatus: 0
  )

proc errorPageResult(page: int; attempts: int; kind: PageErrorKind;
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
    staged: newSeq[PageResult](total),
    nextSubmitSeqId: 0,
    nextEmitSeqId: 0,
    remaining: total,
    allSucceeded: true,
    rng: initRand(epochTime().int64),
    output: streams.open(stdout)
  )

proc emitPageResult(output: Stream; value: PageResult): bool =
  output.writeJson(value)
  streams.write(output, '\n')
  result = value.status == PageOk

proc flushOrderedResults(state: var PipelineState) =
  while state.nextEmitSeqId < state.staged.len and
      state.staged[state.nextEmitSeqId].status != PagePending:
    let pageResult = state.staged[state.nextEmitSeqId]
    if not emitPageResult(state.output, pageResult):
      state.allSucceeded = false
    state.staged[state.nextEmitSeqId] = PageResult(status: PagePending)
    inc state.nextEmitSeqId
    dec state.remaining

proc startBatchIfAny(client: Relay; state: var PipelineState) =
  if state.submitBatch.len > 0:
    client.startRequests(state.submitBatch)

proc queueAttempt(cfg: RuntimeConfig; doc: PdfDocument; seqId: int; attempt: int;
    state: var PipelineState) =
  let pageNumber = cfg.selectedPages[seqId]
  var webp: seq[byte]
  var canBuildRequest = false
  try:
    webp = renderPageToWebp(doc, pageNumber, cfg.renderConfig)
    canBuildRequest = true
  except IOError:
    state.staged[seqId] = errorPageResult(
      page = pageNumber,
      attempts = attempt,
      kind = PdfError,
      message = getCurrentExceptionMsg()
    )
  except ValueError:
    state.staged[seqId] = errorPageResult(
      page = pageNumber,
      attempts = attempt,
      kind = EncodeError,
      message = getCurrentExceptionMsg()
    )

  if canBuildRequest:
    let requestId = packRequestId(seqId, attempt)
    try:
      let req = buildOcrRequest(cfg.networkConfig, cfg.apiKey, webp, requestId)
      state.submitBatch.addRequest(
        verb = req.verb,
        url = req.url,
        headers = req.headers,
        body = req.body,
        requestId = req.requestId,
        timeoutMs = req.timeoutMs
      )
      inc state.inFlightCount
    except CatchableError:
      state.staged[seqId] = errorPageResult(
        page = pageNumber,
        attempts = attempt,
        kind = NetworkError,
        message = getCurrentExceptionMsg()
      )

proc submitFreshAttempts(cfg: RuntimeConfig; doc: PdfDocument; client: Relay;
    maxInFlight: int; state: var PipelineState) =
  if state.inFlightCount < maxInFlight and state.nextSubmitSeqId < state.staged.len:
    let capacity = maxInFlight - state.inFlightCount
    let startLen = state.submitBatch.len
    var added = 0
    while added < capacity and state.nextSubmitSeqId < state.staged.len:
      queueAttempt(cfg, doc, state.nextSubmitSeqId, 1, state)
      inc state.nextSubmitSeqId
      if state.submitBatch.len > startLen + added:
        inc added
    startBatchIfAny(client, state)
    flushOrderedResults(state)

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
    submitFreshAttempts(cfg, doc, client, maxInFlight, state)

    if state.remaining > 0:
      if state.inFlightCount == 0:
        raise newException(IOError, "pipeline stalled before all results arrived")
      var item: RequestResult
      if not client.waitForResult(item):
        raise newException(IOError, "relay worker stopped before all results arrived")

      let requestId = item.response.request.requestId
      let meta = unpackRequestId(requestId)
      let seqId = meta.seqId
      let attempt = meta.attempt
      dec state.inFlightCount

      if shouldRetry(item, attempt, maxAttempts):
        let delayMs = retryDelayMs(state.rng, attempt, retryPolicy)
        if delayMs > 0:
          sleep(delayMs)
        queueAttempt(cfg, doc, seqId, attempt + 1, state)
        startBatchIfAny(client, state)
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
      flushOrderedResults(state)

  result = state.allSucceeded
