import std/[json, os, osproc, strutils]
import pdfocr/errors

type
  RunResult = object
    exitCode: int
    stdoutText: string
    stderrText: string

proc runCommand(cmd: string): int =
  execShellCmd(cmd)

proc runApp(appPath: string; apiKey: string; mode: string): RunResult =
  let outPath = getTempDir().joinPath("pdfocr_phase08_purity.out")
  let errPath = getTempDir().joinPath("pdfocr_phase08_purity.err")
  let cmd =
    "LD_LIBRARY_PATH=" & quoteShell("third_party/pdfium/lib") &
    " DEEPINFRA_API_KEY=" & quoteShell(apiKey) &
    " PDFOCR_TEST_MODE=" & quoteShell(mode) &
    " " & quoteShell(appPath) &
    " " & quoteShell("tests/slides.pdf") &
    " --pages:" & quoteShell("1-5") &
    " > " & quoteShell(outPath) &
    " 2> " & quoteShell(errPath)

  result.exitCode = runCommand(cmd)
  result.stdoutText = if fileExists(outPath): readFile(outPath) else: ""
  result.stderrText = if fileExists(errPath): readFile(errPath) else: ""

proc main() =
  let appPath = getTempDir().joinPath("pdfocr_phase08_purity_app")
  doAssert runCommand(
    "nim c -d:testing -o:" & quoteShell(appPath) & " " & quoteShell("src/app.nim")
  ) == 0

  let secret = "SECRET_PHASE08_KEY"
  let run = runApp(appPath, secret, "mixed")
  doAssert run.exitCode == 2

  let lines = run.stdoutText.strip().splitLines()
  doAssert lines.len == 5
  for line in lines:
    let obj = parseJson(line)
    doAssert obj.hasKey("page")
    doAssert obj.hasKey("status")
    doAssert obj.hasKey("attempts")
    doAssert not line.startsWith("[info]")
    doAssert not line.startsWith("[error]")
    doAssert not line.startsWith("[warn]")

  doAssert run.stderrText.contains("[info]")
  doAssert run.stderrText.contains("completion:")
  doAssert not run.stdoutText.contains(secret)
  doAssert not run.stderrText.contains(secret)

  let longMsg = repeat("x", MAX_ERROR_MESSAGE_LEN + 1000)
  doAssert boundedErrorMessage(longMsg).len <= MAX_ERROR_MESSAGE_LEN

when isMainModule:
  main()
