import pdfocr/pdfium
import pdfocr/jpeglib
import pdfocr/layout
import std/strutils

proc clamp(val, minv, maxv: int): int =
  if val < minv: return minv
  if val > maxv: return maxv
  val

proc drawRectBgrx(buf: pointer; stride, width, height: int;
                  x0, y0, x1, y1: int; color: uint32) =
  let minX = clamp(min(x0, x1), 0, width - 1)
  let maxX = clamp(max(x0, x1), 0, width - 1)
  let minY = clamp(min(y0, y1), 0, height - 1)
  let maxY = clamp(max(y0, y1), 0, height - 1)
  let base = cast[ptr UncheckedArray[uint32]](buf)

  # top
  for x in minX .. maxX:
    base[(minY * stride + x * 4) div 4] = color
  # bottom
  for x in minX .. maxX:
    base[(maxY * stride + x * 4) div 4] = color
  # left/right
  for y in minY .. maxY:
    base[(y * stride + minX * 4) div 4] = color
    base[(y * stride + maxX * 4) div 4] = color

proc collectTextBoxes(items: seq[LTItem]; boxes: var seq[LTTextBox]) =
  for item in items:
    if item of LTTextBox:
      boxes.add(LTTextBox(item))

proc main() =
  let inputFile = "tests/input.pdf"
  let outputFile = "tests/test_output_text_boxes.jpg"
  let dpiScale = 2.0

  initPdfium()

  var doc: PdfDocument
  var page: PdfPage
  var bitmap: PdfBitmap
  var textPage: PdfTextPage

  try:
    doc = loadDocument(inputFile)
    page = loadPage(doc, 0)
    textPage = loadTextPage(page)
    let (pageWidth, pageHeight) = pageSize(page)
    let width = int(pageWidth * dpiScale)
    let height = int(pageHeight * dpiScale)

    bitmap = createBitmap(width, height, alpha = false)
    fillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF'u32)
    renderPage(bitmap, page, 0, 0, width, height)

    var zeroBoxes = 0
    var minW = 1.0e9
    var minH = 1.0e9
    var maxW = 0.0
    var maxH = 0.0
    var minY = 1.0e9
    var maxY = -1.0e9
    let totalChars = charCount(textPage)
    for i in 0 ..< totalChars:
      let (l, r, b, t) = getCharBox(textPage, i)
      let w = r - l
      let h = t - b
      if w == 0 or h == 0:
        inc(zeroBoxes)
      if w > 0: minW = min(minW, w)
      if h > 0: minH = min(minH, h)
      maxW = max(maxW, w)
      maxH = max(maxH, h)
      minY = min(minY, b)
      maxY = max(maxY, t)
    echo "Char boxes: count=", totalChars, " zero=", zeroBoxes, " minW=", minW, " minH=", minH, " maxW=", maxW, " maxH=", maxH, " minY=", minY, " maxY=", maxY

    let layout = buildTextPageLayout(page, newLAParams(wordMargin = 0.3, boxesFlowEnabled = false))
    var boxes: seq[LTTextBox] = @[]
    collectTextBoxes(layout.items, boxes)
    if boxes.len == 0:
      # fallback: draw full-page box if no groups were produced
      boxes.add(newLTTextBoxHorizontal())
      boxes[^1].setBBox((0.0, 0.0, pageWidth, pageHeight))

    for box in boxes:
      let x0 = int(box.x0 * dpiScale)
      let x1 = int(box.x1 * dpiScale)
      let y0 = int((pageHeight - box.y1) * dpiScale)
      let y1 = int((pageHeight - box.y0) * dpiScale)
      drawRectBgrx(buffer(bitmap), stride(bitmap), width, height, x0, y0, x1, y1, 0xFF0000FF'u32)

    let rawText = extractText(page)
    var layoutText = ""
    for box in boxes:
      layoutText.add(box.getText())
    echo "--- Pdfium extractText ---"
    echo rawText
    echo "--- Layout text ---"
    echo layoutText
    if rawText.strip != layoutText.strip:
      echo "WARNING: extractText and layout text differ"

    var comp = initJpegCompressorBgrx(outputFile, width, height, quality = 90)
    try:
      writeBgrx(comp, buffer(bitmap), stride(bitmap))
    finally:
      finish(comp)

    echo "Wrote ", outputFile
  finally:
    destroy(bitmap)
    close(textPage)
    close(page)
    close(doc)
    destroyPdfium()

when isMainModule:
  main()
