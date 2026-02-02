# --- Type Definitions ---
type
  FPDF_DOCUMENT* = distinct pointer
  FPDF_PAGE* = distinct pointer
  FPDF_BITMAP* = distinct pointer
  FPDF_TEXTPAGE* = distinct pointer
  FPDF_PAGEOBJECT* = distinct pointer

  # The config struct for Init
  FPDF_LIBRARY_CONFIG* {.bycopy.} = object
    version*: cint
    m_pUserFontPaths*: cstringArray
    m_pIsolate*: pointer
    m_v8EmbedderSlot*: cuint
    m_pPlatform*: pointer

const
  FPDF_PAGEOBJECT_TEXT* = 1

# --- 3. Function Imports (The Bindings) ---

# Core Library Handling
proc FPDF_InitLibraryWithConfig*(config: ptr FPDF_LIBRARY_CONFIG) {.importc, cdecl.}
proc FPDF_DestroyLibrary*() {.importc, cdecl.}
proc FPDF_GetLastError*(): culong {.importc, cdecl.}

# Document Handling
proc FPDF_LoadDocument*(file_path: cstring, password: cstring): FPDF_DOCUMENT {.importc, cdecl.}
proc FPDF_CloseDocument*(document: FPDF_DOCUMENT) {.importc, cdecl.}
proc FPDF_GetPageCount*(document: FPDF_DOCUMENT): cint {.importc, cdecl.}

# Page Handling
proc FPDF_LoadPage*(document: FPDF_DOCUMENT, page_index: cint): FPDF_PAGE {.importc, cdecl.}
proc FPDF_ClosePage*(page: FPDF_PAGE) {.importc, cdecl.}
proc FPDF_GetPageWidth*(page: FPDF_PAGE): cdouble {.importc, cdecl.}
proc FPDF_GetPageHeight*(page: FPDF_PAGE): cdouble {.importc, cdecl.}

# Bitmap & Rendering
# width, height, alpha (0 or 1)
proc FPDFBitmap_Create*(width, height, alpha: cint): FPDF_BITMAP {.importc, cdecl.}
proc FPDFBitmap_Destroy*(bitmap: FPDF_BITMAP) {.importc, cdecl.}
# color is 32-bit integer (0xAARRGGBB)
proc FPDFBitmap_FillRect*(bitmap: FPDF_BITMAP, left, top, width, height: cint, color: culong) {.importc, cdecl.}
proc FPDFBitmap_GetBuffer*(bitmap: FPDF_BITMAP): pointer {.importc, cdecl.}
proc FPDFBitmap_GetStride*(bitmap: FPDF_BITMAP): cint {.importc, cdecl.}

# The main render function
# flags: 0 for normal, 0x01 for annotations, 0x10 for LCD text
proc FPDF_RenderPageBitmap*(bitmap: FPDF_BITMAP, page: FPDF_PAGE, 
                            start_x, start_y, size_x, size_y: cint, 
                            rotate, flags: cint) {.importc, cdecl.}

# Text Extraction
proc FPDFText_LoadPage*(page: FPDF_PAGE): FPDF_TEXTPAGE {.importc, cdecl.}
proc FPDFText_ClosePage*(text_page: FPDF_TEXTPAGE) {.importc, cdecl.}
proc FPDFText_CountChars*(text_page: FPDF_TEXTPAGE): cint {.importc, cdecl.}
proc FPDFText_GetText*(text_page: FPDF_TEXTPAGE, start_index, count: cint, buffer: pointer): cint {.importc, cdecl.}
# Get the bounding box of a specific character index
proc FPDFText_GetCharBox*(text_page: FPDF_TEXTPAGE, index: cint, 
                          left, right, bottom, top: ptr cdouble): cint {.importc, cdecl.}

