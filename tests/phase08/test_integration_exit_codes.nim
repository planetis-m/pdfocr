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

proc runApp(appPath: string; envVars: seq[(string, string)]; args: seq[string];
    workDir: string = "."): RunResult =
  let outPath = getTempDir().joinPath("pdfocr_phase08_integration.out")
  let errPath = getTempDir().joinPath("pdfocr_phase08_integration.err")
  let argStr = args.mapIt(quoteShell(it)).join(" ")
  let envStr = buildEnvPrefix(envVars)
  let runCmd =
    if envStr.len > 0:
      envStr & " " & quoteShell(appPath) & " " & argStr &
        " > " & quoteShell(outPath) & " 2> " & quoteShell(errPath)
    else:
      quoteShell(appPath) & " " & argStr &
        " > " & quoteShell(outPath) & " 2> " & quoteShell(errPath)
  let cmd = "cd " & quoteShell(workDir) & " && " & runCmd

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
  let isolatedDir = getTempDir().joinPath("pdfocr_phase08_no_config")
  createDir(isolatedDir)
  let slidesPdfPath = absolutePath("tests/slides.pdf")

  let networkRun = runApp(appPath, baseEnv, @[
    "tests/slides.pdf", "--pages:1-3"
  ])
  doAssert networkRun.exitCode == 2
  let networkLines = networkRun.stdoutText.strip().splitLines()
  doAssert networkLines.len == 3
  var errSeen = false
  for line in networkLines:
    let status = parseJson(line)["status"].getStr()
    doAssert status == "ok" or status == "error"
    if status == "error":
      errSeen = true
  doAssert errSeen

  let missingKey = runApp(appPath, @[("LD_LIBRARY_PATH", "third_party/pdfium/lib")], @[
    slidesPdfPath, "--pages:1"
  ], isolatedDir)
  doAssert missingKey.exitCode > 2

  let missingKeyAllPages = runApp(appPath, @[("LD_LIBRARY_PATH", "third_party/pdfium/lib")], @[
    slidesPdfPath, "--all-pages"
  ], isolatedDir)
  doAssert missingKeyAllPages.exitCode > 2

  let conflictingSelection = runApp(appPath, baseEnv, @[
    "tests/slides.pdf", "--pages:1", "--all-pages"
  ])
  doAssert conflictingSelection.exitCode > 2

  let badPath = runApp(appPath, baseEnv, @[
    "tests/does-not-exist.pdf", "--pages:1"
  ])
  doAssert badPath.exitCode > 2

when isMainModule:
  main()
