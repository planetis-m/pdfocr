import pdfocr/pdfium
import pdfocr/jpeglib
import pdfocr/layout

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

type
  ParamSet = object
    name: string
    lineOverlap: float
    charMargin: float
    lineMargin: float
    wordMargin: float
    detectVertical: bool

proc renderWithParams(page: PdfPage; pageWidth, pageHeight: float; dpiScale: float;
                      params: ParamSet; outputFile: string) =
  let width = int(pageWidth * dpiScale)
  let height = int(pageHeight * dpiScale)

  var bitmap = createBitmap(width, height, alpha = false)
  try:
    fillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF'u32)
    renderPage(bitmap, page, 0, 0, width, height)

    let layout = buildTextPageLayout(
      page,
      newLAParams(
        lineOverlap = params.lineOverlap,
        charMargin = params.charMargin,
        lineMargin = params.lineMargin,
        wordMargin = params.wordMargin,
        detectVertical = params.detectVertical
      )
    )
    var boxes = layout.textboxes
    if boxes.len == 0:
      boxes.add(LTTextBox(bbox: (0.0, 0.0, pageWidth, pageHeight), text: ""))

    for box in boxes:
      let x0 = int(box.bbox.x0 * dpiScale)
      let x1 = int(box.bbox.x1 * dpiScale)
      let y0 = int((pageHeight - box.bbox.y1) * dpiScale)
      let y1 = int((pageHeight - box.bbox.y0) * dpiScale)
      drawRectBgrx(buffer(bitmap), stride(bitmap), width, height, x0, y0, x1, y1, 0xFF0000FF'u32)

    var comp = initJpegCompressorBgrx(outputFile, width, height, quality = 90)
    try:
      writeBgrx(comp, buffer(bitmap), stride(bitmap))
    finally:
      finish(comp)
  finally:
    destroy(bitmap)

proc main() =
  let inputFile = "tests/input.pdf"
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

    let variants = @[
      ParamSet(name: "base", lineOverlap: 0.5, charMargin: 2.0, lineMargin: 0.5, wordMargin: 0.3, detectVertical: false),
      ParamSet(name: "loose-both", lineOverlap: 0.4, charMargin: 3.0, lineMargin: 0.8, wordMargin: 0.3, detectVertical: false),
      ParamSet(name: "very-loose-line", lineOverlap: 0.35, charMargin: 2.0, lineMargin: 1.1, wordMargin: 0.3, detectVertical: false),
      ParamSet(name: "very-loose-both", lineOverlap: 0.35, charMargin: 4.0, lineMargin: 1.1, wordMargin: 0.3, detectVertical: false),
      ParamSet(name: "ultra-loose-both", lineOverlap: 0.25, charMargin: 6.0, lineMargin: 1.6, wordMargin: 0.3, detectVertical: false),
      ParamSet(name: "base-vertical", lineOverlap: 0.5, charMargin: 2.0, lineMargin: 0.5, wordMargin: 0.3, detectVertical: true)
    ]

    for v in variants:
      let outputFile = "tests/test_output_text_boxes_" & v.name & ".jpg"
      renderWithParams(page, pageWidth, pageHeight, dpiScale, v, outputFile)
      echo "Wrote ", outputFile
  finally:
    destroy(bitmap)
    close(textPage)
    close(page)
    close(doc)
    destroyPdfium()

when isMainModule:
  main()
