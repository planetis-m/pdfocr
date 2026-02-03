# Ergonomic PDFium helpers built on top of the raw bindings.

import std/[strformat, widestrs]
import ./bindings/pdfium

type
  PdfDocument* = object
    raw*: FPDF_DOCUMENT

  PdfPage* = object
    raw*: FPDF_PAGE

  PdfBitmap* = object
    raw*: FPDF_BITMAP
    width*: int
    height*: int

  PdfTextPage* = object
    raw*: FPDF_TEXTPAGE

proc lastErrorCode*(): culong =
  FPDF_GetLastError()

proc raisePdfiumError*(context: string) {.noinline.} =
  let code = lastErrorCode()
  let detail =
    case code
    of 0: "no error"
    of 1: "unknown error"
    of 2: "file not found or could not be opened"
    of 3: "file not in PDF format or corrupted"
    of 4: "password required or incorrect password"
    of 5: "unsupported security scheme"
    of 6: "page not found or content error"
    of 1001: "operation blocked by license restrictions"
    else: "unknown"
  raise newException(IOError, &"{context}: {detail} (code {code})")

proc initPdfium*() =
  var config = FPDF_LIBRARY_CONFIG(
    version: 2,
    m_pUserFontPaths: nil,
    m_pIsolate: nil,
    m_v8EmbedderSlot: 0,
    m_pPlatform: nil
  )
  FPDF_InitLibraryWithConfig(addr config)

proc destroyPdfium*() =
  FPDF_DestroyLibrary()

proc loadDocument*(path: string; password: string = ""): PdfDocument =
  result.raw = FPDF_LoadDocument(path.cstring, cstring(password))
  if pointer(result.raw) == nil:
    raisePdfiumError("FPDF_LoadDocument failed")

proc close*(doc: var PdfDocument) =
  if pointer(doc.raw) != nil:
    FPDF_CloseDocument(doc.raw)
    doc.raw = FPDF_DOCUMENT(nil)

proc pageCount*(doc: PdfDocument): int =
  int(FPDF_GetPageCount(doc.raw))

proc loadPage*(doc: PdfDocument; index: int): PdfPage =
  result.raw = FPDF_LoadPage(doc.raw, index.cint)
  if pointer(result.raw) == nil:
    raisePdfiumError("FPDF_LoadPage failed")

proc loadTextPage*(page: PdfPage): PdfTextPage =
  result.raw = FPDFText_LoadPage(page.raw)
  if pointer(result.raw) == nil:
    raisePdfiumError("FPDFText_LoadPage failed")

proc close*(page: var PdfPage) =
  if pointer(page.raw) != nil:
    FPDF_ClosePage(page.raw)
    page.raw = FPDF_PAGE(nil)

proc close*(textPage: var PdfTextPage) =
  if pointer(textPage.raw) != nil:
    FPDFText_ClosePage(textPage.raw)
    textPage.raw = FPDF_TEXTPAGE(nil)

proc pageSize*(page: PdfPage): tuple[width, height: float] =
  (float(FPDF_GetPageWidth(page.raw)), float(FPDF_GetPageHeight(page.raw)))

proc createBitmap*(width, height: int; alpha: bool = false): PdfBitmap =
  result.raw = FPDFBitmap_Create(width.cint, height.cint, alpha.cint)
  result.width = width
  result.height = height
  if pointer(result.raw) == nil:
    raise newException(IOError, "FPDFBitmap_Create failed")

proc destroy*(bitmap: var PdfBitmap) =
  if pointer(bitmap.raw) != nil:
    FPDFBitmap_Destroy(bitmap.raw)
    bitmap.raw = FPDF_BITMAP(nil)
    bitmap.width = 0
    bitmap.height = 0

proc fillRect*(bitmap: PdfBitmap; left, top, width, height: int; color: uint32) =
  FPDFBitmap_FillRect(bitmap.raw, left.cint, top.cint, width.cint, height.cint, color.culong)

proc renderPage*(bitmap: PdfBitmap; page: PdfPage; startX, startY, sizeX, sizeY: int;
                 rotate: int = 0; flags: int = 0) =
  FPDF_RenderPageBitmap(
    bitmap.raw, page.raw,
    startX.cint, startY.cint,
    sizeX.cint, sizeY.cint,
    rotate.cint, flags.cint
  )

proc renderPageAtScale*(page: PdfPage; scale: float; alpha: bool = false; rotate: int = 0; flags: int = 0): PdfBitmap =
  let (pageWidth, pageHeight) = pageSize(page)
  let width = int(pageWidth * scale)
  let height = int(pageHeight * scale)
  result = createBitmap(width, height, alpha)
  fillRect(result, 0, 0, width, height, 0xFFFFFFFF'u32)
  renderPage(result, page, 0, 0, width, height, rotate, flags)

proc buffer*(bitmap: PdfBitmap): pointer =
  FPDFBitmap_GetBuffer(bitmap.raw)

proc stride*(bitmap: PdfBitmap): int =
  int(FPDFBitmap_GetStride(bitmap.raw))

proc extractText*(page: PdfPage): string =
  var textPage = loadTextPage(page)
  try:
    let count = FPDFText_CountChars(textPage.raw)
    if count <= 0:
      return ""

    # Pdfium expects buffer size including the null terminator.
    var wStr = newWideCString(count)
    discard FPDFText_GetText(textPage.raw, 0, count.cint, cast[ptr uint16](toWideCString(wStr)))
    result = $wStr
  finally:
    close(textPage)

proc charCount*(textPage: PdfTextPage): int =
  int(FPDFText_CountChars(textPage.raw))

proc getTextRange*(textPage: PdfTextPage; startIndex, count: int): string =
  if count <= 0:
    return ""
  # Pdfium expects buffer size including the null terminator.
  var wStr = newWideCString(count)
  discard FPDFText_GetText(textPage.raw, startIndex.cint, count.cint, cast[ptr uint16](toWideCString(wStr)))
  result = $wStr

proc getCharBox*(textPage: PdfTextPage; index: int): tuple[left, right, bottom, top: float] =
  var left, right, bottom, top: cdouble
  let ok = FPDFText_GetCharBox(textPage.raw, index.cint, addr left, addr right, addr bottom, addr top)
  if ok == 0:
    return (0.0, 0.0, 0.0, 0.0)
  (left.float, right.float, bottom.float, top.float)
