# Phase 05: Network Scheduler/Worker (Windowed Dispatch + Retries)

## Goal

Implement the scheduler that enforces the sliding window, drives libcurl multi concurrency, retries retryable failures, and forwards final page results to the ordered writer.

## Inputs

1. `SPEC.md` sections 7, 8, 11, 12, 13, 15
2. `docs/curl.md`
3. `docs/threading_channels.md`
4. Contracts from `plans/03_runtime_contracts_and_channels.md`

## Steps

1. Build scheduler state model:
   - `nextSeqToRequestRender` pointer,
   - rendered-task ready buffer keyed by `seqId`,
   - retry priority queue (`readyAtMs`, task payload, attempt count),
   - active transfer map (`easyHandle -> requestContext`),
   - final-result pending buffer for writer backpressure (bounded).

2. Initialize curl handles:
   - create `CurlMulti` with `initMulti()`,
   - define request context object containing:
     - `seqId`, `page`, `attempt`,
     - response buffer string,
     - header list handle,
     - easy handle handle.

3. Enforce sliding-window eligibility at every schedule point:
   - read atomic `NEXT_TO_WRITE`,
   - compute `windowLimitExclusive = NEXT_TO_WRITE + WINDOW`,
   - never schedule dispatch/retry for `seqId >= windowLimitExclusive`.

4. Implement render-demand refill policy:
   - if scheduler-side buffered rendered work drops below `LOW_WATER`, request more renders up to `HIGH_WATER`,
   - only request `seqId` values within the active window,
   - send `RenderRequest` over `renderReqCh` using `trySend` in loop with bounded retries.

5. Drain renderer outputs frequently:
   - use `tryRecv(renderOutCh, ...)` batch loop,
   - success tasks enter dispatch buffer,
   - renderer terminal failures are converted to final `PageResult` and routed to writer path (no network attempt).

6. Dispatch HTTP requests while capacity exists:
   - continue while `inflight < MAX_INFLIGHT` and eligible tasks are ready,
   - base64-encode `webpBytes` during request creation (not earlier),
   - build OpenAI-compatible JSON body via `eminim` with:
     - `model = "allenai/olmOCR-2-7B-1025"`
     - text instruction + `data:image/webp;base64,...` image URL.

7. Configure each easy handle (per request):
   - `setUrl(API_URL)`
   - `setWriteCallback(...)` to append response bytes into context buffer
   - `setPostFields(jsonBody)`
   - `setHeaders(...)` with:
     - `Authorization: Bearer ${DEEPINFRA_API_KEY}`
     - `Content-Type: application/json`
   - `setTimeoutMs(TOTAL_TIMEOUT_MS)`
   - `setConnectTimeoutMs(CONNECT_TIMEOUT_MS)`
   - `setSslVerify(true, true)`
   - `setAcceptEncoding("gzip, deflate")`
   - `setPrivate(pointerToContext)`
   - `addHandle(multi, easy)`

8. Drive non-blocking multi loop:
   - call `perform(multi)` repeatedly,
   - call `poll(multi, MULTI_WAIT_MAX_MS)`,
   - consume completions with `tryInfoRead(...)`,
   - for each completed transfer: `removeHandle(multi, easy)` and evaluate outcome.

9. Classify completion outcomes:
   - transport/curl errors -> `NETWORK_ERROR` or `TIMEOUT` (based on curl code),
   - HTTP 429 -> `RATE_LIMIT`,
   - HTTP 5xx -> retryable `HTTP_ERROR`,
   - HTTP 4xx (except 429) -> terminal `HTTP_ERROR`,
   - HTTP 2xx parse failure -> `PARSE_ERROR`,
   - HTTP 2xx valid body -> success text from `choices[0].message.content`.

10. Implement retry policy:
   - retry only for `RATE_LIMIT`, `TIMEOUT`, retryable `NETWORK_ERROR`, and HTTP 5xx,
   - stop when attempts reach `1 + MAX_RETRIES`,
   - backoff:
     - `raw = RETRY_BASE_DELAY_MS * 2^(attempt-1)`
     - `delay = min(RETRY_MAX_DELAY_MS, raw) + jitter`
   - increment `RETRY_COUNT` atomic on each scheduled retry.

11. Implement writer-path backpressure handling:
   - first try `trySend(writerInCh, result)`,
   - if full, store in local pending buffer,
   - keep pending buffer bounded to `WINDOW + MAX_INFLIGHT`,
   - while pending buffer non-empty, prioritize flushing to writer before dispatching additional work.

12. Maintain diagnostics atomics:
   - set `INFLIGHT_COUNT` whenever active handle count changes,
   - do not use diagnostics counters for correctness decisions.

13. Termination condition:
   - scheduler exits only when:
     - all `N` `seqId`s have terminal final results,
     - no active curl transfers,
     - retry queue empty,
     - pending writer buffer drained.
   - send renderer stop signal when no further render requests are possible/needed.

## API References Required In This Phase

1. `docs/curl.md`:
   - `initMulti`
   - `initEasy`
   - `setUrl`
   - `setWriteCallback`
   - `setPostFields`
   - `setHeaders`
   - `setTimeoutMs`
   - `setConnectTimeoutMs`
   - `setSslVerify`
   - `setAcceptEncoding`
   - `setPrivate`
   - `getPrivate`
   - `addHandle`
   - `removeHandle`
   - `perform` (multi)
   - `poll`
   - `tryInfoRead`
   - `responseCode`
   - `reset` (if easy-handle reuse is implemented)

2. `docs/threading_channels.md`:
   - `tryRecv`
   - `trySend`
   - `send`

## Completion Criteria

1. Sliding-window constraint is enforced in all scheduling/retry paths.
2. Scheduler maintains stable in-flight concurrency up to `MAX_INFLIGHT` when eligible work exists.
3. Retry/backoff behavior matches spec and is jittered/capped.
4. Scheduler never blocks indefinitely on writer channel sends.
