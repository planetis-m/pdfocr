import threading/channels
import pdfocr/errors
import pdfocr/[types, writer]

const N = 120_000

proc main() =
  resetSharedAtomics()

  var selectedPages = newSeq[int](N)
  for i in 0 ..< N:
    selectedPages[i] = i + 1

  let writerInCh = newChan[PageResult](Positive(64))
  let fatalCh = newChan[FatalEvent](Positive(2))

  var th: Thread[WriterContext]
  createThread(th, runWriter, WriterContext(
    selectedCount: selectedPages.len,
    selectedPages: selectedPages,
    writerInCh: writerInCh,
    fatalCh: fatalCh
  ))

  for i in 0 ..< N:
    writerInCh.send(PageResult(
      seqId: i,
      page: i + 1,
      status: psOk,
      attempts: 1,
      text: "",
      errorKind: PARSE_ERROR,
      errorMessage: "",
      httpStatus: 0,
      hasHttpStatus: false
    ))

  joinThread(th)

when isMainModule:
  main()
