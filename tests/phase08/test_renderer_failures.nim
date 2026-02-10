import std/os
import threading/channels
import pdfocr/[errors, pdfium, renderer, types]

proc testPageRenderFailure() =
  let renderReqCh = newChan[RenderRequest](Positive(8))
  let renderOutCh = newChan[RendererOutput](Positive(8))
  let fatalCh = newChan[FatalEvent](Positive(2))

  var th: Thread[RendererContext]
  createThread(th, runRenderer, RendererContext(
    pdfPath: "tests/slides.pdf",
    selectedPages: @[999_999], # out-of-range page forces loadPage failure
    renderReqCh: renderReqCh,
    renderOutCh: renderOutCh,
    fatalCh: fatalCh
  ))

  renderReqCh.send(RenderRequest(kind: rrkPage, seqId: 0))
  renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))

  var rendered: RendererOutput
  renderOutCh.recv(rendered)
  doAssert rendered.kind == rokRenderFailure
  doAssert rendered.failure.errorKind == PDF_ERROR
  joinThread(th)

proc testEncodeFailure() =
  putEnv("PDFOCR_TEST_FORCE_ENCODE_ERROR", "1")
  defer:
    delEnv("PDFOCR_TEST_FORCE_ENCODE_ERROR")

  let renderReqCh = newChan[RenderRequest](Positive(8))
  let renderOutCh = newChan[RendererOutput](Positive(8))
  let fatalCh = newChan[FatalEvent](Positive(2))

  var th: Thread[RendererContext]
  createThread(th, runRenderer, RendererContext(
    pdfPath: "tests/slides.pdf",
    selectedPages: @[1],
    renderReqCh: renderReqCh,
    renderOutCh: renderOutCh,
    fatalCh: fatalCh
  ))

  renderReqCh.send(RenderRequest(kind: rrkPage, seqId: 0))
  renderReqCh.send(RenderRequest(kind: rrkStop, seqId: -1))

  var rendered: RendererOutput
  renderOutCh.recv(rendered)
  doAssert rendered.kind == rokRenderFailure
  doAssert rendered.failure.errorKind == ENCODE_ERROR
  joinThread(th)

proc testFatalOpenFailure() =
  let renderReqCh = newChan[RenderRequest](Positive(8))
  let renderOutCh = newChan[RendererOutput](Positive(8))
  let fatalCh = newChan[FatalEvent](Positive(2))

  var th: Thread[RendererContext]
  createThread(th, runRenderer, RendererContext(
    pdfPath: "tests/does-not-exist.pdf",
    selectedPages: @[1],
    renderReqCh: renderReqCh,
    renderOutCh: renderOutCh,
    fatalCh: fatalCh
  ))

  var ev: FatalEvent
  fatalCh.recv(ev)
  doAssert ev.source == fesRenderer
  doAssert ev.errorKind == PDF_ERROR
  joinThread(th)

proc main() =
  initPdfium()
  try:
    testPageRenderFailure()
    testEncodeFailure()
    testFatalOpenFailure()
  finally:
    destroyPdfium()

when isMainModule:
  main()
