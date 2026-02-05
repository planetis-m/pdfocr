# Dynamic library configuration
when defined(windows):
  const jpegDll = "libjpeg-62.dll"
  {.push dynlib: jpegDll, header: "jpeglib.h".}
else:
  {.push header: "jpeglib.h".}
  {.passC: "-include stdio.h".}

# Standard JPEGLib types
type
  j_common_ptr* = ptr jpeg_common_struct
  j_compress_ptr* = ptr jpeg_compress_struct
  
  # We only define fields we read/write.
  # The "incompleteStruct" tells Nim to ignore size mismatches.
  jpeg_compress_struct* {.importc: "struct jpeg_compress_struct", incompleteStruct, pure.} = object
    err*: ptr jpeg_error_mgr
    image_width*: cuint
    image_height*: cuint
    input_components*: cint
    in_color_space*: cint # J_COLOR_SPACE enum
    next_scanline*: cuint
    # We omit the hundreds of private fields; C handles them!
  
  jpeg_common_struct* {.importc: "struct jpeg_common_struct", incompleteStruct, pure.} = object
    err*: ptr jpeg_error_mgr # Pointer to the error manager
  
  # We only list the function pointers we need to override or call.
  # The C compiler handles the rest of the fields/size automatically.
  jpeg_error_mgr* {.importc: "struct jpeg_error_mgr", incompleteStruct, pure.} = object
    error_exit*: proc (cinfo: j_common_ptr) {.cdecl.}
    emit_message*: proc (cinfo: j_common_ptr, msg_level: cint) {.cdecl.}
    output_message*: proc (cinfo: j_common_ptr) {.cdecl.}
    format_message*: proc (cinfo: j_common_ptr, buffer: cstring) {.cdecl.}
    reset_error_mgr*: proc (cinfo: j_common_ptr) {.cdecl.}
  
  # Typedef for row pointers
  JSAMPROW* = ptr UncheckedArray[byte]
  JSAMPARRAY* = ptr JSAMPROW

# Constants from headers
const
  JCS_RGB* = 2
  JCS_EXT_BGRX* = 9 # TurboJPEG extension
  TRUE* = 1
  FALSE* = 0
  JPEG_LIB_VERSION* = 62
  JMSG_LENGTH_MAX* = 200

# --- Function Imports ---
proc jpeg_std_error*(err: ptr jpeg_error_mgr): ptr jpeg_error_mgr {.importc, cdecl.}
proc jpeg_create_compress*(cinfo: ptr jpeg_compress_struct) {.importc, cdecl.}
proc jpeg_stdio_dest*(cinfo: ptr jpeg_compress_struct, outfile: File) {.importc, cdecl.}
proc jpeg_mem_dest*(cinfo: ptr jpeg_compress_struct, outbuffer: ptr ptr byte, outsize: ptr culong) {.importc, cdecl.}
proc jpeg_set_defaults*(cinfo: ptr jpeg_compress_struct) {.importc, cdecl.}
proc jpeg_set_quality*(cinfo: ptr jpeg_compress_struct, quality: cint, force_baseline: cint) {.importc, cdecl.}
proc jpeg_start_compress*(cinfo: ptr jpeg_compress_struct, write_all_tables: cint) {.importc, cdecl.}
proc jpeg_write_scanlines*(cinfo: ptr jpeg_compress_struct, scanlines: JSAMPARRAY, num_lines: cuint): cuint {.importc, cdecl.}
proc jpeg_finish_compress*(cinfo: ptr jpeg_compress_struct) {.importc, cdecl.}
proc jpeg_destroy_compress*(cinfo: ptr jpeg_compress_struct) {.importc, cdecl.}

{.pop.}
