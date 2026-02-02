import pdfocr/wrappers/[jpeglib, pdfium]
import std/[os, widestrs]

# --- Clean Text Extraction using widestrs ---
proc extractText(page: FPDF_PAGE): string =
  let textPage = FPDFText_LoadPage(page)
  if cast[pointer](textPage) == nil: return ""
  
  # Ensure we clean up the text page when this function exits
  defer: FPDFText_ClosePage(textPage)

  let count = FPDFText_CountChars(textPage)
  if count <= 0: return ""

  # 1. Allocate UTF-16 buffer
  # We allocate 'count' characters. 
  # newWideCString automatically handles memory and zero-termination safety.
  var wStr = newWideCString(count)

  # 2. Fill it with PDFium
  # We convert the Obj to the raw pointer using 'toWideCString' (implicit or explicit)
  # and pass it to C.
  discard FPDFText_GetText(textPage, 0, count, cast[ptr uint16](toWideCString(wStr)))

  # 3. Convert to UTF-8
  # The `$` operator for WideCStringObj automatically converts 
  # UTF-16LE to a native UTF-8 Nim string.
  result = $wStr

# --- Pure Nim Save Function ---
proc saveJpeg(filename: string, buffer: pointer, width, height, stride: int) =
  # Stack allocation works because the C compiler knows the size of the struct
  # referenced in the emitted code, even if Nim doesn't know it here.
  var cinfo: jpeg_compress_struct
  var jerr: jpeg_error_mgr
  
  # 1. Error handling
  cinfo.err = jpeg_std_error(addr jerr)
  
  # 2. Init
  # Uses our template to pass the correct C-side sizeof()
  jpeg_create_compress(addr cinfo)
  
  # 3. IO
  # Nim's 'open' returns a File object that is compatible with C's FILE*
  let f = open(filename, fmWrite)
  jpeg_stdio_dest(addr cinfo, f)
  
  # 4. Settings
  cinfo.image_width = width.cuint
  cinfo.image_height = height.cuint
  cinfo.input_components = 4
  cinfo.in_color_space = JCS_EXT_BGRX # Speed boost
  
  jpeg_set_defaults(addr cinfo)
  jpeg_set_quality(addr cinfo, 95, TRUE)
  
  # 5. Compress
  jpeg_start_compress(addr cinfo, TRUE)
  
  var row_ptr: JSAMPROW
  let raw_buf = cast[ByteAddress](buffer)
  
  while cinfo.next_scanline < cinfo.image_height:
    # Pointer arithmetic
    let row_addr = raw_buf + (cinfo.next_scanline.int * stride)
    row_ptr = cast[JSAMPROW](row_addr)
    
    # Pass address of the row pointer
    discard jpeg_write_scanlines(addr cinfo, addr row_ptr, 1)
    
  # 6. Cleanup
  jpeg_finish_compress(addr cinfo)
  jpeg_destroy_compress(addr cinfo)
  close(f)

# --- Main ---
proc main() =
  let inputFile = "input.pdf"
  let outputFile = "final_output.jpg"
  let dpiScale = 2.0 

  var config: FPDF_LIBRARY_CONFIG
  config.version = 2
  FPDF_InitLibraryWithConfig(addr config)

  let doc = FPDF_LoadDocument(inputFile, nil)
  if cast[pointer](doc) == nil:
    quit("Failed to load PDF")
    
  let page = FPDF_LoadPage(doc, 0)
  
  let width = (FPDF_GetPageWidth(page) * dpiScale).cint
  let height = (FPDF_GetPageHeight(page) * dpiScale).cint
  
  echo "Rendering ", width, "x", height
  
  let bitmap = FPDFBitmap_Create(width, height, 0)
  FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF.culong)
  FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 0)
  
  saveJpeg(outputFile, 
           FPDFBitmap_GetBuffer(bitmap), 
           width.int, height.int, 
           FPDFBitmap_GetStride(bitmap).int)
           
  echo "Saved to ", outputFile

  # 2. Extract Text
  echo "\n--- Extracted Text ---"
  echo extractText(page)
  echo "----------------------"
  
  FPDFBitmap_Destroy(bitmap)
  FPDF_ClosePage(page)
  FPDF_CloseDocument(doc)
  FPDF_DestroyLibrary()

main()

