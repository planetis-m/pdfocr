type
  LogLevel* = enum
    info, warn, error, off

const configuredLogLevel =
  when defined(release):
    LogLevel.warn
  else:
    LogLevel.info

proc shouldLog(level: LogLevel): bool =
  configuredLogLevel != LogLevel.off and ord(level) >= ord(configuredLogLevel)

proc log(level: LogLevel; prefix: string; message: string) =
  if shouldLog(level):
    stderr.writeLine(prefix & message)

proc logInfo*(message: string) =
  log(info, "[info] ", message)

proc logWarn*(message: string) =
  log(warn, "[warn] ", message)

proc logError*(message: string) =
  log(error, "[error] ", message)
