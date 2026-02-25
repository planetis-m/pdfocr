import pdfocr/page_selection

proc expectValueError(spec: string; totalPages: int) =
  var raised = false
  try:
    discard normalizePageSelection(spec, totalPages)
  except ValueError:
    raised = true
  doAssert raised, "expected ValueError for spec: " & spec

proc main() =
  doAssert allPagesSelection(5) == @[1, 2, 3, 4, 5]
  doAssert normalizePageSelection("1,4-6,12", 20) == @[1, 4, 5, 6, 12]
  doAssert normalizePageSelection("6,2,3,2-4", 20) == @[2, 3, 4, 6]

  expectValueError("", 10)
  expectValueError("1,", 10)
  expectValueError("4-2", 10)
  expectValueError("1,a", 10)
  expectValueError("-1", 10)

when isMainModule:
  main()
