import std/strformat
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
  ctx.renderOutCh.send(RendererOutput(
    kind: rokRenderFailure,
    failure: RenderFailure(
      seqId: seqId,
      page: page,
      errorKind: kind,
      errorMessage: boundedErrorMessage(message),
      attempts: 1
    )
  ))

proc runRenderer*(ctx: RendererContext) {.thread.} =
  var doc: PdfDocument
  try:
    doc = loadDocument(ctx.pdfPath)
  except CatchableError as exc:
    ctx.sendFatal(PDF_ERROR, exc.msg)
    return

  while true:
    var req: RenderRequest
    ctx.renderReqCh.recv(req)
    if req.kind == rrkStop:
      break

    let seqId = req.seqId
    if seqId < 0 or seqId >= ctx.selectedPages.len:
      ctx.sendRenderFailure(seqId, 0, PDF_ERROR, &"invalid seq_id for renderer: {seqId}")
      continue

    let page = ctx.selectedPages[seqId]

    var bitmap: PdfBitmap
    try:
      var pdfPage = loadPage(doc, page - 1)
      bitmap = renderPageAtScale(
        pdfPage,
        RENDER_SCALE,
        rotate = RENDER_ROTATE,
        flags = RENDER_FLAGS
      )
    except CatchableError as exc:
      ctx.sendRenderFailure(seqId, page, PDF_ERROR, exc.msg)
      continue

    let bitmapWidth = width(bitmap)
    let bitmapHeight = height(bitmap)
    let pixels = buffer(bitmap)
    let rowStride = stride(bitmap)
    if bitmapWidth <= 0 or bitmapHeight <= 0 or pixels.isNil or rowStride <= 0:
      ctx.sendRenderFailure(
        seqId,
        page,
        PDF_ERROR,
        "invalid bitmap state from renderer"
      )
      continue

    let webpBytes =
      try:
        compressBgr(
          Positive(bitmapWidth),
          Positive(bitmapHeight),
          pixels,
          rowStride,
          WEBP_QUALITY
        )
      except CatchableError as exc:
        ctx.sendRenderFailure(seqId, page, ENCODE_ERROR, exc.msg)
        continue

    if webpBytes.len == 0:
      ctx.sendRenderFailure(seqId, page, ENCODE_ERROR, "encoded WebP output was empty")
      continue

    ctx.renderOutCh.send(RendererOutput(
      kind: rokRenderedTask,
      task: RenderedTask(
        seqId: seqId,
        page: page,
        webpBytes: webpBytes,
        attempt: 1
      )
    ))
