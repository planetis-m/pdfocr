# Ergonomic libjpeg helpers built on top of the raw bindings.

import std/strformat
import ./bindings/jpeglib

type
  JpegCompressor* = object
    cinfo: jpeg_compress_struct
    jerr: jpeg_error_mgr
    outfile: File
    rowStride: int
    isOpen: bool

proc initJpegCompressor*(path: string; width, height: int; quality: int = 90): JpegCompressor =
  if width <= 0 or height <= 0:
    raise newException(ValueError, "invalid image dimensions")
  if quality < 1 or quality > 100:
    raise newException(ValueError, "quality must be 1..100")

  result.cinfo.err = jpeg_std_error(addr result.jerr)
  jpeg_create_compress(addr result.cinfo)

  if not open(result.outfile, path, fmWrite):
    jpeg_destroy_compress(addr result.cinfo)
    raise newException(IOError, &"could not open output file: {path}")

  result.isOpen = true
  jpeg_stdio_dest(addr result.cinfo, result.outfile)

  result.cinfo.image_width = width.cuint
  result.cinfo.image_height = height.cuint
  result.cinfo.input_components = 3
  result.cinfo.in_color_space = JCS_RGB
  result.rowStride = width * 3

  jpeg_set_defaults(addr result.cinfo)
  jpeg_set_quality(addr result.cinfo, quality.cint, TRUE)
  jpeg_start_compress(addr result.cinfo, TRUE)

proc writeRgb*(comp: var JpegCompressor; buffer: openArray[byte]) =
  if not comp.isOpen:
    raise newException(IOError, "compressor not initialized")
  if buffer.len < comp.rowStride * comp.cinfo.image_height.int:
    raise newException(ValueError, "buffer too small for image size")

  var rowPointer: JSAMPROW
  while comp.cinfo.next_scanline < comp.cinfo.image_height:
    let offset = comp.cinfo.next_scanline.int * comp.rowStride
    rowPointer = cast[JSAMPROW](unsafeAddr buffer[offset])
    discard jpeg_write_scanlines(addr comp.cinfo, addr rowPointer, 1)

proc finish*(comp: var JpegCompressor) =
  if comp.isOpen:
    jpeg_finish_compress(addr comp.cinfo)
    jpeg_destroy_compress(addr comp.cinfo)
    comp.isOpen = false
    if comp.outfile != nil:
      close(comp.outfile)
      comp.outfile = nil
