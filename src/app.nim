import std/os
import pdfocr/orchestrator

proc main() =
  quit(runOrchestrator(commandLineParams()))

when isMainModule:
  main()
