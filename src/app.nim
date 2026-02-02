import pdfocr/[jpeglib, pdfium]

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

    # 2. Extract Text
    echo "\n--- Extracted Text ---"
    echo extractText(page)
    echo "----------------------"

  finally:
    destroy(bitmap)
    close(page)
    close(doc)
    destroyPdfium()

main()
