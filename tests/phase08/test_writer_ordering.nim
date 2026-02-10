import std/[json, os, osproc, strutils]

proc main() =
  let harness = getTempDir().joinPath("pdfocr_phase08_writer_ordering_harness")
  let outPath = getTempDir().joinPath("pdfocr_phase08_writer_ordering.out")
  let errPath = getTempDir().joinPath("pdfocr_phase08_writer_ordering.err")

  doAssert execShellCmd(
    "nim c -d:testing -o:" & quoteShell(harness) & " " &
    quoteShell("tests/phase08/harness_writer_out_of_order.nim")
  ) == 0

  doAssert execShellCmd(
    quoteShell(harness) & " > " & quoteShell(outPath) & " 2> " & quoteShell(errPath)
  ) == 0

  let lines = readFile(outPath).strip().splitLines()
  doAssert lines.len == 3
  doAssert parseJson(lines[0])["page"].getInt() == 2
  doAssert parseJson(lines[1])["page"].getInt() == 4
  doAssert parseJson(lines[2])["page"].getInt() == 6

when isMainModule:
  main()
