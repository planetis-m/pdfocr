import pdfocr/bindings/jpeglib
import std/[os, strformat]

proc createTestImage(width, height: int, outputPath: string): bool =
  ## Creates a simple gradient JPEG image to test the bindings
  var jerr: jpeg_error_mgr
  var cinfo: jpeg_compress_struct
  
  cinfo.err = jpeg_std_error(addr jerr)
  jpeg_create_compress(addr cinfo)

  var outfile: File
  if not open(outfile, outputPath, fmWrite):
    return false

  try:
    jpeg_stdio_dest(addr cinfo, outfile)

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

    return true
  except CatchableError:
    return false
  finally:
    if outfile != nil:
      close(outfile)

proc testBasicFunctionality() =
  let success = createTestImage(320, 240, "test_output.jpg")
  doAssert success, "JPEG creation failed"
  doAssert fileExists("test_output.jpg"), "Output file does not exist"
  doAssert getFileSize("test_output.jpg") > 0, "Output file is empty"

proc testMultipleSizes() =
  let testCases = [
    (64, 64, "test_64x64.jpg"),
    (128, 128, "test_128x128.jpg"),
    (640, 480, "test_640x480.jpg"),
    (1024, 768, "test_1024x768.jpg")
  ]

  for (w, h, path) in testCases:
    let ok = createTestImage(w, h, path)
    doAssert ok, &"Failed to create {path}"
    doAssert fileExists(path), &"Missing output file: {path}"
    doAssert getFileSize(path) > 0, &"Empty output file: {path}"

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
