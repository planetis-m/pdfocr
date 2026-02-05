import std/strformat
import pdfocr/jpeglib

proc main() =
  let width = 320
  let height = 240
  let rowStride = width * 4

  var buffer = newSeq[byte](height * rowStride)
  for y in 0..<height:
    for x in 0..<width:
      let offset = y * rowStride + x * 4
      buffer[offset + 0] = byte((x * 255) div width)   # B
      buffer[offset + 1] = byte((y * 255) div height)  # G
      buffer[offset + 2] = byte(128)                   # R
      buffer[offset + 3] = byte(255)                   # X/alpha padding

  let bytes = compressBgrx(width, height, addr buffer[0], rowStride, quality = 85)

  doAssert bytes.len > 0
  echo &"Wrote in-memory JPEG ({bytes.len} bytes)"

when isMainModule:
  main()
