import std/[json, os, strformat, times, monotimes]
import ./[config, types]

type
  PageSummary* = object
    pageId*: int
    pageNumberUser*: int
    status*: ResultStatus
    attemptCount*: int
    errorKind*: string
    httpStatus*: int

  RunManifest* = object
    inputFile*: string
    inputChecksum*: string
    pageStartUser*: int
    pageEndUser*: int
    config*: Config
    pages*: seq[PageSummary]
    startedAtUnixMs*: int64
    finishedAtUnixMs*: int64

proc jsonlPath*(outputDir: string): string =
  outputDir.joinPath("results.jsonl")

proc manifestPath*(outputDir: string): string =
  outputDir.joinPath("manifest.json")

proc pageBaseName*(pageNumberUser: int): string =
  fmt"page_{pageNumberUser:04d}"

proc pageTextPath*(outputDir: string; pageNumberUser: int): string =
  outputDir.joinPath(pageBaseName(pageNumberUser) & ".txt")

proc pageMetaPath*(outputDir: string; pageNumberUser: int): string =
  outputDir.joinPath(pageBaseName(pageNumberUser) & ".json")

proc configToJson*(cfg: Config): JsonNode =
  result = %*{
    "max_inflight": cfg.maxInflight,
    "high_water": cfg.highWater,
    "low_water": cfg.lowWater,
    "producer_batch": cfg.producerBatch,
    "connect_timeout_ms": cfg.connectTimeoutMs,
    "total_timeout_ms": cfg.totalTimeoutMs,
    "max_retries": cfg.maxRetries,
    "retry_base_delay_ms": cfg.retryBaseDelayMs,
    "retry_max_delay_ms": cfg.retryMaxDelayMs,
    "multi_wait_max_ms": cfg.multiWaitMaxMs,
    "render_dpi": cfg.renderDpi,
    "render_scale": cfg.renderScale,
    "jpeg_quality": cfg.jpegQuality,
    "ordering_mode": $cfg.orderingMode,
    "output_format": $cfg.outputFormat,
    "max_queued_image_bytes": cfg.maxQueuedImageBytes
  }

proc monoOffsetMs*(base: MonoTime; value: MonoTime): int64 =
  if value == MonoTime():
    return 0
  let delta = value - base
  result = int64(delta.inMilliseconds)

proc resultToJson*(res: Result; base: MonoTime): JsonNode =
  let errorKind = if res.status == rsFailure: $res.errorKind else: ""
  let errorMessage = if res.status == rsFailure: res.errorMessage else: ""
  result = %*{
    "page_id": res.pageId,
    "page_number_user": res.pageNumberUser,
    "text": res.text,
    "error_kind": errorKind,
    "error_message": errorMessage,
    "attempt_count": res.attemptCount,
    "http_status": res.httpStatus,
    "started_at_ms": monoOffsetMs(base, res.startedAt),
    "finished_at_ms": monoOffsetMs(base, res.finishedAt)
  }

proc resultToMetadataJson*(res: Result; base: MonoTime): JsonNode =
  let errorKind = if res.status == rsFailure: $res.errorKind else: ""
  let errorMessage = if res.status == rsFailure: res.errorMessage else: ""
  result = %*{
    "page_id": res.pageId,
    "page_number_user": res.pageNumberUser,
    "status": $res.status,
    "error_kind": errorKind,
    "error_message": errorMessage,
    "attempt_count": res.attemptCount,
    "http_status": res.httpStatus,
    "started_at_ms": monoOffsetMs(base, res.startedAt),
    "finished_at_ms": monoOffsetMs(base, res.finishedAt)
  }

proc manifestToJson*(manifest: RunManifest): JsonNode =
  var pages = newSeq[JsonNode](manifest.pages.len)
  for i, page in manifest.pages:
    pages[i] = %*{
      "page_id": page.pageId,
      "page_number_user": page.pageNumberUser,
      "status": $page.status,
      "attempt_count": page.attemptCount,
      "error_kind": page.errorKind,
      "http_status": page.httpStatus
    }
  result = %*{
    "input_file": manifest.inputFile,
    "input_checksum": manifest.inputChecksum,
    "page_start_user": manifest.pageStartUser,
    "page_end_user": manifest.pageEndUser,
    "page_range": fmt"{manifest.pageStartUser}-{manifest.pageEndUser}",
    "config": configToJson(manifest.config),
    "pages": pages,
    "started_at_unix_ms": manifest.startedAtUnixMs,
    "finished_at_unix_ms": manifest.finishedAtUnixMs
  }

proc nowUnixMs*(): int64 =
  result = getTime().toUnix() * 1000
