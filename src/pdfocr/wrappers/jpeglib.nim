# We rely on the system's C header for the actual size/layout during compilation.

{.passC: "-include stdio.h".}

# Standard JPEGLib types
type
  # Opaque pointers
  j_common_ptr* = pointer
  j_compress_ptr* = ptr jpeg_compress_struct

  # We only define fields we read/write.
  # The "incompleteStruct" tells Nim to ignore size mismatches.
  jpeg_compress_struct* {.importc: "struct jpeg_compress_struct", header: "<jpeglib.h>", incompleteStruct, pure.} = object
    err*: ptr jpeg_error_mgr
    image_width*: cuint
    image_height*: cuint
    input_components*: cint
    in_color_space*: cint # J_COLOR_SPACE enum
    next_scanline*: cuint
    # We omit the hundreds of private fields; C handles them!

  jpeg_error_mgr* {.importc: "struct jpeg_error_mgr", header: "<jpeglib.h>", incompleteStruct, pure.} = object
    # We generally just pass the pointer, but if you need fields, add them here.

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

# --- Function Imports ---
{.push importc, callconv: cdecl, header: "<jpeglib.h>".}

# Standard API
proc jpeg_std_error*(err: ptr jpeg_error_mgr): ptr jpeg_error_mgr
proc jpeg_create_compress*(cinfo: ptr jpeg_compress_struct)
proc jpeg_stdio_dest*(cinfo: ptr jpeg_compress_struct, outfile: File) # Nim File maps to FILE* in C backend
proc jpeg_set_defaults*(cinfo: ptr jpeg_compress_struct)
proc jpeg_set_quality*(cinfo: ptr jpeg_compress_struct, quality: cint, force_baseline: cint)
proc jpeg_start_compress*(cinfo: ptr jpeg_compress_struct, write_all_tables: cint)
proc jpeg_write_scanlines*(cinfo: ptr jpeg_compress_struct, scanlines: JSAMPARRAY, num_lines: cuint): cuint
proc jpeg_finish_compress*(cinfo: ptr jpeg_compress_struct)
proc jpeg_destroy_compress*(cinfo: ptr jpeg_compress_struct)

{.pop.}

