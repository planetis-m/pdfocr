import std/[os, strformat]
import pdfocr/pdfium

proc main() =
  let pdfPath = "input.pdf"

  if not fileExists(pdfPath):
    quit(&"Missing PDF file: {pdfPath}")

  initPdfium()
  try:
    var doc = loadDocument(pdfPath)
    let count = pageCount(doc)
    doAssert count > 0

    var page = loadPage(doc, 0)
    let (w, h) = pageSize(page)
    doAssert w > 0 and h > 0

    let renderWidth = 200
    let renderHeight = int(float(renderWidth) * (h / w))
    var bitmap = createBitmap(renderWidth, renderHeight, alpha = false)
    fillRect(bitmap, 0, 0, renderWidth, renderHeight, 0xFFFFFFFF'u32)
    renderPage(bitmap, page, 0, 0, renderWidth, renderHeight)

    doAssert buffer(bitmap) != nil
    doAssert stride(bitmap) > 0
  finally:
    destroyPdfium()

when isMainModule:
  main()
