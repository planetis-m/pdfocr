import std/strformat
import std/times
import ./config

proc logLine(level: string; message: string) =
  let tsMs = getTime().toUnix() * 1000
  echo &"{tsMs} [{level}] {message}"

proc logInfo*(message: string) =
  logLine("INFO", message)

proc logWarn*(message: string) =
  logLine("WARN", message)

proc logError*(message: string) =
  logLine("ERROR", message)

proc logConfigSnapshot*(cfg: Config) =
  logInfo("config " & $cfg)

type
  ProgressCounters* = object
    total*: int
    completed*: int
    success*: int
    failed*: int

proc `$`*(counters: ProgressCounters): string =
  "completed=" & $counters.completed & "/" & $counters.total &
    " success=" & $counters.success &
    " failed=" & $counters.failed

proc logProgress*(counters: ProgressCounters) =
  logInfo("progress " & $counters)
