# Phase 08: Testing Matrix And Acceptance Closure

## Goal

Validate the implementation against every acceptance criterion in `SPEC.md` with deterministic tests covering ordering, retries, backpressure, and shutdown semantics.

## Inputs

1. `SPEC.md` section 19
2. All prior phases
3. API docs used by implementation:
   - `docs/pdfium.md`
   - `docs/curl.md`
   - `docs/threading_channels.md`

## Steps

1. Create parser/normalization unit tests:
   - valid single pages and ranges,
   - duplicates and out-of-order input normalize correctly,
   - malformed syntax rejects,
   - out-of-bounds and empty result selection reject.

2. Create data-contract unit tests:
   - output JSON shape for `ok` and `error`,
   - error-message truncation,
   - attempt counting consistency (`1 .. 1 + MAX_RETRIES`).

3. Create scheduler policy tests with mocked network behavior:
   - retry on 429/5xx/timeout/transport,
   - no retry on 4xx except 429,
   - exponential backoff bounded by `RETRY_MAX_DELAY_MS`,
   - jitter applied (non-zero variation over repeated runs),
   - sliding window guard never schedules `seqId >= NEXT_TO_WRITE + WINDOW`.

4. Create ordering tests:
   - inject out-of-order completion events,
   - assert writer output remains strictly ordered by normalized page list,
   - assert exactly one line per selected page.

5. Create backpressure tests:
   - simulate slow/blocked stdout consumer (pipe with delayed reader),
   - assert process stalls safely without unbounded memory growth,
   - assert no internal deadlock while consumer eventually resumes.

6. Create renderer failure-path tests:
   - per-page render failure -> `PDF_ERROR`,
   - encode failure -> `ENCODE_ERROR`,
   - fatal document-open failure -> fatal exit `>2`.

7. Create end-to-end integration tests:
   - all pages success -> exit `0`,
   - mixed success/failure -> exit `2`,
   - fatal startup failures (missing API key, bad file path) -> exit `>2`.

8. Create stderr purity/security tests:
   - confirm stdout contains only JSONL,
   - confirm API key is never logged,
   - confirm bounded excerpts for HTTP/body errors.

9. Build acceptance checklist mapping:
   - one explicit test (or small test set) for each item in `SPEC.md` section 19.

10. Define CI run order:
   - fast unit tests first,
   - scheduler/backpressure/integration suite second,
   - fail-fast on ordering or contract regressions.

## Completion Criteria

1. Every acceptance criterion in `SPEC.md` section 19 has a passing test.
2. Ordering/backpressure/retry behavior is verified under deterministic and adverse conditions.
3. Final release candidate demonstrates correct exit codes and stdout/stderr separation.
