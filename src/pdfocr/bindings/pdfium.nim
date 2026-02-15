# --- Type Definitions ---
type
  FpdfDocument* = distinct pointer
  FpdfPage* = distinct pointer
  FpdfBitmap* = distinct pointer
  FpdfTextPage* = distinct pointer
  FpdfPageObject* = distinct pointer

  # The config struct for Init
  FpdfLibraryConfig* {.bycopy.} = object
    version*: cint
    m_pUserFontPaths*: cstringArray
    m_pIsolate*: pointer
    m_v8EmbedderSlot*: cuint
    m_pPlatform*: pointer

const
  FpdfPageObjectText* = 1
  FpdfBitmapBgr* = 2

# --- 3. Function Imports (The Bindings) ---

{.push importc, callconv: cdecl.}

# Core Library Handling
proc FPDF_InitLibraryWithConfig*(config: ptr FpdfLibraryConfig)
proc FPDF_DestroyLibrary*()
proc FPDF_GetLastError*(): culong

# Document Handling
proc FPDF_LoadDocument*(file_path: cstring, password: cstring): FpdfDocument
proc FPDF_CloseDocument*(document: FpdfDocument)
proc FPDF_GetPageCount*(document: FpdfDocument): cint

# Page Handling
proc FPDF_LoadPage*(document: FpdfDocument, page_index: cint): FpdfPage
proc FPDF_ClosePage*(page: FpdfPage)
proc FPDF_GetPageWidth*(page: FpdfPage): cdouble
proc FPDF_GetPageHeight*(page: FpdfPage): cdouble

# Bitmap & Rendering
# width, height, alpha (0 or 1)
proc FPDFBitmap_Create*(width, height, alpha: cint): FpdfBitmap
proc FPDFBitmap_CreateEx*(width, height, format: cint, first_scan: pointer, stride: cint): FpdfBitmap
proc FPDFBitmap_Destroy*(bitmap: FpdfBitmap)
# color is 32-bit integer (0xAARRGGBB)
proc FPDFBitmap_FillRect*(bitmap: FpdfBitmap, left, top, width, height: cint, color: culong)
proc FPDFBitmap_GetBuffer*(bitmap: FpdfBitmap): pointer
proc FPDFBitmap_GetStride*(bitmap: FpdfBitmap): cint

# The main render function
# flags: 0 for normal, 0x01 for annotations, 0x10 for LCD text
proc FPDF_RenderPageBitmap*(bitmap: FpdfBitmap, page: FpdfPage,
                            start_x, start_y, size_x, size_y: cint,
                            rotate, flags: cint)

# Text Extraction
proc FPDFText_LoadPage*(page: FpdfPage): FpdfTextPage
proc FPDFText_ClosePage*(text_page: FpdfTextPage)
proc FPDFText_CountChars*(text_page: FpdfTextPage): cint
proc FPDFText_GetText*(text_page: FpdfTextPage, start_index, count: cint, buffer: pointer): cint
# Get the bounding box of a specific character index
proc FPDFText_GetCharBox*(text_page: FpdfTextPage, index: cint,
                          left, right, bottom, top: ptr cdouble): cint

{.pop.}
