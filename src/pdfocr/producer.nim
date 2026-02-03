import std/[os, strformat, times, monotimes]
import threading/channels
import ./[config, logging, types, pdfium, jpeglib]

type
  ProducerContext* = object
    pdfPath*: string
    pageStart*: int
    pageEnd*: int
    outputDir*: string
    config*: Config
    inputChan*: Chan[InputMessage]
    outputChan*: Chan[OutputMessage]

proc runProducer*(ctx: ProducerContext) {.thread.} =
  logInfo("Producer thread started.")
  var doc: PdfDocument
  try:
    doc = loadDocument(ctx.pdfPath)
  except CatchableError as err:
    logError("Failed to load PDF: " & err.msg)
    ctx.inputChan.send(InputMessage(kind: imInputDone))
    return

  defer:
    close(doc)

  let scale =
    if ctx.config.renderScale > 0: ctx.config.renderScale
    else: float(ctx.config.renderDpi) / 72.0

  var batch = newSeq[Task](0)

  for index in ctx.pageStart..ctx.pageEnd:
    let pageId = index - ctx.pageStart
    let pageNumberUser = index + 1
    let startedAt = getMonoTime()
    var page: PdfPage
    var bitmap: PdfBitmap
    var tempPath = ""
    var stage = "render"
    try:
      page = loadPage(doc, index)
      bitmap = renderPageAtScale(page, scale, alpha = false)

      stage = "encode"
      let pid = getCurrentProcessId()
      let stamp = getTime().toUnix()
      tempPath = getTempDir().joinPath(&"pdfocr_{pid}_{pageNumberUser}_{stamp}.jpg")

      var comp = initJpegCompressorBgrx(tempPath, bitmap.width, bitmap.height, ctx.config.jpegQuality)
      try:
        writeBgrx(comp, buffer(bitmap), stride(bitmap))
      finally:
        finish(comp)

      let jpegData = readFile(tempPath)
      var jpegBytes = newSeq[byte](jpegData.len)
      if jpegData.len > 0:
        copyMem(addr jpegBytes[0], unsafeAddr jpegData[0], jpegData.len)
      removeFile(tempPath)
      tempPath = ""

      batch.add(Task(
        pageId: pageId,
        pageNumberUser: pageNumberUser,
        attempt: 0,
        jpegBytes: jpegBytes,
        createdAt: getMonoTime()
      ))
      if batch.len >= ctx.config.producerBatch:
        ctx.inputChan.send(InputMessage(kind: imTaskBatch, tasks: batch))
        batch = @[]
    except CatchableError as err:
      let finishedAt = getMonoTime()
      let errorKind = if stage == "encode": ekEncodeError else: ekPdfError
      ctx.outputChan.send(OutputMessage(
        kind: omPageResult,
        result: Result(
          pageId: pageId,
          pageNumberUser: pageNumberUser,
          status: rsFailure,
          text: "",
          errorKind: errorKind,
          errorMessage: err.msg,
          httpStatus: 0,
          attemptCount: 0,
          startedAt: startedAt,
          finishedAt: finishedAt
        )
      ))
      logError(&"Failed page {pageNumberUser}: {err.msg}")
    finally:
      if tempPath.len > 0 and fileExists(tempPath):
        removeFile(tempPath)
      destroy(bitmap)
      close(page)

  if batch.len > 0:
    ctx.inputChan.send(InputMessage(kind: imTaskBatch, tasks: batch))

  ctx.inputChan.send(InputMessage(kind: imInputDone))
