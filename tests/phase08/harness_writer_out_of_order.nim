import threading/channels
import pdfocr/errors
import pdfocr/[types, writer]

proc main() =
  resetSharedAtomics()

  let selectedPages = @[2, 4, 6]
  let writerInCh = newChan[PageResult](Positive(8))
  let fatalCh = newChan[FatalEvent](Positive(2))

  var th: Thread[WriterContext]
  createThread(th, runWriter, WriterContext(
    selectedCount: selectedPages.len,
    selectedPages: selectedPages,
    writerInCh: writerInCh,
    fatalCh: fatalCh
  ))

  writerInCh.send(PageResult(
    seqId: 2, page: 6, status: psOk, attempts: 1, text: "c",
    errorKind: PARSE_ERROR, errorMessage: "", httpStatus: 0, hasHttpStatus: false
  ))
  writerInCh.send(PageResult(
    seqId: 0, page: 2, status: psOk, attempts: 1, text: "a",
    errorKind: PARSE_ERROR, errorMessage: "", httpStatus: 0, hasHttpStatus: false
  ))
  writerInCh.send(PageResult(
    seqId: 1, page: 4, status: psOk, attempts: 1, text: "b",
    errorKind: PARSE_ERROR, errorMessage: "", httpStatus: 0, hasHttpStatus: false
  ))

  joinThread(th)

when isMainModule:
  main()
