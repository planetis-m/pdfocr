import std/[atomics, os, strformat]
import threading/channels
import ./constants
import ./errors
import ./pdfium
import ./types
import ./webp

proc sendFatal(ctx: RendererContext; kind: ErrorKind; message: string) =
  ctx.fatalCh.send(FatalEvent(
    source: fesRenderer,
    errorKind: kind,
    message: boundedErrorMessage(message)
  ))

proc sendRenderFailure(ctx: RendererContext; seqId: SeqId; page: int; kind: ErrorKind; message: string) =
  let output = RendererOutput(
    kind: rokRenderFailure,
    failure: RenderFailure(
      seqId: seqId,
      page: page,
      errorKind: kind,
      errorMessage: boundedErrorMessage(message),
      attempts: 1
    )
  )
  while not ctx.renderOutCh.trySend(output):
    if SchedulerStopRequested.load(moRelaxed):
      return
    sleep(1)

proc runRenderer*(ctx: RendererContext) {.thread.} =
  var doc: PdfDocument
  try:
    doc = loadDocument(ctx.pdfPath)
  except CatchableError:
    ctx.sendFatal(PdfError, getCurrentExceptionMsg())
    return

  while true:
    if SchedulerStopRequested.load(moRelaxed):
      break
    var req: RenderRequest
    ctx.renderReqCh.recv(req)
    if req.kind == rrkStop:
      break

    let seqId = req.seqId
    if seqId < 0 or seqId >= ctx.selectedPages.len:
      ctx.sendRenderFailure(seqId, 0, PdfError, &"invalid seq_id for renderer: {seqId}")
      continue

    let page = ctx.selectedPages[seqId]

    var bitmap: PdfBitmap
    try:
      var pdfPage = loadPage(doc, page - 1)
      bitmap = renderPageAtScale(
        pdfPage,
        RenderScale,
        rotate = RenderRotate,
        flags = RenderFlags
      )
    except CatchableError:
      ctx.sendRenderFailure(seqId, page, PdfError, getCurrentExceptionMsg())
      continue

    let bitmapWidth = width(bitmap)
    let bitmapHeight = height(bitmap)
    let pixels = buffer(bitmap)
    let rowStride = stride(bitmap)
    if bitmapWidth <= 0 or bitmapHeight <= 0 or pixels.isNil or rowStride <= 0:
      ctx.sendRenderFailure(
        seqId,
        page,
        PdfError,
        "invalid bitmap state from renderer"
      )
      continue

    let webpBytes =
      try:
        when defined(testing):
          if getEnv("PDFOCR_TEST_FORCE_ENCODE_ERROR") == "1":
            raise newException(ValueError, "forced encode failure for tests")
        compressBgr(
          Positive(bitmapWidth),
          Positive(bitmapHeight),
          pixels,
          rowStride,
          WebpQuality
        )
      except CatchableError:
        ctx.sendRenderFailure(seqId, page, EncodeError, getCurrentExceptionMsg())
        continue

    if webpBytes.len == 0:
      ctx.sendRenderFailure(seqId, page, EncodeError, "encoded WebP output was empty")
      continue

    let output = RendererOutput(
      kind: rokRenderedTask,
      task: RenderedTask(
        seqId: seqId,
        page: page,
        webpBytes: webpBytes,
        attempt: 1
      )
    )
    while not ctx.renderOutCh.trySend(output):
      if SchedulerStopRequested.load(moRelaxed):
        return
      sleep(1)
