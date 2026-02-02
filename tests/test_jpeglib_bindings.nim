import pdfocr/wrappers/jpeglib
import std/[os, strformat, strutils]

proc createTestImage(width, height: int, outputPath: string): bool =
  ## Creates a simple gradient JPEG image to test the bindings
  echo &"Creating {width}x{height} test image at: {outputPath}"
  
  # Initialize error manager
  var jerr: jpeg_error_mgr
  var cinfo: jpeg_compress_struct
  
  # Set up error handling
  cinfo.err = jpeg_std_error(addr jerr)
  
  # Create compressor
  jpeg_create_compress(addr cinfo)
  
  # Open output file
  var outfile: File
  if not open(outfile, outputPath, fmWrite):
    echo "ERROR: Could not open output file"
    return false

  try:
    # Set output destination
    jpeg_stdio_dest(addr cinfo, outfile)
    
    # Set image parameters
    cinfo.image_width = width.cuint
    cinfo.image_height = height.cuint
    cinfo.input_components = 3  # RGB
    cinfo.in_color_space = JCS_RGB
    
    echo &"  Image dimensions: {cinfo.image_width}x{cinfo.image_height}"
    echo &"  Color space: RGB ({cinfo.input_components} components)"
    
    # Set compression defaults
    jpeg_set_defaults(addr cinfo)
    jpeg_set_quality(addr cinfo, 90, TRUE)
    echo "  Quality: 90"
    
    # Start compression
    jpeg_start_compress(addr cinfo, TRUE)
    echo "  Compression started"
    
    # Create a gradient image buffer (RGB)
    let rowStride = width * 3
    var imageBuffer = newSeq[byte](height * rowStride)
    
    # Fill with a gradient pattern
    for y in 0..<height:
      for x in 0..<width:
        let offset = y * rowStride + x * 3
        imageBuffer[offset + 0] = byte((x * 255) div width)      # R
        imageBuffer[offset + 1] = byte((y * 255) div height)     # G
        imageBuffer[offset + 2] = byte(128)                      # B (constant)
    
    echo "  Image buffer created with gradient pattern"
    
    # Write scanlines
    var rowPointer: JSAMPROW
    var linesWritten = 0
    
    while cinfo.next_scanline < cinfo.image_height:
      let offset = cinfo.next_scanline.int * rowStride
      rowPointer = cast[JSAMPROW](addr imageBuffer[offset])
      
      let written = jpeg_write_scanlines(addr cinfo, addr rowPointer, 1)
      linesWritten += written.int
    
    echo &"  Wrote {linesWritten} scanlines"
    
    # Finish compression
    jpeg_finish_compress(addr cinfo)
    echo "  Compression finished"
    
    # Cleanup
    jpeg_destroy_compress(addr cinfo)
    echo "  Cleanup complete"
    
    return true
    
  except Exception as e:
    echo &"ERROR during JPEG creation: {e.msg}"
    return false
  finally:
    if outfile != nil:
      close(outfile)

proc testBasicFunctionality() =
  echo "\n=== Testing Basic JPEG Functionality ==="
  
  let success = createTestImage(320, 240, "test_output.jpg")
  
  if success:
    echo "\n✓ Test PASSED: JPEG file created successfully"
    
    # Verify file exists and has size
    if fileExists("test_output.jpg"):
      let fileSize = getFileSize("test_output.jpg")
      echo &"✓ File exists with size: {fileSize} bytes"
      
      if fileSize > 0:
        echo "✓ File has non-zero size"
      else:
        echo "✗ WARNING: File is empty"
    else:
      echo "✗ ERROR: Output file does not exist"
  else:
    echo "\n✗ Test FAILED: Could not create JPEG file"

proc testMultipleSizes() =
  echo "\n=== Testing Multiple Image Sizes ==="
  
  let testCases = [
    (64, 64, "test_64x64.jpg"),
    (128, 128, "test_128x128.jpg"),
    (640, 480, "test_640x480.jpg"),
    (1024, 768, "test_1024x768.jpg")
  ]
  
  var passCount = 0
  for (w, h, path) in testCases:
    if createTestImage(w, h, path):
      passCount += 1
      echo &"✓ {path} created successfully\n"
    else:
      echo &"✗ {path} FAILED\n"
  
  echo &"Passed {passCount}/{testCases.len} size tests"

proc testStructAccess() =
  echo "\n=== Testing Struct Field Access ==="
  
  var jerr: jpeg_error_mgr
  var cinfo: jpeg_compress_struct
  
  cinfo.err = jpeg_std_error(addr jerr)
  jpeg_create_compress(addr cinfo)
  
  # Test field writes
  cinfo.image_width = 800
  cinfo.image_height = 600
  cinfo.input_components = 3
  cinfo.in_color_space = JCS_RGB
  
  # Test field reads
  echo &"  Set width: {cinfo.image_width}"
  echo &"  Set height: {cinfo.image_height}"
  echo &"  Set components: {cinfo.input_components}"
  echo &"  Set color space: {cinfo.in_color_space}"
  
  assert cinfo.image_width == 800, "Width field mismatch"
  assert cinfo.image_height == 600, "Height field mismatch"
  assert cinfo.input_components == 3, "Components field mismatch"
  assert cinfo.in_color_space == JCS_RGB, "Color space field mismatch"
  
  jpeg_destroy_compress(addr cinfo)
  
  echo "✓ All struct field access tests passed"

proc main() =
  echo "╔════════════════════════════════════════╗"
  echo "║  LibJPEG Bindings Test Suite           ║"
  echo "╚════════════════════════════════════════╝"
  
  try:
    testStructAccess()
    testBasicFunctionality()
    testMultipleSizes()
    
    echo "\n" & repeat("═", 40)
    echo "All tests completed!"
    echo "Check the generated .jpg files to verify visual output."
    echo repeat("═", 40)
    
  except Exception as e:
    echo &"\n✗ FATAL ERROR: {e.msg}"
    echo getStackTrace(e)
    quit(1)

when isMainModule:
  main()
