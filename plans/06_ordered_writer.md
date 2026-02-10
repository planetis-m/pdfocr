# Phase 06: Ordered Writer (stdout JSONL Authority)

## Goal

Implement the writer execution unit that exclusively owns stdout, enforces strict `seq_id` order, and emits one JSON line per selected page.

## Inputs

1. `SPEC.md` sections 5, 6, 9, 11, 16
2. Contracts from `plans/03_runtime_contracts_and_channels.md`

## Steps

1. Implement writer thread entrypoint with inputs:
   - `writerInCh` (final `PageResult` messages),
   - immutable `selectedPages` mapping,
   - total selected count `N`,
   - shared atomics (`NEXT_TO_WRITE`, counters).

2. Initialize writer state:
   - `expectedSeq = 0`,
   - `bufferBySeq` map for out-of-order results,
   - local `okCount`, `errCount`.

3. Consume result messages:
   - block on `writerInCh.recv(...)`,
   - validate basic consistency (`seqId` range, mapped page number),
   - ignore/log duplicates if `seqId` already written or already buffered.

4. Buffer and flush in strict order:
   - insert result by `seqId`,
   - while `bufferBySeq` contains `expectedSeq`:
     - encode JSON object via `eminim`,
     - write exactly one line to stdout (`json + "\n"`),
     - increment local counters (`ok` or `error`),
     - increment `expectedSeq`,
     - atomically publish `NEXT_TO_WRITE = expectedSeq`.

5. Ensure output schema per page:
   - always include: `page`, `status`, `attempts`,
   - success includes `text`,
   - error includes `error_kind`, `error_message`, optional `http_status`.

6. Keep stdout pure:
   - no logs/progress/non-JSON text to stdout,
   - all writer diagnostics go to stderr.

7. Flush policy:
   - rely on line writes during streaming,
   - ensure explicit final stdout flush before writer exit.

8. Writer completion:
   - exit only when `expectedSeq == N`,
   - publish final summary (`okCount`, `errCount`) to orchestrator through shared state or join-result structure.

## API References Required In This Phase

1. `docs/threading_channels.md`:
   - `recv`

## Completion Criteria

1. Writer emits exactly `N` JSONL lines in ascending `seqId` order.
2. `NEXT_TO_WRITE` is updated immediately after each successful ordered write.
3. Only writer writes to stdout.
