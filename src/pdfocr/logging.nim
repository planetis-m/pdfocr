import std/locks

var logLock: Lock
type
  LogLevel* = enum
    info, warn, error, off

var configuredLogLevel = LogLevel.info
initLock(logLock)

proc setLogLevel*(level: LogLevel) =
  withLock(logLock):
    configuredLogLevel = level

proc getLogLevel*(): LogLevel =
  withLock(logLock):
    result = configuredLogLevel

proc shouldLog(level: LogLevel): bool =
  configuredLogLevel != LogLevel.off and ord(level) >= ord(configuredLogLevel)

proc log(level: LogLevel; prefix: string; message: string) =
  withLock(logLock):
    if shouldLog(level):
      stderr.writeLine(prefix & message)

proc logInfo*(message: string) =
  log(info, "[info] ", message)

proc logWarn*(message: string) =
  log(warn, "[warn] ", message)

proc logError*(message: string) =
  log(error, "[error] ", message)
