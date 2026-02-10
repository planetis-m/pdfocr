import std/[json, os, osproc, sequtils, strutils]

type
  RunResult = object
    exitCode: int
    stdoutText: string
    stderrText: string

proc buildEnvPrefix(entries: seq[(string, string)]): string =
  var parts: seq[string] = @[]
  for (k, v) in entries:
    parts.add(k & "=" & quoteShell(v))
  parts.join(" ")

proc runCommand(cmd: string): int =
  execShellCmd(cmd)

proc runApp(appPath: string; envVars: seq[(string, string)]; args: seq[string]): RunResult =
  let outPath = getTempDir().joinPath("pdfocr_phase08_integration.out")
  let errPath = getTempDir().joinPath("pdfocr_phase08_integration.err")
  let argStr = args.mapIt(quoteShell(it)).join(" ")
  let envStr = buildEnvPrefix(envVars)
  let cmd =
    if envStr.len > 0:
      envStr & " " & quoteShell(appPath) & " " & argStr &
        " > " & quoteShell(outPath) & " 2> " & quoteShell(errPath)
    else:
      quoteShell(appPath) & " " & argStr &
        " > " & quoteShell(outPath) & " 2> " & quoteShell(errPath)

  result.exitCode = runCommand(cmd)
  result.stdoutText = if fileExists(outPath): readFile(outPath) else: ""
  result.stderrText = if fileExists(errPath): readFile(errPath) else: ""

proc main() =
  let appPath = getTempDir().joinPath("pdfocr_phase08_app")
  doAssert runCommand(
    "nim c -d:testing -o:" & quoteShell(appPath) & " " & quoteShell("src/app.nim")
  ) == 0

  let baseEnv = @[
    ("LD_LIBRARY_PATH", "third_party/pdfium/lib"),
    ("DEEPINFRA_API_KEY", "dummy")
  ]

  let allOk = runApp(appPath, baseEnv & @[("PDFOCR_TEST_MODE", "all_ok")], @[
    "tests/slides.pdf", "--pages", "1-3"
  ])
  doAssert allOk.exitCode == 0
  let allOkLines = allOk.stdoutText.strip().splitLines()
  doAssert allOkLines.len == 3
  for line in allOkLines:
    doAssert parseJson(line)["status"].getStr() == "ok"

  let mixed = runApp(appPath, baseEnv & @[("PDFOCR_TEST_MODE", "mixed")], @[
    "tests/slides.pdf", "--pages", "1-4"
  ])
  doAssert mixed.exitCode == 2
  let mixedLines = mixed.stdoutText.strip().splitLines()
  doAssert mixedLines.len == 4
  var okSeen = false
  var errSeen = false
  for line in mixedLines:
    let status = parseJson(line)["status"].getStr()
    if status == "ok":
      okSeen = true
    elif status == "error":
      errSeen = true
  doAssert okSeen and errSeen

  let missingKey = runApp(appPath, @[("LD_LIBRARY_PATH", "third_party/pdfium/lib")], @[
    "tests/slides.pdf", "--pages", "1"
  ])
  doAssert missingKey.exitCode > 2

  let badPath = runApp(appPath, baseEnv & @[("PDFOCR_TEST_MODE", "all_ok")], @[
    "tests/does-not-exist.pdf", "--pages", "1"
  ])
  doAssert badPath.exitCode > 2

when isMainModule:
  main()
