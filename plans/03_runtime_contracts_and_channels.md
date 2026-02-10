# Phase 03: Runtime Contracts, Atomics, And Channel Topology

## Goal

Define all cross-thread message contracts, bounded channels, and shared atomic progress state before implementing thread logic.

## Inputs

1. `SPEC.md` sections 8, 9, 10, 11, 13, 16
2. `docs/threading_channels.md`

## Steps

1. Define strict message/value types in `types.nim`:
   - `RenderRequest`:
     - `seqId: int`
   - `RenderedTask`:
     - `seqId: int`
     - `page: int`
     - `webpBytes: seq[byte]`
     - `attempt: int` (starts at 1)
   - `RenderFailure`:
     - `seqId`, `page`, `errorKind`, `errorMessage`, `attempts=1`
   - `PageResult` (final writer contract):
     - `seqId`, `page`, `status`, `attempts`
     - success: `text`
     - failure: `errorKind`, `errorMessage`, optional `httpStatus`

2. Define channel payload union for renderer output:
   - one variant for successful `RenderedTask`,
   - one variant for immediate terminal render/encode failure.
   This allows renderer failures to flow through scheduler into writer with exactly one final result per page.

3. Define bounded channel graph with capacities from constants:
   - `renderReqCh: Chan[RenderRequest]` capacity `HIGH_WATER`
   - `renderOutCh: Chan[RendererOutput]` capacity `HIGH_WATER`
   - `writerInCh: Chan[PageResult]` capacity `WINDOW`
   - `fatalCh: Chan[FatalEvent]` small bounded capacity (for fatal thread errors)

4. Define shutdown/control messages:
   - renderer stop signal (`RenderRequest(kind=Stop)` or dedicated control channel),
   - optional scheduler stop/cancel signal via atomic flag.

5. Define shared atomics in one module:
   - `NEXT_TO_WRITE` (`int`, init `0`) correctness-critical,
   - diagnostics counters:
     - `OK_COUNT`
     - `ERR_COUNT`
     - `RETRY_COUNT`
     - `INFLIGHT_COUNT`

6. Enforce channel payload safety constraints:
   - no `JsonNode` on channels,
   - no mutable shared ref-heavy structures crossing threads,
   - serialized strings/byte arrays only at boundaries.

7. Define duplicate-result guard contract:
   - each `seqId` may be finalized once,
   - scheduler drops/logs duplicate finals (stderr warning),
   - writer still receives exactly one final result per `seqId`.

8. Add helper APIs for non-blocking queue draining:
   - wrappers around `tryRecv` loops for batch draining,
   - wrappers around `trySend` with bounded local buffering.

## API References Required In This Phase

1. `docs/threading_channels.md`:
   - `newChan`
   - `send`
   - `trySend`
   - `recv`
   - `tryRecv`
   - `peek` (diagnostics only)

## Completion Criteria

1. All channels and message types are defined and wired with bounded capacities.
2. `NEXT_TO_WRITE` and diagnostic atomics are available to all relevant threads.
3. Contracts guarantee no ref-heavy objects are sent through channels.
