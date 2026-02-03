import std/[strformat, times]
import ./config

proc logLine(level: string; message: string) =
  let ts = now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  echo &"{ts} [{level}] {message}"

proc logInfo*(message: string) =
  logLine("INFO", message)

proc logWarn*(message: string) =
  logLine("WARN", message)

proc logError*(message: string) =
  logLine("ERROR", message)

proc logConfigSnapshot*(cfg: Config) =
  logInfo(&"config maxInflight={cfg.maxInflight} highWater={cfg.highWater} lowWater={cfg.lowWater} " &
          &"producerBatch={cfg.producerBatch} connectTimeoutMs={cfg.connectTimeoutMs} " &
          &"totalTimeoutMs={cfg.totalTimeoutMs} maxRetries={cfg.maxRetries} " &
          &"retryBaseDelayMs={cfg.retryBaseDelayMs} retryMaxDelayMs={cfg.retryMaxDelayMs} " &
          &"multiWaitMaxMs={cfg.multiWaitMaxMs} renderDpi={cfg.renderDpi} " &
          &"renderScale={cfg.renderScale} jpegQuality={cfg.jpegQuality} " &
          &"orderingMode={cfg.orderingMode} outputFormat={cfg.outputFormat} " &
          &"maxQueuedImageBytes={cfg.maxQueuedImageBytes}")

type
  ProgressCounters* = object
    total*: int
    completed*: int
    success*: int
    failed*: int

proc logProgress*(counters: ProgressCounters) =
  logInfo(&"progress completed={counters.completed}/{counters.total} " &
          &"success={counters.success} failed={counters.failed}")
