import std/[atomics, deques]
import threading/channels
import ./[constants, errors]

type
  SeqId* = int

  RuntimeConfig* = object
    inputPath*: string
    apiKey*: string
    selectedPages*: seq[int] # seq_id -> selectedPages[seq_id]
    selectedCount*: int

  RenderRequestKind* = enum
    rrkPage,
    rrkStop

  RenderRequest* = object
    kind*: RenderRequestKind
    seqId*: SeqId

  RenderedTask* = object
    seqId*: SeqId
    page*: int
    webpBytes*: seq[byte]
    attempt*: int # starts at 1

  RenderFailure* = object
    seqId*: SeqId
    page*: int
    errorKind*: ErrorKind
    errorMessage*: string
    attempts*: int

  RendererOutputKind* = enum
    rokRenderedTask,
    rokRenderFailure

  RendererOutput* = object
    case kind*: RendererOutputKind
    of rokRenderedTask:
      task*: RenderedTask
    of rokRenderFailure:
      failure*: RenderFailure

  PageStatus* = enum
    psOk,
    psError

  PageResult* = object
    seqId*: SeqId
    page*: int
    status*: PageStatus
    attempts*: int
    text*: string
    errorKind*: ErrorKind
    errorMessage*: string
    httpStatus*: HttpCode

  FatalEventSource* = enum
    fesRenderer,
    fesScheduler,
    fesWriter,
    fesOrchestrator

  FatalEvent* = object
    source*: FatalEventSource
    errorKind*: ErrorKind
    message*: string

  RuntimeChannels* = object
    renderReqCh*: Chan[RenderRequest]   # capacity = HIGH_WATER
    renderOutCh*: Chan[RendererOutput]  # capacity = HIGH_WATER
    writerInCh*: Chan[PageResult]       # capacity = WINDOW
    fatalCh*: Chan[FatalEvent]          # small bounded channel

  RendererContext* = object
    pdfPath*: string
    selectedPages*: seq[int]
    renderReqCh*: Chan[RenderRequest]
    renderOutCh*: Chan[RendererOutput]
    fatalCh*: Chan[FatalEvent]

  SchedulerContext* = object
    selectedCount*: int
    selectedPages*: seq[int]
    renderReqCh*: Chan[RenderRequest]
    renderOutCh*: Chan[RendererOutput]
    writerInCh*: Chan[PageResult]
    fatalCh*: Chan[FatalEvent]
    apiKey*: string

  WriterContext* = object
    selectedCount*: int
    selectedPages*: seq[int]
    writerInCh*: Chan[PageResult]
    fatalCh*: Chan[FatalEvent]

  FinalizationGuard* = object
    seen*: seq[bool]

# Shared atomics: NEXT_TO_WRITE is correctness-critical.
var
  NextToWrite*: Atomic[int]
  OkCount*: Atomic[int]
  ErrCount*: Atomic[int]
  RetryCount*: Atomic[int]
  InflightCount*: Atomic[int]
  SchedulerStopRequested*: Atomic[bool]

proc resetSharedAtomics*() =
  NextToWrite.store(0, moRelaxed)
  OkCount.store(0, moRelaxed)
  ErrCount.store(0, moRelaxed)
  RetryCount.store(0, moRelaxed)
  InflightCount.store(0, moRelaxed)
  SchedulerStopRequested.store(false, moRelaxed)

proc initRuntimeChannels*(): RuntimeChannels =
  result = RuntimeChannels(
    renderReqCh: newChan[RenderRequest](HighWater),
    renderOutCh: newChan[RendererOutput](HighWater),
    writerInCh: newChan[PageResult](Window),
    fatalCh: newChan[FatalEvent](4)
  )

proc initFinalizationGuard*(selectedCount: Positive): FinalizationGuard =
  result = FinalizationGuard(seen: newSeq[bool](selectedCount))

proc tryFinalizeSeqId*(guard: var FinalizationGuard; seqId: SeqId): bool =
  if seqId < 0 or seqId >= guard.seen.len:
    result = false
  elif guard.seen[seqId]:
    result = false
  else:
    guard.seen[seqId] = true
    result = true

proc tryRecvBatch*[T](channel: Chan[T]; target: var Deque[T]; maxItems: int): int =
  result = 0
  if maxItems > 0:
    while result < maxItems:
      var value: T
      if not channel.tryRecv(value):
        break
      target.addLast(value)
      inc result

proc flushPendingSends*[T](channel: Chan[T]; pending: var Deque[T]; maxItems: int = high(int)): int =
  result = 0
  if maxItems > 0:
    while result < maxItems and pending.len > 0:
      let nextValue = pending.peekFirst()
      if not channel.trySend(nextValue):
        break
      discard pending.popFirst()
      inc result

proc trySendOrBuffer*[T](channel: Chan[T]; value: T; pending: var Deque[T]; maxPending: int): bool =
  if channel.trySend(value):
    result = true
  elif maxPending <= 0 or pending.len >= maxPending:
    result = false
  else:
    pending.addLast(value)
    result = true

# Channel payloads intentionally use value types / strings / byte sequences only.
