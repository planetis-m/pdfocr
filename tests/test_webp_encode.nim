import std/[os, strformat]
import pdfocr/bindings/pdfium
import pdfocr/webp

proc failWithPdfiumError(context: string): void =
  let err = FPDF_GetLastError()
  if err == 0:
    raise newException(IOError, &"{context}: unknown error")
  raise newException(IOError, &"{context}: code {err}")

proc renderFirstPageAsWebp(pdfPath: string; outputPath: string) =
  var doc = FPDF_DOCUMENT(nil)
  var page = FPDF_PAGE(nil)
  var bitmap = FPDF_BITMAP(nil)
  try:
    doc = FPDF_LoadDocument(pdfPath, nil)
    if doc.pointer == nil:
      failWithPdfiumError("FPDF_LoadDocument failed")

    let pageCount = FPDF_GetPageCount(doc)
    doAssert pageCount > 0

    page = FPDF_LoadPage(doc, 0)
    if page.pointer == nil:
      failWithPdfiumError("FPDF_LoadPage failed")

    let pageWidth = FPDF_GetPageWidth(page)
    let pageHeight = FPDF_GetPageHeight(page)
    doAssert pageWidth > 0
    doAssert pageHeight > 0

    let renderWidth = 800
    let renderHeight = int(800.0 * (pageHeight / pageWidth))
    bitmap = FPDFBitmap_Create(renderWidth.cint, renderHeight.cint, 0)
    if bitmap.pointer == nil:
      raise newException(IOError, "FPDFBitmap_Create failed")

    let whiteColor = 0xFFFFFFFF'u64.culong
    FPDFBitmap_FillRect(bitmap, 0, 0, renderWidth.cint, renderHeight.cint, whiteColor)

    FPDF_RenderPageBitmap(
      bitmap, page,
      0, 0,
      renderWidth.cint, renderHeight.cint,
      0,
      0
    )

    let buffer = FPDFBitmap_GetBuffer(bitmap)
    doAssert buffer != nil
    let stride = FPDFBitmap_GetStride(bitmap)
    doAssert stride > 0

    let bytes = encodeBgrWithConfig(renderWidth, renderHeight, buffer, stride, quality = 80.0'f32)
    doAssert bytes.len > 0

    var f = open(outputPath, fmWrite)
    defer: f.close()
    discard f.writeBuffer(addr bytes[0], bytes.len)
  finally:
    if bitmap.pointer != nil:
      FPDFBitmap_Destroy(bitmap)
    if page.pointer != nil:
      FPDF_ClosePage(page)
    if doc.pointer != nil:
      FPDF_CloseDocument(doc)

proc testWebpEncode(pdfPath: string) =
  doAssert fileExists(pdfPath), &"Missing PDF file: {pdfPath}"

  var config = FPDF_LIBRARY_CONFIG(
    version: 2,
    m_pUserFontPaths: nil,
    m_pIsolate: nil,
    m_v8EmbedderSlot: 0,
    m_pPlatform: nil
  )
  FPDF_InitLibraryWithConfig(addr config)
  try:
    renderFirstPageAsWebp(pdfPath, "test_output.webp")
  finally:
    FPDF_DestroyLibrary()

when isMainModule:
  if paramCount() < 1:
    echo "Usage: ./test_webp_encode <path_to_pdf_file>"
    quit(1)

  testWebpEncode(paramStr(1))
