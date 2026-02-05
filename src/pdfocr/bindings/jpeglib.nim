# We need stdio.h before jpeglib.h for FILE type
{.passC: "-include stdio.h".}

when hostOS == "windows":
  import std/dynlib
  
  # Load the DLL
  let jpegHandle = loadLib("libjpeg-62.dll")
  if jpegHandle == nil:
    {.error: "Failed to load libjpeg-62.dll at compile time check".}

# Standard JPEGLib types (always need header for struct definitions)
type
  j_common_ptr* = ptr jpeg_common_struct
  j_compress_ptr* = ptr jpeg_compress_struct
  
  jpeg_compress_struct* {.importc: "struct jpeg_compress_struct", header: "<jpeglib.h>", incompleteStruct, pure.} = object
    err*: ptr jpeg_error_mgr
    image_width*: cuint
    image_height*: cuint
    input_components*: cint
    in_color_space*: cint
    next_scanline*: cuint
  
  jpeg_common_struct* {.importc: "struct jpeg_common_struct", header: "<jpeglib.h>", incompleteStruct, pure.} = object
    err*: ptr jpeg_error_mgr
  
  jpeg_error_mgr* {.importc: "struct jpeg_error_mgr", header: "<jpeglib.h>", incompleteStruct, pure.} = object
    error_exit*: proc (cinfo: j_common_ptr) {.cdecl.}
    emit_message*: proc (cinfo: j_common_ptr, msg_level: cint) {.cdecl.}
    output_message*: proc (cinfo: j_common_ptr) {.cdecl.}
    format_message*: proc (cinfo: j_common_ptr, buffer: cstring) {.cdecl.}
    reset_error_mgr*: proc (cinfo: j_common_ptr) {.cdecl.}
  
  JSAMPROW* = ptr UncheckedArray[byte]
  JSAMPARRAY* = ptr JSAMPROW

# Constants
const
  JCS_RGB* = 2
  JCS_EXT_BGRX* = 9
  TRUE* = 1
  FALSE* = 0
  JPEG_LIB_VERSION* = 62
  JMSG_LENGTH_MAX* = 200

# Function type definitions
type
  ProcJpegStdError = proc(err: ptr jpeg_error_mgr): ptr jpeg_error_mgr {.cdecl.}
  ProcJpegCreateCompress = proc(cinfo: ptr jpeg_compress_struct, version: cint, structsize: csize_t) {.cdecl.}
  ProcJpegStdioDest = proc(cinfo: ptr jpeg_compress_struct, outfile: File) {.cdecl.}
  ProcJpegMemDest = proc(cinfo: ptr jpeg_compress_struct, outbuffer: ptr ptr byte, outsize: ptr culong) {.cdecl.}
  ProcJpegSetDefaults = proc(cinfo: ptr jpeg_compress_struct) {.cdecl.}
  ProcJpegSetQuality = proc(cinfo: ptr jpeg_compress_struct, quality: cint, force_baseline: cint) {.cdecl.}
  ProcJpegStartCompress = proc(cinfo: ptr jpeg_compress_struct, write_all_tables: cint) {.cdecl.}
  ProcJpegWriteScanlines = proc(cinfo: ptr jpeg_compress_struct, scanlines: JSAMPARRAY, num_lines: cuint): cuint {.cdecl.}
  ProcJpegFinishCompress = proc(cinfo: ptr jpeg_compress_struct) {.cdecl.}
  ProcJpegDestroyCompress = proc(cinfo: ptr jpeg_compress_struct) {.cdecl.}

when hostOS == "windows":
  # Dynamically loaded functions
  var
    jpeg_std_error_impl: ProcJpegStdError
    jpeg_CreateCompress_impl: ProcJpegCreateCompress
    jpeg_stdio_dest_impl: ProcJpegStdioDest
    jpeg_mem_dest_impl: ProcJpegMemDest
    jpeg_set_defaults_impl: ProcJpegSetDefaults
    jpeg_set_quality_impl: ProcJpegSetQuality
    jpeg_start_compress_impl: ProcJpegStartCompress
    jpeg_write_scanlines_impl: ProcJpegWriteScanlines
    jpeg_finish_compress_impl: ProcJpegFinishCompress
    jpeg_destroy_compress_impl: ProcJpegDestroyCompress
  
  proc initJpegLib() =
    let handle = loadLib("libjpeg-62.dll")
    if handle == nil:
      raise newException(LibraryError, "Failed to load libjpeg-62.dll")
    
    jpeg_std_error_impl = cast[ProcJpegStdError](symAddr(handle, "jpeg_std_error"))
    if jpeg_std_error_impl == nil:
      raise newException(LibraryError, "Failed to load jpeg_std_error from libjpeg-62.dll")
    
    jpeg_CreateCompress_impl = cast[ProcJpegCreateCompress](symAddr(handle, "jpeg_CreateCompress"))
    if jpeg_CreateCompress_impl == nil:
      raise newException(LibraryError, "Failed to load jpeg_CreateCompress from libjpeg-62.dll")
    
    jpeg_stdio_dest_impl = cast[ProcJpegStdioDest](symAddr(handle, "jpeg_stdio_dest"))
    if jpeg_stdio_dest_impl == nil:
      raise newException(LibraryError, "Failed to load jpeg_stdio_dest from libjpeg-62.dll")
    
    jpeg_mem_dest_impl = cast[ProcJpegMemDest](symAddr(handle, "jpeg_mem_dest"))
    if jpeg_mem_dest_impl == nil:
      raise newException(LibraryError, "Failed to load jpeg_mem_dest from libjpeg-62.dll")
    
    jpeg_set_defaults_impl = cast[ProcJpegSetDefaults](symAddr(handle, "jpeg_set_defaults"))
    if jpeg_set_defaults_impl == nil:
      raise newException(LibraryError, "Failed to load jpeg_set_defaults from libjpeg-62.dll")
    
    jpeg_set_quality_impl = cast[ProcJpegSetQuality](symAddr(handle, "jpeg_set_quality"))
    if jpeg_set_quality_impl == nil:
      raise newException(LibraryError, "Failed to load jpeg_set_quality from libjpeg-62.dll")
    
    jpeg_start_compress_impl = cast[ProcJpegStartCompress](symAddr(handle, "jpeg_start_compress"))
    if jpeg_start_compress_impl == nil:
      raise newException(LibraryError, "Failed to load jpeg_start_compress from libjpeg-62.dll")
    
    jpeg_write_scanlines_impl = cast[ProcJpegWriteScanlines](symAddr(handle, "jpeg_write_scanlines"))
    if jpeg_write_scanlines_impl == nil:
      raise newException(LibraryError, "Failed to load jpeg_write_scanlines from libjpeg-62.dll")
    
    jpeg_finish_compress_impl = cast[ProcJpegFinishCompress](symAddr(handle, "jpeg_finish_compress"))
    if jpeg_finish_compress_impl == nil:
      raise newException(LibraryError, "Failed to load jpeg_finish_compress from libjpeg-62.dll")
    
    jpeg_destroy_compress_impl = cast[ProcJpegDestroyCompress](symAddr(handle, "jpeg_destroy_compress"))
    if jpeg_destroy_compress_impl == nil:
      raise newException(LibraryError, "Failed to load jpeg_destroy_compress from libjpeg-62.dll")
  
  # Initialize on module load
  initJpegLib()
  
  # Public API wrappers
  proc jpeg_std_error*(err: ptr jpeg_error_mgr): ptr jpeg_error_mgr =
    jpeg_std_error_impl(err)
  
  proc jpeg_create_compress*(cinfo: ptr jpeg_compress_struct) =
    jpeg_CreateCompress_impl(cinfo, JPEG_LIB_VERSION, csize_t(sizeof(jpeg_compress_struct)))
  
  proc jpeg_stdio_dest*(cinfo: ptr jpeg_compress_struct, outfile: File) =
    jpeg_stdio_dest_impl(cinfo, outfile)
  
  proc jpeg_mem_dest*(cinfo: ptr jpeg_compress_struct, outbuffer: ptr ptr byte, outsize: ptr culong) =
    jpeg_mem_dest_impl(cinfo, outbuffer, outsize)
  
  proc jpeg_set_defaults*(cinfo: ptr jpeg_compress_struct) =
    jpeg_set_defaults_impl(cinfo)
  
  proc jpeg_set_quality*(cinfo: ptr jpeg_compress_struct, quality: cint, force_baseline: cint) =
    jpeg_set_quality_impl(cinfo, quality, force_baseline)
  
  proc jpeg_start_compress*(cinfo: ptr jpeg_compress_struct, write_all_tables: cint) =
    jpeg_start_compress_impl(cinfo, write_all_tables)
  
  proc jpeg_write_scanlines*(cinfo: ptr jpeg_compress_struct, scanlines: JSAMPARRAY, num_lines: cuint): cuint =
    jpeg_write_scanlines_impl(cinfo, scanlines, num_lines)
  
  proc jpeg_finish_compress*(cinfo: ptr jpeg_compress_struct) =
    jpeg_finish_compress_impl(cinfo)
  
  proc jpeg_destroy_compress*(cinfo: ptr jpeg_compress_struct) =
    jpeg_destroy_compress_impl(cinfo)

else:
  # Linux/macOS: use header-based imports
  {.passC: "-include stdio.h".}
  {.push header: "<jpeglib.h>", cdecl, importc.}
  
  proc jpeg_std_error*(err: ptr jpeg_error_mgr): ptr jpeg_error_mgr
  proc jpeg_create_compress*(cinfo: ptr jpeg_compress_struct)
  proc jpeg_stdio_dest*(cinfo: ptr jpeg_compress_struct, outfile: File)
  proc jpeg_mem_dest*(cinfo: ptr jpeg_compress_struct, outbuffer: ptr ptr byte, outsize: ptr culong)
  proc jpeg_set_defaults*(cinfo: ptr jpeg_compress_struct)
  proc jpeg_set_quality*(cinfo: ptr jpeg_compress_struct, quality: cint, force_baseline: cint)
  proc jpeg_start_compress*(cinfo: ptr jpeg_compress_struct, write_all_tables: cint)
  proc jpeg_write_scanlines*(cinfo: ptr jpeg_compress_struct, scanlines: JSAMPARRAY, num_lines: cuint): cuint
  proc jpeg_finish_compress*(cinfo: ptr jpeg_compress_struct)
  proc jpeg_destroy_compress*(cinfo: ptr jpeg_compress_struct)
  
  {.pop.}
