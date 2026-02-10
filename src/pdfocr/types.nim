import std/atomics
import threading/channels
import ./errors

type
  SeqId* = int

  RuntimeConfig* = object
    inputPath*: string
    apiKey*: string
    selectedPages*: seq[int] # seq_id -> selectedPages[seq_id]
    selectedCount*: int

  PageStatus* = enum
    psOk,
    psError

  RenderRequest* = object
    seqId*: SeqId

  RenderedTask* = object
    seqId*: SeqId
    page*: int
    webpBytes*: seq[byte]
    attempt*: int

  PageResult* = object
    seqId*: SeqId
    page*: int
    status*: PageStatus
    attempts*: int
    text*: string
    errorKind*: ErrorKind
    errorMessage*: string
    httpStatus*: int
    hasHttpStatus*: bool

  ProgressState* = object
    nextToWrite*: Atomic[int]
    okCount*: Atomic[int]
    errCount*: Atomic[int]
    retryCount*: Atomic[int]
    inflightCount*: Atomic[int]

  RendererContext* = object
    selectedPages*: seq[int]
    requestChan*: Chan[RenderRequest]
    renderedChan*: Chan[RenderedTask]
    resultChan*: Chan[PageResult]

  SchedulerContext* = object
    renderRequestChan*: Chan[RenderRequest]
    renderedChan*: Chan[RenderedTask]
    resultChan*: Chan[PageResult]
    apiKey*: string
    progress*: ptr ProgressState

  WriterContext* = object
    selectedPages*: seq[int]
    resultChan*: Chan[PageResult]
    progress*: ptr ProgressState

# Keep channel payloads value-like. JSON crosses thread boundaries as serialized string.
