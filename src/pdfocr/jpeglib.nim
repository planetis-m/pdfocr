# Ergonomic libjpeg helpers built on top of the raw bindings.

import ./bindings/jpeglib

proc cFree(p: pointer) {.importc: "free", header: "<stdlib.h>".}

type
  JpegError* = object of CatchableError
  JpegQuality* = range[1..100]

  JpegCompressor = object
    cinfo: jpeg_compress_struct
    jerr: jpeg_error_mgr
    outBuffer: ptr UncheckedArray[byte]
    outSize: culong
    rowStride: int

proc errorExit(cinfo: j_common_ptr) {.cdecl.} =
  var buffer: array[JMSG_LENGTH_MAX, char]
  # Let libjpeg format the error message into our buffer
  if cinfo.err.format_message != nil:
    cinfo.err.format_message(cinfo, cast[cstring](addr buffer))
  else: # Fallback if formatter is missing
    let msg = "Unknown fatal error in libjpeg (format_message missing)"
    copyMem(addr buffer[0], addr msg[0], min(msg.len + 1, JMSG_LENGTH_MAX))
  # Raise exception to unwind (replaces exit(1))
  raise newException(JpegError, $cast[cstring](addr buffer))

proc emitMessage(cinfo: j_common_ptr, msg_level: cint) {.cdecl.} =
  discard

proc initCompressor(comp: var JpegCompressor; width, height: int; quality: int) =
  comp.cinfo.err = jpeg_std_error(addr comp.jerr)
  comp.jerr.error_exit = errorExit
  comp.jerr.emit_message = emitMessage

  jpeg_create_compress(addr comp.cinfo)

  # Prepare memory destination (libjpeg will allocate the buffer)
  comp.outBuffer = nil
  comp.outSize = 0
  jpeg_mem_dest(addr comp.cinfo, cast[ptr ptr byte](addr comp.outBuffer), addr comp.outSize)

  # Configure image for BGRX (4 channels)
  comp.cinfo.image_width = width.cuint
  comp.cinfo.image_height = height.cuint
  comp.cinfo.input_components = 4
  comp.cinfo.in_color_space = JCS_EXT_BGRX

  jpeg_set_defaults(addr comp.cinfo)
  jpeg_set_quality(addr comp.cinfo, quality.cint, TRUE)
  jpeg_start_compress(addr comp.cinfo, TRUE)

proc writeRows(comp: var JpegCompressor; pixels: pointer; stride: int) =
  var rowPointer: JSAMPROW
  let raw = cast[uint](pixels)
  
  while comp.cinfo.next_scanline < comp.cinfo.image_height:
    # Calculate exact row address using the provided stride
    let offset = comp.cinfo.next_scanline.int * stride
    rowPointer = cast[JSAMPROW](raw + offset.uint)
    discard jpeg_write_scanlines(addr comp.cinfo, addr rowPointer, 1)

proc finishCompressor(comp: var JpegCompressor): seq[byte] =
  jpeg_finish_compress(addr comp.cinfo)
  
  # Copy the C buffer content into a new Nim sequence
  if comp.outSize > 0 and comp.outBuffer != nil:
    result = newSeq[byte](comp.outSize.int)
    copyMem(addr result[0], comp.outBuffer, comp.outSize.int)
  else:
    result = @[]

proc destroyCompressor(comp: var JpegCompressor) =
  if comp.outBuffer != nil:
    cFree(comp.outBuffer)
  jpeg_destroy_compress(addr comp.cinfo)

proc compressBgrx*(width, height: Positive; pixels: pointer; stride: Positive; quality: JpegQuality = 90): seq[byte] =
  ## Compresses a BGRX buffer (pointer + stride) into a new JPEG sequence.
  var comp: JpegCompressor
  initCompressor(comp, width, height, quality)
  
  try:
    writeRows(comp, pixels, stride)
    result = finishCompressor(comp)
  finally:
    destroyCompressor(comp)
