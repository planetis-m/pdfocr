# Ergonomic libjpeg helpers built on top of the raw bindings.

import std/assertions
import ./bindings/jpeglib

proc cFree(p: pointer) {.importc: "free", header: "<stdlib.h>".}

type
  JpegCompressor* = object
    cinfo: jpeg_compress_struct
    jerr: jpeg_error_mgr
    outBuffer: ptr UncheckedArray[byte]
    outSize: culong
    rowStride: int
    isOpen: bool
  JpegQuality* = range[1..100]

proc `=destroy`*(comp: JpegCompressor) =
  if comp.isOpen:
    jpeg_finish_compress(addr comp.cinfo)
    jpeg_destroy_compress(addr comp.cinfo)
    if comp.outBuffer != nil:
      cFree(comp.outBuffer)

proc `=copy`*(dest: var JpegCompressor; src: JpegCompressor) {.error.}

proc `=sink`*(dest: var JpegCompressor; src: JpegCompressor) =
  `=destroy`(dest)
  dest.cinfo = src.cinfo
  dest.jerr = src.jerr
  dest.outBuffer = src.outBuffer
  dest.outSize = src.outSize
  dest.rowStride = src.rowStride
  dest.isOpen = src.isOpen

proc `=wasMoved`*(comp: var JpegCompressor) =
  comp.outBuffer = nil
  comp.outSize = 0
  comp.rowStride = 0
  comp.isOpen = false

proc initJpegCompressor*(width, height: Positive; quality: JpegQuality = 90): JpegCompressor =
  result.cinfo.err = jpeg_std_error(addr result.jerr)
  jpeg_create_compress(addr result.cinfo)

  result.isOpen = true
  result.outBuffer = nil
  result.outSize = 0
  jpeg_mem_dest(addr result.cinfo, cast[ptr ptr byte](addr result.outBuffer), addr result.outSize)

  result.cinfo.image_width = width.cuint
  result.cinfo.image_height = height.cuint
  result.cinfo.input_components = 3
  result.cinfo.in_color_space = JCS_RGB
  result.rowStride = width * 3

  jpeg_set_defaults(addr result.cinfo)
  jpeg_set_quality(addr result.cinfo, quality.cint, TRUE)
  jpeg_start_compress(addr result.cinfo, TRUE)

proc finishJpeg*(comp: var JpegCompressor): seq[byte] =
  assert comp.isOpen, "compressor not initialized"
  jpeg_finish_compress(addr comp.cinfo)
  jpeg_destroy_compress(addr comp.cinfo)
  if comp.outSize > 0 and comp.outBuffer != nil:
    result.setLen(comp.outSize.int)
    copyMem(addr result[0], comp.outBuffer, comp.outSize.int)
  if comp.outBuffer != nil:
    cFree(comp.outBuffer)
  comp.outBuffer = nil
  comp.outSize = 0
  comp.isOpen = false

proc writeRgb*(comp: var JpegCompressor; buffer: openArray[byte]) =
  assert comp.isOpen, "compressor not initialized"
  if buffer.len < comp.rowStride * comp.cinfo.image_height.int:
    raise newException(ValueError, "buffer too small for image size")

  var rowPointer: JSAMPROW
  while comp.cinfo.next_scanline < comp.cinfo.image_height:
    let offset = comp.cinfo.next_scanline.int * comp.rowStride
    rowPointer = cast[JSAMPROW](addr buffer[offset])
    discard jpeg_write_scanlines(addr comp.cinfo, addr rowPointer, 1)

proc initJpegCompressorBgrx*(width, height: Positive; quality: JpegQuality = 90): JpegCompressor =
  result.cinfo.err = jpeg_std_error(addr result.jerr)
  jpeg_create_compress(addr result.cinfo)

  result.isOpen = true
  result.outBuffer = nil
  result.outSize = 0
  jpeg_mem_dest(addr result.cinfo, cast[ptr ptr byte](addr result.outBuffer), addr result.outSize)

  result.cinfo.image_width = width.cuint
  result.cinfo.image_height = height.cuint
  result.cinfo.input_components = 4
  result.cinfo.in_color_space = JCS_EXT_BGRX
  result.rowStride = width * 4

  jpeg_set_defaults(addr result.cinfo)
  jpeg_set_quality(addr result.cinfo, quality.cint, TRUE)
  jpeg_start_compress(addr result.cinfo, TRUE)

proc writeBgrx*(comp: var JpegCompressor; buffer: pointer; stride: Positive) =
  assert comp.isOpen, "compressor not initialized"

  var rowPointer: JSAMPROW
  let raw = cast[uint](buffer)
  while comp.cinfo.next_scanline < comp.cinfo.image_height:
    let offset = comp.cinfo.next_scanline.uint * stride.uint
    rowPointer = cast[JSAMPROW](raw + offset)
    discard jpeg_write_scanlines(addr comp.cinfo, addr rowPointer, 1)
