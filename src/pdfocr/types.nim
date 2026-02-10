import std/[atomics, deques]
import threading/channels
import ./constants
import ./errors

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
    httpStatus*: int
    hasHttpStatus*: bool

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
    renderReqCh*: Chan[RenderRequest]
    renderOutCh*: Chan[RendererOutput]
    writerInCh*: Chan[PageResult]
    fatalCh*: Chan[FatalEvent]
    apiKey*: string

  WriterContext* = object
    selectedPages*: seq[int]
    writerInCh*: Chan[PageResult]
    fatalCh*: Chan[FatalEvent]

  FinalizationGuard* = object
    seen*: seq[bool]

# Shared atomics: NEXT_TO_WRITE is correctness-critical.
var
  NEXT_TO_WRITE*: Atomic[int]
  OK_COUNT*: Atomic[int]
  ERR_COUNT*: Atomic[int]
  RETRY_COUNT*: Atomic[int]
  INFLIGHT_COUNT*: Atomic[int]
  SCHEDULER_STOP_REQUESTED*: Atomic[bool]

proc resetSharedAtomics*() =
  NEXT_TO_WRITE.store(0, moRelaxed)
  OK_COUNT.store(0, moRelaxed)
  ERR_COUNT.store(0, moRelaxed)
  RETRY_COUNT.store(0, moRelaxed)
  INFLIGHT_COUNT.store(0, moRelaxed)
  SCHEDULER_STOP_REQUESTED.store(false, moRelaxed)

proc initRuntimeChannels*(): RuntimeChannels =
  RuntimeChannels(
    renderReqCh: newChan[RenderRequest](Positive(HIGH_WATER)),
    renderOutCh: newChan[RendererOutput](Positive(HIGH_WATER)),
    writerInCh: newChan[PageResult](Positive(WINDOW)),
    fatalCh: newChan[FatalEvent](Positive(4))
  )

proc initFinalizationGuard*(selectedCount: int): FinalizationGuard =
  if selectedCount < 0:
    raise newException(ValueError, "selectedCount must be >= 0")
  FinalizationGuard(seen: newSeq[bool](selectedCount))

proc tryFinalizeSeqId*(guard: var FinalizationGuard; seqId: SeqId): bool =
  if seqId < 0 or seqId >= guard.seen.len:
    return false
  if guard.seen[seqId]:
    return false
  guard.seen[seqId] = true
  true

proc tryRecvBatch*[T](channel: Chan[T]; target: var Deque[T]; maxItems: int): int =
  if maxItems <= 0:
    return 0
  while result < maxItems:
    var value: T
    if not channel.tryRecv(value):
      break
    target.addLast(value)
    inc result

proc flushPendingSends*[T](channel: Chan[T]; pending: var Deque[T]; maxItems: int = high(int)): int =
  if maxItems <= 0:
    return 0
  while result < maxItems and pending.len > 0:
    let nextValue = pending.peekFirst()
    if not channel.trySend(nextValue):
      break
    discard pending.popFirst()
    inc result

proc trySendOrBuffer*[T](channel: Chan[T]; value: T; pending: var Deque[T]; maxPending: int): bool =
  if channel.trySend(value):
    return true
  if maxPending <= 0 or pending.len >= maxPending:
    return false
  pending.addLast(value)
  true

# Channel payloads intentionally use value types / strings / byte sequences only.
