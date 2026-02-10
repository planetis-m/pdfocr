import std/strutils

proc logInfo*(message: string) =
  stderr.writeLine("[info] " & message.strip())

proc logWarn*(message: string) =
  stderr.writeLine("[warn] " & message.strip())

proc logError*(message: string) =
  stderr.writeLine("[error] " & message.strip())
