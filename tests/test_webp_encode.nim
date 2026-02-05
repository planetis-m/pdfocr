import std/[os, strformat]
import pdfocr/pdfium
import pdfocr/webp

proc renderFirstPageAsWebp(pdfPath: string; outputPath: string) =
  var doc = loadDocument(pdfPath)
  let count = pageCount(doc)
  doAssert count > 0

  var page = loadPage(doc, 0)
  let (pageWidth, pageHeight) = pageSize(page)
  doAssert pageWidth > 0
  doAssert pageHeight > 0

  let renderWidth = 800
  let renderHeight = int(800.0 * (pageHeight / pageWidth))
  var bitmap = createBitmap(renderWidth, renderHeight)
  fillRect(bitmap, 0, 0, renderWidth, renderHeight, 0xFFFFFFFF'u32)
  renderPage(bitmap, page, 0, 0, renderWidth, renderHeight)

  let buf = buffer(bitmap)
  doAssert buf != nil
  let rowStride = stride(bitmap)
  doAssert rowStride > 0

  let bytes = compressBgr(renderWidth, renderHeight, buf, rowStride, 80)
  doAssert bytes.len > 0

  var f = open(outputPath, fmWrite)
  defer: f.close()
  discard f.writeBuffer(addr bytes[0], bytes.len)

proc testWebpEncode(pdfPath: string) =
  doAssert fileExists(pdfPath), &"Missing PDF file: {pdfPath}"

  initPdfium()
  try:
    renderFirstPageAsWebp(pdfPath, "test_output.webp")
  finally:
    destroyPdfium()

when isMainModule:
  if paramCount() < 1:
    quit("Usage: ./test_webp_encode <path_to_pdf_file>")
  testWebpEncode(paramStr(1))
