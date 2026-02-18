import std/atomics
import threading/channels
import ./[errors, curl]

type
  SeqId* = int

  NetworkConfig* = object
    apiUrl*: string
    model*: string
    prompt*: string
    connectTimeoutMs*: int
    totalTimeoutMs*: int
    maxRetries*: int
    retryBaseDelayMs*: int
    retryMaxDelayMs*: int

  RenderConfig* = object
    renderScale*: float
    webpQuality*: float32

  RuntimeConfig* = object
    inputPath*: string
    apiKey*: string
    selectedPages*: seq[int] # seq_id -> selectedPages[seq_id]
    selectedCount*: int
    maxInflight*: int
    networkConfig*: NetworkConfig
    renderConfig*: RenderConfig

  OcrTaskKind* = enum
    otkPage,
    otkStop

  OcrTask* = object
    kind*: OcrTaskKind
    seqId*: SeqId
    page*: int
    webpBytes*: seq[byte]

  PageStatus* = enum
    psOk,
    psError

  PageResult* = object
    seqId*: SeqId
    page*: int
    status*: PageStatus
    attempts*: int
    text*: string
    kind*: ErrorKind
    errorMessage*: string
    httpStatus*: HttpCode

  NetworkWorkerContext* = object
    taskCh*: Chan[OcrTask]
    resultCh*: Chan[PageResult]
    apiKey*: string
    maxInflight*: int
    config*: NetworkConfig

# Shared atomics for diagnostics.
var
  RetryCount*: Atomic[int]

proc resetSharedAtomics*() =
  RetryCount.store(0, moRelaxed)

# Channel payloads intentionally use value types / strings / byte sequences only.
