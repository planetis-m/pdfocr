import std/[os, osproc, streams, strutils]

const N = 120_000

proc main() =
  let harness = getTempDir().joinPath("pdfocr_phase08_writer_backpressure_harness")

  doAssert execShellCmd(
    "nim c -d:testing -o:" & quoteShell(harness) & " " &
    quoteShell("tests/phase08/harness_writer_backpressure.nim")
  ) == 0

  let p = startProcess(harness, options = {poUsePath})
  sleep(400)
  doAssert p.running()

  let outData = p.outputStream.readAll()
  let errData = p.errorStream.readAll()
  discard errData
  let code = p.waitForExit(120_000)
  doAssert code == 0
  doAssert outData.strip().splitLines().len == N

when isMainModule:
  main()
