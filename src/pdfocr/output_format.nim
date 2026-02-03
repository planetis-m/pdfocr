import std/[os, strformat, times, monotimes, streams]
import eminim
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

  ResultJson* = object
    page_id*: int
    page_number_user*: int
    text*: string
    error_kind*: string
    error_message*: string
    attempt_count*: int
    http_status*: int
    started_at_ms*: int64
    finished_at_ms*: int64

  ResultMetaJson* = object
    page_id*: int
    page_number_user*: int
    status*: string
    error_kind*: string
    error_message*: string
    attempt_count*: int
    http_status*: int
    started_at_ms*: int64
    finished_at_ms*: int64

  ConfigJson* = object
    max_inflight*: int
    high_water*: int
    low_water*: int
    producer_batch*: int
    connect_timeout_ms*: int
    total_timeout_ms*: int
    max_retries*: int
    retry_base_delay_ms*: int
    retry_max_delay_ms*: int
    multi_wait_max_ms*: int
    render_dpi*: int
    render_scale*: float
    jpeg_quality*: int
    ordering_mode*: string
    output_format*: string
    max_queued_image_bytes*: int

  PageSummaryJson* = object
    page_id*: int
    page_number_user*: int
    status*: string
    attempt_count*: int
    error_kind*: string
    http_status*: int

  RunManifestJson* = object
    input_file*: string
    input_checksum*: string
    page_start_user*: int
    page_end_user*: int
    page_range*: string
    config*: ConfigJson
    pages*: seq[PageSummaryJson]
    started_at_unix_ms*: int64
    finished_at_unix_ms*: int64

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

proc configToJson*(cfg: Config): ConfigJson =
  ConfigJson(
    max_inflight: cfg.maxInflight,
    high_water: cfg.highWater,
    low_water: cfg.lowWater,
    producer_batch: cfg.producerBatch,
    connect_timeout_ms: cfg.connectTimeoutMs,
    total_timeout_ms: cfg.totalTimeoutMs,
    max_retries: cfg.maxRetries,
    retry_base_delay_ms: cfg.retryBaseDelayMs,
    retry_max_delay_ms: cfg.retryMaxDelayMs,
    multi_wait_max_ms: cfg.multiWaitMaxMs,
    render_dpi: cfg.renderDpi,
    render_scale: cfg.renderScale,
    jpeg_quality: cfg.jpegQuality,
    ordering_mode: $cfg.orderingMode,
    output_format: $cfg.outputFormat,
    max_queued_image_bytes: cfg.maxQueuedImageBytes
  )

proc monoOffsetMs*(base: MonoTime; value: MonoTime): int64 =
  if value == MonoTime():
    return 0
  let delta = value - base
  result = int64(delta.inMilliseconds)

proc resultToJson*(res: Result; base: MonoTime): ResultJson =
  let errorKind = if res.status == rsFailure: $res.errorKind else: ""
  let errorMessage = if res.status == rsFailure: res.errorMessage else: ""
  ResultJson(
    page_id: res.pageId,
    page_number_user: res.pageNumberUser,
    text: res.text,
    error_kind: errorKind,
    error_message: errorMessage,
    attempt_count: res.attemptCount,
    http_status: res.httpStatus,
    started_at_ms: monoOffsetMs(base, res.startedAt),
    finished_at_ms: monoOffsetMs(base, res.finishedAt)
  )

proc resultToMetadataJson*(res: Result; base: MonoTime): ResultMetaJson =
  let errorKind = if res.status == rsFailure: $res.errorKind else: ""
  let errorMessage = if res.status == rsFailure: res.errorMessage else: ""
  ResultMetaJson(
    page_id: res.pageId,
    page_number_user: res.pageNumberUser,
    status: $res.status,
    error_kind: errorKind,
    error_message: errorMessage,
    attempt_count: res.attemptCount,
    http_status: res.httpStatus,
    started_at_ms: monoOffsetMs(base, res.startedAt),
    finished_at_ms: monoOffsetMs(base, res.finishedAt)
  )

proc manifestToJson*(manifest: RunManifest): RunManifestJson =
  var pages = newSeq[PageSummaryJson](manifest.pages.len)
  for i, page in manifest.pages:
    pages[i] = PageSummaryJson(
      page_id: page.pageId,
      page_number_user: page.pageNumberUser,
      status: $page.status,
      attempt_count: page.attemptCount,
      error_kind: page.errorKind,
      http_status: page.httpStatus
    )
  RunManifestJson(
    input_file: manifest.inputFile,
    input_checksum: manifest.inputChecksum,
    page_start_user: manifest.pageStartUser,
    page_end_user: manifest.pageEndUser,
    page_range: fmt"{manifest.pageStartUser}-{manifest.pageEndUser}",
    config: configToJson(manifest.config),
    pages: pages,
    started_at_unix_ms: manifest.startedAtUnixMs,
    finished_at_unix_ms: manifest.finishedAtUnixMs
  )

proc toJsonString*[T](value: T): string =
  var s = newStringStream()
  s.storeJson(value)
  result = s.data

# Work around eminim generic resolution for nested object sequences.
proc storeJson*(s: Stream; value: PageSummaryJson) =
  eminim.storeJson(s, value)

proc nowUnixMs*(): int64 =
  result = getTime().toUnix() * 1000
