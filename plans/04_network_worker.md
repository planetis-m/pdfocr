# Phase 4: Network Worker (curl multi, retries, concurrency)

## Goals
- Implement the high-throughput, stable-concurrency HTTP layer with bounded queues and retry policy.
- Use libcurl multi interface to maintain `MAX_INFLIGHT` requests.

## Steps
1. Implement `src/pdfocr/network_worker.nim` with a dedicated worker thread that owns:
   - `CurlMulti` handle, a pool of `CurlEasy` handles (size = `MAX_INFLIGHT`).
   - Reservoir queue, delayed retry queue (min-heap by next time), and `pending_results` buffer.

2. Initialize curl handles:
   - `initMulti()` for the multi handle.
   - For each easy handle: `initEasy()`, set TLS verification via `setSslVerify(true, true)`.
   - Preconfigure Accept-Encoding if desired using `setAcceptEncoding`.

3. Implement request construction for DeepInfra:
   - Build JSON body with base64 JPEG and model `allenai/olmOCR-2-7B-1025` per SPEC §9.8.
   - Set headers with `CurlSlist`: `Authorization: Bearer ...`, `Content-Type: application/json`.
   - Use `setUrl`, `setPostFields`, `setHeaders`, `setTimeoutMs`, `setConnectTimeoutMs`, `setWriteCallback`.
   - Store per-request state via `setPrivate` (task pointer or index).

4. Reservoir + refill policy (SPEC §9.2):
   - When `reservoir.size < LOW_WATER`, drain all immediately-available `TaskBatch` messages and refill to `HIGH_WATER`.
   - Never block waiting for a full batch.

5. Dispatch policy (SPEC §9.3):
   - If any easy handles are free and reservoir has tasks, assign tasks and `addHandle`.
   - Maintain near-`MAX_INFLIGHT` in-flight whenever tasks exist.

6. Main loop with curl multi:
   - Use `poll(timeoutMs)` where `timeoutMs = min(MULTI_WAIT_MAX_MS, time_until_next_retry)`.
   - Call `perform(multi)` until it returns no immediate work.
   - Harvest completions using `tryInfoRead` and handle each completion:
     - Get HTTP status via `responseCode`.
     - Parse response JSON, extract OCR text.
     - On success emit `Result`.
     - On retryable error (429/5xx/timeout/transfer): schedule backoff + jitter.
     - On non-retryable 4xx: emit failure.
     - Always `removeHandle` and `reset` easy handle for reuse.

7. Retry scheduling:
   - Implement exponential backoff with jitter between `RETRY_BASE_DELAY_MS` and `RETRY_MAX_DELAY_MS`.
   - If `attempt > MAX_RETRIES`, emit final failure.
   - Move due retries from delayed queue back into reservoir each loop.

8. Output non-blocking requirement (SPEC §9.6):
   - Send results via output channel using non-blocking send.
   - If channel is full, enqueue into `pending_results` and keep the curl loop running.
   - Periodically flush `pending_results`.

9. Shutdown conditions (SPEC §11):
   - After `InputDone` and when reservoir, delayed queue, in-flight, and `pending_results` are empty, send `OutputDone` and exit.

## API References
- Curl multi: `pdfocr.curl.initMulti`, `addHandle`, `removeHandle`, `perform`, `poll`, `tryInfoRead` (docs/curl.md)
- Curl easy: `initEasy`, `setUrl`, `setPostFields`, `setHeaders`, `setTimeoutMs`, `setConnectTimeoutMs`, `setSslVerify`, `setWriteCallback`, `responseCode`, `reset`, `setPrivate`, `getPrivate`, `close` (docs/curl.md)
- Curl headers: `CurlSlist.addHeader`, `free` (docs/curl.md)
