import pdfocr/page_ranges

proc main() =
  doAssert normalizePageRange(10, 1, -1) == 1 .. 10
  doAssert normalizePageRange(10, 5, 3) == 3 .. 5
  doAssert normalizePageRange(10, -2, 4) == 1 .. 4
  doAssert normalizePageRange(0, 1, -1) == 0 .. -1

when isMainModule:
  main()
