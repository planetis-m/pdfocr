import std/[os, strformat]
import pdfocr/jpeglib

proc main() =
  let outputPath = "test_output_wrapper.jpg"
  let width = 320
  let height = 240
  let rowStride = width * 3

  var buffer = newSeq[byte](height * rowStride)
  for y in 0..<height:
    for x in 0..<width:
      let offset = y * rowStride + x * 3
      buffer[offset + 0] = byte((x * 255) div width)
      buffer[offset + 1] = byte((y * 255) div height)
      buffer[offset + 2] = byte(128)

  var comp = initJpegCompressor(outputPath, width, height, quality = 85)
  try:
    writeRgb(comp, buffer)
  finally:
    finish(comp)

  doAssert fileExists(outputPath)
  let size = getFileSize(outputPath)
  echo &"Wrote {outputPath} ({size} bytes)"

when isMainModule:
  main()
