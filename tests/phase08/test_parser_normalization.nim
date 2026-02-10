import pdfocr/page_selection

template expectValueError(body: untyped) =
  block:
    var raised = false
    try:
      body
    except ValueError:
      raised = true
    doAssert raised

proc main() =
  doAssert normalizePageSelection("1", 10) == @[1]
  doAssert normalizePageSelection("3-5", 10) == @[3, 4, 5]
  doAssert normalizePageSelection("5, 1, 3-4, 4, 1", 10) == @[1, 3, 4, 5]
  doAssert normalizePageSelection(" 2 , 4 - 6 , 6 ", 10) == @[2, 4, 5, 6]

  expectValueError:
    discard normalizePageSelection("", 10)
  expectValueError:
    discard normalizePageSelection("a", 10)
  expectValueError:
    discard normalizePageSelection("3-", 10)
  expectValueError:
    discard normalizePageSelection("5-3", 10)
  expectValueError:
    discard normalizePageSelection("11", 10)
  expectValueError:
    discard normalizePageSelection("1", 0)

when isMainModule:
  main()
