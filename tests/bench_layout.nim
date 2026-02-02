import std/[monotimes, strformat, os, strutils, algorithm]
import pdfocr/pdfium
import pdfocr/layout

proc nowMs(): float =
  float(getMonoTime().ticks) / 1_000_000.0

proc main() =
  let pdfPath = if paramCount() >= 1: paramStr(1) else: "tests/input.pdf"
  let iters = if paramCount() >= 2: parseInt(paramStr(2)) else: 5
  let warmups = if paramCount() >= 3: parseInt(paramStr(3)) else: 2

  if not fileExists(pdfPath):
    echo "Missing PDF: ", pdfPath
    quit(1)

  initPdfium()
  var doc: PdfDocument
  var page: PdfPage
  try:
    doc = loadDocument(pdfPath)
    page = loadPage(doc, 0)

    let params = newLAParams(wordMargin = 0.3)

    for _ in 0 ..< warmups:
      discard buildTextPageLayout(page, params)

    var samples: seq[float] = @[]
    for _ in 0 ..< iters:
      let start = nowMs()
      discard buildTextPageLayout(page, params)
      let elapsed = nowMs() - start
      samples.add(elapsed)

    samples.sort()
    let minv = samples[0]
    let maxv = samples[^1]
    var sum = 0.0
    for v in samples:
      sum += v
    let mean = sum / samples.len.float
    let p50 = if samples.len mod 2 == 1:
      samples[samples.len div 2]
    else:
      (samples[samples.len div 2 - 1] + samples[samples.len div 2]) / 2.0
    echo &"layout: iters={iters} warmups={warmups} mean={mean:.3f}ms p50={p50:.3f}ms min={minv:.3f}ms max={maxv:.3f}ms"
  finally:
    close(page)
    close(doc)
    destroyPdfium()

when isMainModule:
  main()
