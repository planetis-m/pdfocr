# Phase 6: Observability, Shutdown Semantics, and Tests

## Goals
- Implement logging, metrics, and shutdown behavior per SPEC §11–§13.
- Add tests for critical invariants and error paths.

## Steps
1. Logging and metrics:
   - Emit startup config snapshot (without API key).
   - Log periodic progress: completed pages, success/failure, in-flight, reservoir size, retry queue size.
   - Log errors with page id, attempt, http status/curl error, and bounded response excerpt.

2. Shutdown semantics:
   - Ensure normal completion when producer `InputDone` + network worker drained + output done.
   - Propagate fatal errors (PDF open, missing API key) to main and exit non-zero.
   - Optional: handle SIGINT by stopping producer and deciding whether to drain or abort inflight transfers.

3. Result integrity checks:
   - Ensure each selected page yields exactly one final result (success or failure).
   - Exit code `0` only if all pages succeed.

4. Tests (non-network where possible):
   - Page range parsing and validation logic.
   - Ordering buffer correctness in output stage.
   - Retry backoff calculation and jitter bounds.
   - Reservoir refill logic with mocked input batches.

## API References
- Uses shared types, logging, and pipeline modules built in earlier phases.
