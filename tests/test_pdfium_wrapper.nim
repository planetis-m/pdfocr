import std/[os, strformat]
import pdfocr/pdfium

proc main() =
  let pdfPath =
    if paramCount() >= 1:
      paramStr(1)
    else:
      "tests/input.pdf"

  if not fileExists(pdfPath):
    echo &"Missing PDF file: {pdfPath}"
    quit(1)

  initPdfium()
  var doc: PdfDocument
  var page: PdfPage
  var bitmap: PdfBitmap

  try:
    doc = loadDocument(pdfPath)
    let count = pageCount(doc)
    doAssert count > 0

    page = loadPage(doc, 0)
    let (w, h) = pageSize(page)
    doAssert w > 0 and h > 0

    let renderWidth = 200
    let renderHeight = int(float(renderWidth) * (h / w))
    bitmap = createBitmap(renderWidth, renderHeight, alpha = false)
    fillRect(bitmap, 0, 0, renderWidth, renderHeight, 0xFFFFFFFF'u32)
    renderPage(bitmap, page, 0, 0, renderWidth, renderHeight)

    doAssert buffer(bitmap) != nil
    doAssert stride(bitmap) > 0
  finally:
    destroy(bitmap)
    close(page)
    close(doc)
    destroyPdfium()

when isMainModule:
  main()
