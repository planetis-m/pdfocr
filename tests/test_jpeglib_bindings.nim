import pdfocr/bindings/jpeglib
import std/strformat

proc cFree(p: pointer) {.importc: "free", header: "<stdlib.h>".}

proc createTestImage(width, height: int): seq[byte] =
  ## Creates a simple gradient JPEG image to test the bindings
  var jerr: jpeg_error_mgr
  var cinfo: jpeg_compress_struct

  cinfo.err = jpeg_std_error(addr jerr)
  jpeg_create_compress(addr cinfo)

  var outBuffer: ptr byte = nil
  var outSize: culong = 0

  try:
    jpeg_mem_dest(addr cinfo, addr outBuffer, addr outSize)

    cinfo.image_width = width.cuint
    cinfo.image_height = height.cuint
    cinfo.input_components = 3  # RGB
    cinfo.in_color_space = JCS_RGB

    jpeg_set_defaults(addr cinfo)
    jpeg_set_quality(addr cinfo, 90, TRUE)

    jpeg_start_compress(addr cinfo, TRUE)

    let rowStride = width * 3
    var imageBuffer = newSeq[byte](height * rowStride)

    for y in 0..<height:
      for x in 0..<width:
        let offset = y * rowStride + x * 3
        imageBuffer[offset + 0] = byte((x * 255) div width)      # R
        imageBuffer[offset + 1] = byte((y * 255) div height)     # G
        imageBuffer[offset + 2] = byte(128)                      # B (constant)

    var rowPointer: JSAMPROW
    while cinfo.next_scanline < cinfo.image_height:
      let offset = cinfo.next_scanline.int * rowStride
      rowPointer = cast[JSAMPROW](addr imageBuffer[offset])

      discard jpeg_write_scanlines(addr cinfo, addr rowPointer, 1)

    jpeg_finish_compress(addr cinfo)
    jpeg_destroy_compress(addr cinfo)

    if outSize > 0 and outBuffer != nil:
      result.setLen(outSize.int)
      copyMem(addr result[0], outBuffer, outSize.int)
  except CatchableError:
    result = @[]
  finally:
    if outBuffer != nil:
      cFree(outBuffer)

proc testBasicFunctionality() =
  let bytes = createTestImage(320, 240)
  doAssert bytes.len > 0, "JPEG creation failed"

proc testMultipleSizes() =
  let testCases = [
    (64, 64),
    (128, 128),
    (640, 480),
    (1024, 768)
  ]

  for (w, h) in testCases:
    let bytes = createTestImage(w, h)
    doAssert bytes.len > 0, &"Failed to create {w}x{h} image"

proc testStructAccess() =
  var jerr: jpeg_error_mgr
  var cinfo: jpeg_compress_struct

  cinfo.err = jpeg_std_error(addr jerr)
  jpeg_create_compress(addr cinfo)

  cinfo.image_width = 800
  cinfo.image_height = 600
  cinfo.input_components = 3
  cinfo.in_color_space = JCS_RGB

  assert cinfo.image_width == 800, "Width field mismatch"
  assert cinfo.image_height == 600, "Height field mismatch"
  assert cinfo.input_components == 3, "Components field mismatch"
  assert cinfo.in_color_space == JCS_RGB, "Color space field mismatch"

  jpeg_destroy_compress(addr cinfo)

when isMainModule:
  testStructAccess()
  testBasicFunctionality()
  testMultipleSizes()
