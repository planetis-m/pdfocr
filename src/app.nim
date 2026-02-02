import pdfocr/[jpeglib, pdfium, layout]

# --- Main ---
proc main() =
  let inputFile = "input.pdf"
  let outputFile = "final_output.jpg"
  let dpiScale = 2.0 

  initPdfium()

  var doc: PdfDocument
  var page: PdfPage
  var bitmap: PdfBitmap

  try:
    doc = loadDocument(inputFile)
    page = loadPage(doc, 0)
    let (pageWidth, pageHeight) = pageSize(page)

    let width = int(pageWidth * dpiScale)
    let height = int(pageHeight * dpiScale)

    echo "Rendering ", width, "x", height

    bitmap = createBitmap(width, height, alpha = false)
    fillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF'u32)
    renderPage(bitmap, page, 0, 0, width, height)

    var comp = initJpegCompressorBgrx(outputFile, width, height, quality = 95)
    try:
      writeBgrx(comp, buffer(bitmap), stride(bitmap))
    finally:
      finish(comp)

    echo "Saved to ", outputFile

    # 2. Extract Text via layout analysis (very-loose-both params)
    let params = newLAParams(
      lineOverlap = 0.35,
      charMargin = 4.0,
      lineMargin = 1.1,
      wordMargin = 0.3
    )
    let layoutPage = buildTextPageLayout(page, params)
    var layoutText = ""
    for box in layoutPage.textboxes:
      layoutText.add(box.text)
    echo "\n--- Layout Text ---"
    echo layoutText
    echo "-------------------"

  finally:
    destroy(bitmap)
    close(page)
    close(doc)
    destroyPdfium()

main()
