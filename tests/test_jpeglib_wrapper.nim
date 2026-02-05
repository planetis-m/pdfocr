import std/strformat
import pdfocr/jpeglib

proc main() =
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

  var comp = initJpegCompressor(width, height, quality = 85)
  writeRgb(comp, buffer)
  let bytes = finishJpeg(comp)

  doAssert bytes.len > 0
  echo &"Wrote in-memory JPEG ({bytes.len} bytes)"

when isMainModule:
  main()
