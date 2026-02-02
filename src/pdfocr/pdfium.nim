# Ergonomic PDFium helpers built on top of the raw bindings.

import std/strformat
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

proc lastErrorCode*(): culong =
  FPDF_GetLastError()

proc raisePdfiumError*(context: string) =
  let code = lastErrorCode()
  var detail = "unknown"
  case code
  of 1: detail = "file not found or could not be opened"
  of 2: detail = "file format error"
  of 3: detail = "password error"
  of 4: detail = "security error"
  of 5: detail = "page not found or content error"
  else: discard
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
  let passPtr = if password.len == 0: nil else: password.cstring
  result.raw = FPDF_LoadDocument(path.cstring, passPtr)
  if pointer(result.raw) == nil:
    raisePdfiumError("FPDF_LoadDocument failed")

proc close*(doc: var PdfDocument) =
  if pointer(doc.raw) != nil:
    FPDF_CloseDocument(doc.raw)
    doc.raw = cast[FPDF_DOCUMENT](nil)

proc pageCount*(doc: PdfDocument): int =
  int(FPDF_GetPageCount(doc.raw))

proc loadPage*(doc: PdfDocument; index: int): PdfPage =
  result.raw = FPDF_LoadPage(doc.raw, index.cint)
  if pointer(result.raw) == nil:
    raisePdfiumError("FPDF_LoadPage failed")

proc close*(page: var PdfPage) =
  if pointer(page.raw) != nil:
    FPDF_ClosePage(page.raw)
    page.raw = cast[FPDF_PAGE](nil)

proc pageSize*(page: PdfPage): tuple[width, height: float] =
  (float(FPDF_GetPageWidth(page.raw)), float(FPDF_GetPageHeight(page.raw)))

proc createBitmap*(width, height: int; alpha: bool = false): PdfBitmap =
  result.raw = FPDFBitmap_Create(width.cint, height.cint, if alpha: 1 else: 0)
  result.width = width
  result.height = height
  if pointer(result.raw) == nil:
    raise newException(IOError, "FPDFBitmap_Create failed")

proc destroy*(bitmap: var PdfBitmap) =
  if pointer(bitmap.raw) != nil:
    FPDFBitmap_Destroy(bitmap.raw)
    bitmap.raw = cast[FPDF_BITMAP](nil)
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

proc buffer*(bitmap: PdfBitmap): pointer =
  FPDFBitmap_GetBuffer(bitmap.raw)

proc stride*(bitmap: PdfBitmap): int =
  int(FPDFBitmap_GetStride(bitmap.raw))
