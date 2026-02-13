import std/locks

var logLock: Lock
initLock(logLock)

proc log(level: string; message: string) =
  withLock(logLock):
    stderr.writeLine(level & message)

proc logInfo*(message: string) =
  log("[info] ", message)

proc logWarn*(message: string) =
  log("[warn] ", message)

proc logError*(message: string) =
  log("[error] ", message)
