import std/[base64, locks, os, random, times]
import ./bindings/curl
import ./[constants, curl, errors, json_codec, pdfium, types, webp]

const
  BatchCount = 3
  BatchSize = 32
  OcrInstruction = "Extract all readable text exactly."
  RetryJitterDivisor = 2

type
  Owner = enum
    OwnMain,
    OwnRenderer,
    OwnNetwork,
    OwnWriter

  Phase = enum
    PhaseEmpty,
    PhaseRendered,
    PhaseNetworked

  SlotStr = object
    data: pointer
    len: int

  BatchMeta = object
    owner: Owner
    phase: Phase
    startSeq: int
    count: int
    generation: uint64
    readyForMain: bool

  RequestOutcome = object
    ok: bool
    text: string
    errorKind: ErrorKind
    errorMessage: string
    httpStatus: HttpCode
    retryable: bool

  RendererThreadCtx = object
    pdfPath: string

  NetworkThreadCtx = object
    apiKey: string

  WriterThreadCtx = object

var
  gMu: Lock
  gCv: Cond

  gMeta: array[BatchCount, BatchMeta]
  gSlots: array[BatchCount, array[BatchSize, SlotStr]]
  gSlotIsFinal: array[BatchCount, array[BatchSize, bool]]
  gSlotIsError: array[BatchCount, array[BatchSize, bool]]

  gSelectedPages: ptr UncheckedArray[int]
  gTotalPages: int
  gNextSeqToRender: int
  gNextBatchToWrite: int

  gFatal: bool
  gStop: bool
  gExitCode: int
  gWrittenPages: int
  gOkCount: int
  gErrCount: int

proc clearSlot(slot: var SlotStr) =
  if slot.data != nil:
    deallocShared(slot.data)
  slot.data = nil
  slot.len = 0

proc copyIntoSlot(slot: var SlotStr; value: string) =
  clearSlot(slot)
  if value.len == 0:
    return
  slot.data = allocShared(value.len)
  if slot.data == nil:
    raise newException(OutOfMemDefect, "allocShared failed")
  copyMem(slot.data, unsafeAddr value[0], value.len)
  slot.len = value.len

proc slotEndsWithNewline(slot: SlotStr): bool =
  if slot.data == nil or slot.len <= 0:
    return false
  let bytes = cast[ptr UncheckedArray[char]](slot.data)
  result = bytes[slot.len - 1] == '\n'

proc writeAll(buf: pointer; len: int) =
  var written = 0
  while written < len:
    let remaining = len - written
    let chunkPtr = cast[pointer](cast[uint](buf) + uint(written))
    let n = stdout.writeBuffer(chunkPtr, remaining)
    if n <= 0:
      raise newException(IOError, "stdout write failed")
    inc written, n

proc storeFinalLine(batchIdx, slotIdx, seqId, page, attempts: int;
                    status: PageStatus; text: string;
                    errorKind: ErrorKind; errorMessage: string;
                    httpStatus: HttpCode) =
  let line = encodeResultLine(PageResult(
    seqId: seqId,
    page: page,
    status: status,
    attempts: attempts,
    text: text,
    errorKind: errorKind,
    errorMessage: errorMessage,
    httpStatus: httpStatus
  ))
  copyIntoSlot(gSlots[batchIdx][slotIdx], line)
  gSlotIsFinal[batchIdx][slotIdx] = true
  gSlotIsError[batchIdx][slotIdx] = status == psError

proc storeRequestBody(batchIdx, slotIdx: int; requestBody: string) =
  copyIntoSlot(gSlots[batchIdx][slotIdx], requestBody)
  gSlotIsFinal[batchIdx][slotIdx] = false
  gSlotIsError[batchIdx][slotIdx] = false

proc markFatal() =
  acquire(gMu)
  if not gFatal:
    gFatal = true
    gStop = true
    gExitCode = ExitFatalRuntime
  broadcast(gCv)
  release(gMu)

proc classifyNetworkError(curlCode: CURLcode): ErrorKind =
  if curlCode == CURLE_OPERATION_TIMEDOUT:
    Timeout
  else:
    NetworkError

proc isRetryableHttp(httpCode: HttpCode): bool =
  httpCode >= Http500 and httpCode < Http600

proc backoffBaseMs(attempt: int): int =
  let exponent = if attempt <= 1: 0 else: attempt - 1
  let raw = RetryBaseDelayMs shl exponent
  result = min(raw, RetryMaxDelayMs)

proc retryDelayMs(rng: var Rand; nextAttempt: int): int =
  let base = backoffBaseMs(nextAttempt)
  let jitterMax = max(1, base div RetryJitterDivisor)
  result = base + rng.rand(jitterMax)

proc pageForSeq(seqId: int): int {.inline.} =
  gSelectedPages[seqId]

proc performRequest(payload: SlotStr; apiKey: string): RequestOutcome =
  var responseBody = ""

  proc writeResponseCb(buffer: ptr char; size: csize_t; nitems: csize_t; userdata: pointer): csize_t {.cdecl.} =
    let total = int(size * nitems)
    if total <= 0:
      return 0
    let outStr = cast[ptr string](userdata)
    if outStr != nil:
      let baseLen = outStr[].len
      outStr[].setLen(baseLen + total)
      copyMem(addr outStr[][baseLen], buffer, total)
    result = csize_t(total)

  try:
    var easy = initEasy()
    var headers: CurlSlist
    headers.addHeader("Authorization: Bearer " & apiKey)
    headers.addHeader("Content-Type: application/json")
    easy.setUrl(ApiUrl)
    easy.setWriteCallback(writeResponseCb, cast[pointer](addr responseBody))
    easy.setPostFieldsRaw(payload.data, payload.len)
    easy.setHeaders(headers)
    easy.setTimeoutMs(TotalTimeoutMs)
    easy.setConnectTimeoutMs(ConnectTimeoutMs)
    easy.setSslVerify(true, true)
    easy.setAcceptEncoding("gzip, deflate")

    let curlCode = easy.performCode()
    if curlCode != CURLE_OK:
      let err = classifyNetworkError(curlCode)
      result = RequestOutcome(
        ok: false,
        text: "",
        errorKind: err,
        errorMessage: boundedErrorMessage("curl transfer failed code=" & $int(curlCode)),
        httpStatus: HttpNone,
        retryable: true
      )
      return

    let httpCode = easy.responseCode()
    if httpCode == Http429:
      result = RequestOutcome(
        ok: false,
        text: "",
        errorKind: RateLimit,
        errorMessage: "HTTP 429 rate limited",
        httpStatus: httpCode,
        retryable: true
      )
      return

    if isRetryableHttp(httpCode):
      result = RequestOutcome(
        ok: false,
        text: "",
        errorKind: HttpError,
        errorMessage: boundedErrorMessage("HTTP " & $httpCode),
        httpStatus: httpCode,
        retryable: true
      )
      return

    if httpCode < Http200 or httpCode >= Http300:
      result = RequestOutcome(
        ok: false,
        text: "",
        errorKind: HttpError,
        errorMessage: boundedErrorMessage("HTTP " & $httpCode),
        httpStatus: httpCode,
        retryable: false
      )
      return

    let parsed = parseChatCompletionResponse(responseBody)
    if not parsed.ok:
      result = RequestOutcome(
        ok: false,
        text: "",
        errorKind: ParseError,
        errorMessage: parsed.error_message,
        httpStatus: HttpNone,
        retryable: false
      )
      return

    result = RequestOutcome(
      ok: true,
      text: parsed.text,
      errorKind: NoError,
      errorMessage: "",
      httpStatus: HttpNone,
      retryable: false
    )
  except CatchableError:
    result = RequestOutcome(
      ok: false,
      text: "",
      errorKind: NetworkError,
      errorMessage: boundedErrorMessage(getCurrentExceptionMsg()),
      httpStatus: HttpNone,
      retryable: true
    )

proc findBatchOwnedBy(owner: Owner; phase: Phase): int =
  for i in 0 ..< BatchCount:
    if gMeta[i].owner == owner and gMeta[i].phase == phase and not gMeta[i].readyForMain:
      return i
  -1

proc rendererThreadMain(ctx: RendererThreadCtx) {.thread.} =
  var doc: PdfDocument
  try:
    doc = loadDocument(ctx.pdfPath)
  except CatchableError:
    markFatal()
    return

  while true:
    var
      batchIdx = -1
      startSeq = 0
      count = 0

    acquire(gMu)
    while true:
      batchIdx = findBatchOwnedBy(OwnRenderer, PhaseEmpty)
      if batchIdx >= 0:
        startSeq = gMeta[batchIdx].startSeq
        count = gMeta[batchIdx].count
        break
      if gStop:
        release(gMu)
        return
      wait(gCv, gMu)
    release(gMu)

    try:
      for i in 0 ..< BatchSize:
        if i >= count:
          clearSlot(gSlots[batchIdx][i])
          gSlotIsFinal[batchIdx][i] = false
          gSlotIsError[batchIdx][i] = false
          continue

        let seqId = startSeq + i
        let page = pageForSeq(seqId)

        var cancelRequested = false
        acquire(gMu)
        if gStop:
          cancelRequested = true
        release(gMu)

        if cancelRequested:
          storeFinalLine(
            batchIdx,
            i,
            seqId,
            page,
            1,
            psError,
            "",
            NetworkError,
            "cancelled before render",
            HttpNone
          )
          continue

        var bitmap: PdfBitmap
        var renderOk = false
        try:
          var pdfPage = loadPage(doc, page - 1)
          bitmap = renderPageAtScale(pdfPage, RenderScale, rotate = RenderRotate, flags = RenderFlags)
          renderOk = true
        except CatchableError:
          storeFinalLine(
            batchIdx,
            i,
            seqId,
            page,
            1,
            psError,
            "",
            PdfError,
            boundedErrorMessage(getCurrentExceptionMsg()),
            HttpNone
          )

        if not renderOk:
          continue

        let bmpW = width(bitmap)
        let bmpH = height(bitmap)
        let pixels = buffer(bitmap)
        let rowStride = stride(bitmap)
        if bmpW <= 0 or bmpH <= 0 or pixels.isNil or rowStride <= 0:
          storeFinalLine(
            batchIdx,
            i,
            seqId,
            page,
            1,
            psError,
            "",
            PdfError,
            "invalid bitmap state from renderer",
            HttpNone
          )
          continue

        try:
          let webpBytes = compressBgr(
            Positive(bmpW),
            Positive(bmpH),
            pixels,
            rowStride,
            WebpQuality
          )
          if webpBytes.len == 0:
            storeFinalLine(
              batchIdx,
              i,
              seqId,
              page,
              1,
              psError,
              "",
              EncodeError,
              "encoded WebP output was empty",
              HttpNone
            )
            continue

          let imageDataUrl = "data:image/webp;base64," & base64.encode(webpBytes)
          let requestBody = buildChatCompletionRequest(OcrInstruction, imageDataUrl)
          storeRequestBody(batchIdx, i, requestBody)
        except CatchableError:
          storeFinalLine(
            batchIdx,
            i,
            seqId,
            page,
            1,
            psError,
            "",
            EncodeError,
            boundedErrorMessage(getCurrentExceptionMsg()),
            HttpNone
          )
    except CatchableError:
      markFatal()
      return

    acquire(gMu)
    if gMeta[batchIdx].owner == OwnRenderer:
      gMeta[batchIdx].readyForMain = true
    broadcast(gCv)
    release(gMu)

proc networkThreadMain(ctx: NetworkThreadCtx) {.thread.} =
  var rng = initRand(int(epochTime()))

  while true:
    var
      batchIdx = -1
      startSeq = 0
      count = 0

    acquire(gMu)
    while true:
      batchIdx = findBatchOwnedBy(OwnNetwork, PhaseRendered)
      if batchIdx >= 0:
        startSeq = gMeta[batchIdx].startSeq
        count = gMeta[batchIdx].count
        break
      if gStop:
        release(gMu)
        return
      wait(gCv, gMu)
    release(gMu)

    try:
      for i in 0 ..< count:
        let seqId = startSeq + i
        let page = pageForSeq(seqId)

        if gSlotIsFinal[batchIdx][i]:
          continue

        var attempts = 1
        while true:
          var stopNow = false
          acquire(gMu)
          stopNow = gStop
          release(gMu)

          if stopNow:
            storeFinalLine(
              batchIdx,
              i,
              seqId,
              page,
              attempts,
              psError,
              "",
              NetworkError,
              "cancelled before request",
              HttpNone
            )
            break

          let outcome = performRequest(gSlots[batchIdx][i], ctx.apiKey)
          if outcome.ok:
            storeFinalLine(
              batchIdx,
              i,
              seqId,
              page,
              attempts,
              psOk,
              outcome.text,
              NoError,
              "",
              HttpNone
            )
            break

          let maxAttempts = 1 + MaxRetries
          if outcome.retryable and attempts < maxAttempts:
            inc attempts
            let delayMs = retryDelayMs(rng, attempts)
            sleep(delayMs)
            continue

          storeFinalLine(
            batchIdx,
            i,
            seqId,
            page,
            attempts,
            psError,
            "",
            outcome.errorKind,
            outcome.errorMessage,
            outcome.httpStatus
          )
          break
    except CatchableError:
      markFatal()
      return

    acquire(gMu)
    if gMeta[batchIdx].owner == OwnNetwork:
      gMeta[batchIdx].readyForMain = true
    broadcast(gCv)
    release(gMu)

proc writerThreadMain(_: WriterThreadCtx) {.thread.} =
  while true:
    var
      batchIdx = -1
      count = 0

    acquire(gMu)
    while true:
      batchIdx = findBatchOwnedBy(OwnWriter, PhaseNetworked)
      if batchIdx >= 0:
        count = gMeta[batchIdx].count
        break
      if gStop:
        release(gMu)
        return
      wait(gCv, gMu)
    release(gMu)

    var
      localOk = 0
      localErr = 0

    try:
      for i in 0 ..< count:
        let slot = gSlots[batchIdx][i]
        if slot.data != nil and slot.len > 0:
          writeAll(slot.data, slot.len)
          if not slotEndsWithNewline(slot):
            stdout.write('\n')

        if gSlotIsError[batchIdx][i]:
          inc localErr
        else:
          inc localOk

      flushFile(stdout)
    except CatchableError:
      markFatal()
      return

    for i in 0 ..< BatchSize:
      clearSlot(gSlots[batchIdx][i])
      gSlotIsFinal[batchIdx][i] = false
      gSlotIsError[batchIdx][i] = false

    acquire(gMu)
    inc gWrittenPages, count
    inc gOkCount, localOk
    inc gErrCount, localErr
    if gMeta[batchIdx].owner == OwnWriter:
      gMeta[batchIdx].readyForMain = true
    broadcast(gCv)
    release(gMu)

proc anyOwnedBy(owner: Owner): bool =
  for i in 0 ..< BatchCount:
    if gMeta[i].owner == owner:
      return true
  false

proc allBatchesReusable(): bool =
  for i in 0 ..< BatchCount:
    if gMeta[i].owner != OwnMain or gMeta[i].phase != PhaseEmpty or gMeta[i].readyForMain:
      return false
  true

proc findMainBatch(phase: Phase; startSeq = -1): int =
  var bestStart = high(int)
  var found = -1
  for i in 0 ..< BatchCount:
    if gMeta[i].owner == OwnMain and gMeta[i].phase == phase and not gMeta[i].readyForMain:
      if startSeq >= 0:
        if gMeta[i].startSeq == startSeq:
          return i
      elif gMeta[i].startSeq < bestStart:
        bestStart = gMeta[i].startSeq
        found = i
  found

proc recycleBatch(idx: int) =
  gMeta[idx].owner = OwnMain
  gMeta[idx].phase = PhaseEmpty
  gMeta[idx].readyForMain = false
  gMeta[idx].startSeq = 0
  gMeta[idx].count = 0
  inc gMeta[idx].generation

proc transferWorkerReadyBatches(): bool =
  result = false
  for idx in 0 ..< BatchCount:
    if not gMeta[idx].readyForMain:
      continue

    case gMeta[idx].owner
    of OwnRenderer:
      gMeta[idx].owner = OwnMain
      gMeta[idx].phase = PhaseRendered
      gMeta[idx].readyForMain = false
      result = true
    of OwnNetwork:
      gMeta[idx].owner = OwnMain
      gMeta[idx].phase = PhaseNetworked
      gMeta[idx].readyForMain = false
      result = true
    of OwnWriter:
      recycleBatch(idx)
      result = true
    of OwnMain:
      gMeta[idx].readyForMain = false
      result = true

proc assignWorkIfPossible(): bool =
  result = false

  if not anyOwnedBy(OwnWriter):
    let nextWriterBatch = findMainBatch(PhaseNetworked, gNextBatchToWrite)
    if nextWriterBatch >= 0:
      gMeta[nextWriterBatch].owner = OwnWriter
      gMeta[nextWriterBatch].readyForMain = false
      inc gNextBatchToWrite, gMeta[nextWriterBatch].count
      result = true

  if not anyOwnedBy(OwnNetwork):
    let nextNetworkBatch = findMainBatch(PhaseRendered)
    if nextNetworkBatch >= 0:
      gMeta[nextNetworkBatch].owner = OwnNetwork
      gMeta[nextNetworkBatch].readyForMain = false
      result = true

  if not anyOwnedBy(OwnRenderer) and gNextSeqToRender < gTotalPages:
    let emptyBatch = findMainBatch(PhaseEmpty)
    if emptyBatch >= 0:
      let remaining = gTotalPages - gNextSeqToRender
      let count = min(BatchSize, remaining)
      gMeta[emptyBatch].owner = OwnRenderer
      gMeta[emptyBatch].phase = PhaseEmpty
      gMeta[emptyBatch].startSeq = gNextSeqToRender
      gMeta[emptyBatch].count = count
      gMeta[emptyBatch].readyForMain = false
      inc gNextSeqToRender, count
      result = true

proc freeAllSlots() =
  for b in 0 ..< BatchCount:
    for i in 0 ..< BatchSize:
      clearSlot(gSlots[b][i])
      gSlotIsFinal[b][i] = false
      gSlotIsError[b][i] = false

proc freeSelectedPages() =
  if gSelectedPages != nil:
    deallocShared(gSelectedPages)
  gSelectedPages = nil

proc initState(runtimeConfig: RuntimeConfig) =
  freeSelectedPages()
  let selectedCount = runtimeConfig.selectedPages.len
  if selectedCount > 0:
    let bytes = selectedCount * sizeof(int)
    gSelectedPages = cast[ptr UncheckedArray[int]](allocShared(bytes))
    if gSelectedPages == nil:
      raise newException(OutOfMemDefect, "allocShared failed for selected pages")
    copyMem(gSelectedPages, unsafeAddr runtimeConfig.selectedPages[0], bytes)
  else:
    gSelectedPages = nil
  gTotalPages = runtimeConfig.selectedCount
  gNextSeqToRender = 0
  gNextBatchToWrite = 0
  gFatal = false
  gStop = false
  gExitCode = ExitAllOk
  gWrittenPages = 0
  gOkCount = 0
  gErrCount = 0

  for i in 0 ..< BatchCount:
    gMeta[i] = BatchMeta(
      owner: OwnMain,
      phase: PhaseEmpty,
      startSeq: 0,
      count: 0,
      generation: 0'u64,
      readyForMain: false
    )

  freeAllSlots()

proc runGlobal3BatchEngine*(runtimeConfig: RuntimeConfig): int =
  initLock(gMu)
  initCond(gCv)

  var
    rendererThread: Thread[RendererThreadCtx]
    networkThread: Thread[NetworkThreadCtx]
    writerThread: Thread[WriterThreadCtx]
    rendererStarted = false
    networkStarted = false
    writerStarted = false
    joinedThreads = false

  try:
    initState(runtimeConfig)

    createThread(rendererThread, rendererThreadMain, RendererThreadCtx(pdfPath: runtimeConfig.inputPath))
    rendererStarted = true
    createThread(networkThread, networkThreadMain, NetworkThreadCtx(apiKey: runtimeConfig.apiKey))
    networkStarted = true
    createThread(writerThread, writerThreadMain, WriterThreadCtx())
    writerStarted = true

    acquire(gMu)
    while true:
      var changed = false

      if transferWorkerReadyBatches():
        changed = true

      if not gStop and assignWorkIfPossible():
        changed = true

      if gFatal:
        gStop = true
        broadcast(gCv)
        break

      if gWrittenPages >= gTotalPages and allBatchesReusable():
        gStop = true
        broadcast(gCv)
        break

      if changed:
        broadcast(gCv)
      else:
        wait(gCv, gMu)
    release(gMu)

    if rendererStarted:
      joinThread(rendererThread)
    if networkStarted:
      joinThread(networkThread)
    if writerStarted:
      joinThread(writerThread)
    joinedThreads = true

    if gFatal:
      result = max(gExitCode, ExitFatalRuntime)
    elif gErrCount > 0:
      result = ExitHasPageErrors
    else:
      result = ExitAllOk
  except CatchableError:
    result = ExitFatalRuntime
  finally:
    if not joinedThreads and (rendererStarted or networkStarted or writerStarted):
      acquire(gMu)
      gStop = true
      broadcast(gCv)
      release(gMu)
      if rendererStarted:
        joinThread(rendererThread)
      if networkStarted:
        joinThread(networkThread)
      if writerStarted:
        joinThread(writerThread)
    acquire(gMu)
    freeAllSlots()
    freeSelectedPages()
    release(gMu)
    deinitCond(gCv)
    deinitLock(gMu)
