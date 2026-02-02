import std/[os, strformat]
import pdfocr/wrappers/pdfium  # Import your pdfium bindings

# --- Helper Procedures ---

proc checkError(operation: string) =
  let err = FPDF_GetLastError()
  if err != 0:
    echo &"Error during {operation}: code {err}"
    case err
    of 1: echo "  - File not found or could not be opened"
    of 2: echo "  - File format error"
    of 3: echo "  - Password error"
    of 4: echo "  - Security error"
    of 5: echo "  - Page not found or content error"
    else: echo "  - Unknown error"

proc saveBitmapAsPPM(bitmap: FPDF_BITMAP, width, height: int, filename: string) =
  ## Save bitmap as PPM (simple image format for testing)
  let buffer = cast[ptr UncheckedArray[uint8]](FPDFBitmap_GetBuffer(bitmap))
  let stride = FPDFBitmap_GetStride(bitmap)
  
  var f = open(filename, fmWrite)
  defer: f.close()
  
  # PPM header
  f.writeLine("P6")
  f.writeLine(&"{width} {height}")
  f.writeLine("255")
  
  # Write pixel data (convert BGRA to RGB)
  for y in 0..<height:
    for x in 0..<width:
      let idx = y * stride + x * 4
      let b = buffer[idx]
      let g = buffer[idx + 1]
      let r = buffer[idx + 2]
      # Skip alpha (buffer[idx + 3])
      f.write(char(r))
      f.write(char(g))
      f.write(char(b))
  
  echo &"✓ Saved bitmap to {filename}"

# --- Main Test Procedure ---

proc testPDFiumBindings(pdfPath: string) =
  echo "=== Testing PDFium Bindings ==="
  echo ""
  
  # Test 1: Initialize Library
  echo "1. Initializing PDFium library..."
  var config = FPDF_LIBRARY_CONFIG(
    version: 2,
    m_pUserFontPaths: nil,
    m_pIsolate: nil,
    m_v8EmbedderSlot: 0,
    m_pPlatform: nil
  )
  FPDF_InitLibraryWithConfig(addr config)
  echo "✓ Library initialized"
  echo ""
  
  # Test 2: Load Document
  echo "2. Loading PDF document..."
  if not fileExists(pdfPath):
    echo &"✗ Error: File not found: {pdfPath}"
    echo "Please provide a valid PDF file path"
    FPDF_DestroyLibrary()
    return
  
  let doc = FPDF_LoadDocument(pdfPath, nil)
  if doc.pointer == nil:
    echo "✗ Failed to load document"
    checkError("FPDF_LoadDocument")
    FPDF_DestroyLibrary()
    return
  echo &"✓ Document loaded: {pdfPath}"
  echo ""
  
  # Test 3: Get Page Count
  echo "3. Getting page count..."
  let pageCount = FPDF_GetPageCount(doc)
  echo &"✓ Document has {pageCount} page(s)"
  echo ""
  
  if pageCount == 0:
    echo "✗ No pages in document"
    FPDF_CloseDocument(doc)
    FPDF_DestroyLibrary()
    return
  
  # Test 4: Load First Page
  echo "4. Loading first page..."
  let page = FPDF_LoadPage(doc, 0)
  if page.pointer == nil:
    echo "✗ Failed to load page"
    checkError("FPDF_LoadPage")
    FPDF_CloseDocument(doc)
    FPDF_DestroyLibrary()
    return
  echo "✓ Page loaded"
  echo ""
  
  # Test 5: Get Page Dimensions
  echo "5. Getting page dimensions..."
  let pageWidth = FPDF_GetPageWidth(page)
  let pageHeight = FPDF_GetPageHeight(page)
  echo &"✓ Page size: {pageWidth:.2f} x {pageHeight:.2f} points"
  echo ""
  
  # Test 6: Create Bitmap
  echo "6. Creating bitmap for rendering..."
  let renderWidth = 800
  let renderHeight = int(800.0 * (pageHeight / pageWidth))
  let bitmap = FPDFBitmap_Create(renderWidth.cint, renderHeight.cint, 0)
  
  if bitmap.pointer == nil:
    echo "✗ Failed to create bitmap"
    FPDF_ClosePage(page)
    FPDF_CloseDocument(doc)
    FPDF_DestroyLibrary()
    return
  echo &"✓ Bitmap created: {renderWidth} x {renderHeight} pixels"
  echo ""
  
  # Test 7: Fill Bitmap with White Background
  echo "7. Filling bitmap with white background..."
  # Color: 0xFFFFFFFF = white (ARGB format)
  # Cast to culong to match the expected type
  let whiteColor = 0xFFFFFFFF'u64.culong
  FPDFBitmap_FillRect(bitmap, 0, 0, renderWidth.cint, renderHeight.cint, whiteColor)
  echo "✓ Background filled"
  echo ""
  
  # Test 8: Render Page to Bitmap
  echo "8. Rendering page to bitmap..."
  FPDF_RenderPageBitmap(
    bitmap, page,
    0, 0,  # start_x, start_y
    renderWidth.cint, renderHeight.cint,  # size_x, size_y
    0,  # rotation (0, 1, 2, 3 for 0°, 90°, 180°, 270°)
    0   # flags (0x01 for annotations, 0x10 for LCD text optimization)
  )
  echo "✓ Page rendered"
  echo ""
  
  # Test 9: Get Bitmap Buffer Info
  echo "9. Checking bitmap buffer..."
  let buffer = FPDFBitmap_GetBuffer(bitmap)
  let stride = FPDFBitmap_GetStride(bitmap)
  if buffer == nil:
    echo "✗ Failed to get bitmap buffer"
  else:
    echo &"✓ Buffer obtained - Stride: {stride} bytes"
  echo ""
  
  # Test 10: Save Bitmap to File
  echo "10. Saving rendered page as image..."
  try:
    saveBitmapAsPPM(bitmap, renderWidth, renderHeight, "test_output.ppm")
    echo "   (You can view test_output.ppm with image viewers or convert to PNG)"
  except:
    echo &"✗ Failed to save bitmap: {getCurrentExceptionMsg()}"
  echo ""
  
  # Test 11: Cleanup
  echo "11. Cleaning up resources..."
  FPDFBitmap_Destroy(bitmap)
  echo "✓ Bitmap destroyed"
  
  FPDF_ClosePage(page)
  echo "✓ Page closed"
  
  FPDF_CloseDocument(doc)
  echo "✓ Document closed"
  
  FPDF_DestroyLibrary()
  echo "✓ Library destroyed"
  echo ""
  
  echo "=== All Tests Passed! ==="

# --- Entry Point ---

when isMainModule:
  if paramCount() < 1:
    echo "Usage: ./test_pdfium_bindings <path_to_pdf_file>"
    echo ""
    echo "Example:"
    echo "  ./test_pdfium_bindings sample.pdf"
    quit(1)
  
  let pdfPath = paramStr(1)
  testPDFiumBindings(pdfPath)
