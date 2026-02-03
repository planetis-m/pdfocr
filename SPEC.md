# Specification: High-Throughput PDF Slide OCR Extractor (DeepInfra olmOCR)

## 1. Purpose and Scope

This system extracts text from selected pages of a PDF (typically lecture slides) by rendering pages to images, sending them to the DeepInfra `allenai/olmOCR-2-7B-1025` model, and writing OCR results to disk.

The system is optimized for **overall throughput** rather than per-page latency. It is designed to run as a batch-processing tool with bounded memory usage, robust retry behavior, and stable concurrency over the full document.

---

## 2. Goals

1. **High throughput** across large page ranges.
2. **Stable concurrency** in the network layer (avoid concurrency “tail-off” behavior).
3. **Bounded memory usage** via explicit backpressure and queue sizing.
4. **Robustness** to transient network errors and HTTP 429/5xx responses.
5. **Deadlock-free operation** via one-way dataflow and explicit avoidance of blocking critical progress loops.
6. **Deterministic and reviewable behavior** with well-defined states and shutdown semantics.

---

## 3. Non-Goals

1. Real-time/interactive per-page latency optimization.
2. Perfect OCR accuracy tuning beyond correct request formatting and stable image production.
3. Distributed execution across machines.
4. UI beyond CLI (unless specified separately).

---

## 4. Inputs, Outputs, and CLI

### 4.1 Inputs
- `pdf_path`: path to a local PDF file.
- `page_range`: inclusive range, e.g. `1-10` (user-visible page numbering), validated against PDF page count.
- `deepinfra_api_key`: provided via environment variable or config file.
- Optional: output directory path, run metadata, and performance-related knobs (see §6).

### 4.2 Outputs
- Per-page OCR result written to disk.
- A run manifest (recommended) containing:
  - input file name and checksum (optional)
  - page range
  - configuration snapshot
  - per-page status summary (success/failure/attempt count)
  - timing summary

### 4.3 Output Format
The implementation SHALL support at least one of:
- **JSON Lines**: one JSON object per page result, named `results.jsonl`, or
- **One file per page**: e.g. `page_0001.txt` plus `page_0001.json` metadata.

The output MUST include:
- `page_index` (0-based internal index and/or 1-based user index)
- OCR text (if success)
- error information (if failed)
- attempt count
- HTTP status (if available)
- timestamps (start/end, optional but recommended)

### 4.4 Exit Codes
- `0`: all pages processed successfully
- non-zero: one or more pages failed or a fatal initialization/runtime error occurred

---

## 5. Core Architecture

The system is a **three-stage pipeline** with bounded queues:

1. **Producer Stage (Render/Encode)**  
   Reads PDF pages using PDFium, renders each selected page, encodes to JPEG, and packages page tasks.

2. **Network Worker Stage (OCR Requests)**  
   A dedicated thread drives `libcurl` multi interface (`curl_multi_*`) to execute concurrent HTTP requests to DeepInfra. It maintains stable concurrency using an internal task reservoir and watermark-based refilling.

3. **Output Stage (Disk Writer)**  
   A dedicated thread writes results to disk and optionally enforces ordering.

### 5.1 Thread Ownership and Responsibilities
- The **producer thread** owns PDFium objects and image encoding resources.
- The **network worker thread** exclusively owns:
  - `CURLM*` multi handle
  - pool of `CURL*` easy handles
  - request/response buffers associated with each easy handle
- The **output thread** exclusively owns file I/O.

No thread may access another thread’s owned objects directly; communication is message-based over channels.

---

## 6. Configuration Parameters

### 6.1 Concurrency
- `MAX_INFLIGHT` (default: 50; range: 1–200)
  - Maximum simultaneous DeepInfra requests for the model.
  - MUST NOT exceed 200 unless the account limit is known to be higher.

### 6.2 Task Reservoir Sizing (Throughput Stability)
- `HIGH_WATER = MAX_INFLIGHT * K` (default `K=4`)
- `LOW_WATER  = MAX_INFLIGHT * M` (default `M=1`)
- Requirements:
  - `HIGH_WATER >= LOW_WATER >= MAX_INFLIGHT`
  - `K >= 2` is recommended to absorb burstiness.

### 6.3 Producer Batching
- Producer emits vectors (batches) of tasks into the input channel.
- `PRODUCER_BATCH = HIGH_WATER - LOW_WATER` by default, but may be smaller if memory constraints require it.

### 6.4 Timeouts and Retries
- `CONNECT_TIMEOUT_MS` (default: 10_000)
- `TOTAL_TIMEOUT_MS` per request (default: 120_000; configurable)
- `MAX_RETRIES` (default: 5)
- `RETRY_BASE_DELAY_MS` (default: 500)
- `RETRY_MAX_DELAY_MS` (default: 20_000)
- Retry jitter MUST be applied.

### 6.5 Curl Wait Behavior
- Network worker uses `curl_multi_poll()` (or `curl_multi_wait()`).
- `MULTI_WAIT_MAX_MS` (default: 250–1000ms; configurable)
  - MUST be finite to ensure periodic checks for new tasks and retry timers.

### 6.6 Memory Budgeting (Guideline)
Memory is dominated by queued image payloads. The system SHOULD provide:
- `MAX_QUEUED_IMAGE_BYTES` (optional hard limit), enforced by adjusting channel capacity and/or producer blocking.

---

## 7. Data Model and Channels

### 7.1 Task Object
A `Task` represents a single page OCR request:
- `page_id`: stable identifier (e.g., 0-based index in the selected range)
- `page_number_user`: original 1-based page number (optional, for reporting)
- `jpeg_bytes`: byte array (preferred storage format in queues)
- `attempt`: integer, starts at 0
- `created_time`: monotonic timestamp (recommended)

**Note:** Base64 encoding SHOULD be done when constructing the HTTP body (inside the network worker) to reduce queued memory expansion.

### 7.2 Result Object
- `page_id`
- `status`: success/failure
- `text` (if success)
- `error_kind` and `error_message` (if failure)
- `http_status` (if available)
- `attempt_count`
- `timings` (optional but recommended)

### 7.3 Channels

#### Input Channel (Producer → Network Worker)
- Message type:
  - `TaskBatch(Vec<Task>)`
  - `InputDone`
- Capacity: fixed, chosen to bound memory.
- Backpressure: producer blocks when full.

#### Output Channel (Network Worker → Output Thread)
- Message type:
  - `PageResult(Result)`
  - `OutputDone`
- Capacity: fixed.
- **Critical requirement:** the network worker MUST NOT block indefinitely on output sends (see §9.6).

---

## 8. Producer Stage: Rendering and Encoding

### 8.1 Requirements
1. Open PDF with PDFium.
2. Validate page range.
3. For each page in range:
   - Render page to pixmap at configured resolution (DPI or scale).
   - Encode to JPEG with configured quality.
   - Construct `Task`.
4. Aggregate tasks into batches and send to input channel.
5. After last task, send `InputDone`.

### 8.2 Rendering/Encoding Controls (Recommended)
- `RENDER_DPI` or scale factor.
- `JPEG_QUALITY` (e.g., 70–90).
These affect token usage and OCR accuracy/cost; must be configurable.

### 8.3 Producer Backpressure
Producer MUST obey input channel backpressure. If the input channel is full:
- producer blocks and does not render additional pages, bounding memory.

---

## 9. Network Worker Stage (Core Throughput Logic)

### 9.1 Overview
The network worker maintains:
- An **easy handle pool** of size `MAX_INFLIGHT`
- A **reservoir queue** of pending tasks
- A **delayed-retry queue** keyed by next eligible time
- A **pending-results buffer** to avoid blocking on output

The worker continuously refills the reservoir and dispatches tasks onto free handles, ensuring the number of in-flight requests stays near `MAX_INFLIGHT` whenever work remains.

### 9.2 Reservoir and Watermark Refill Policy
- The worker monitors `reservoir.size()`.
- When `reservoir.size() < LOW_WATER`, it SHALL attempt to refill up to `HIGH_WATER` by draining as many `TaskBatch` messages from the input channel as are immediately available.
- Refill MUST NOT depend on completion of any particular group of tasks.
- The worker MUST accept and store partial refills; it MUST NOT wait to “fill a batch.”

### 9.3 Dispatch Policy (Saturation)
Whenever free handles exist:
- Pop tasks from `reservoir` and start requests until either:
  - no free handles remain, or
  - `reservoir` is empty.

This dispatch step SHALL be performed repeatedly throughout execution, including after each completion event and after each refill attempt.

### 9.4 Retry Scheduling
If a request fails with a retryable condition (see §9.5), the task is rescheduled:
- `attempt += 1`
- if `attempt > MAX_RETRIES`: produce a final failure result
- else compute `next_time = now + backoff(attempt) + jitter`
- push into delayed-retry queue

When `now >= next_time`, delayed tasks are moved back into the reservoir.

### 9.5 HTTP Handling Rules

#### 9.5.1 Success
- HTTP 2xx with a parseable response body yielding OCR text ⇒ emit success result.

#### 9.5.2 429 Too Many Requests
- Treated as retryable.
- Backoff MUST be applied (exponential + jitter).
- The system MAY optionally reduce effective concurrency if sustained 429s occur (adaptive throttling), but this is not required if stable operation is achieved by `MAX_INFLIGHT <= 200` and backoff.

#### 9.5.3 5xx
- Treated as retryable (subject to `MAX_RETRIES`).

#### 9.5.4 4xx (except 429)
- Treated as non-retryable by default.
- Emit failure result with status and body excerpt for diagnostics.

#### 9.5.5 Network/TLS/Timeout Errors
- Retryable up to `MAX_RETRIES`.

### 9.6 Output Non-Blocking Requirement
The network worker MUST NOT block its main progress loop on writing results to the output channel.

Required behavior:
- If the output channel is full, the worker SHALL enqueue results into an internal `pending_results` queue and continue driving `curl_multi_*` to completion.
- The worker SHALL periodically attempt to flush `pending_results` to the output channel (non-blocking or bounded blocking).

This prevents throughput collapse and ensures in-flight requests continue to be processed.

### 9.7 Curl Multi Loop Requirements

#### 9.7.1 Waiting
The worker SHALL call `curl_multi_poll()` with a finite timeout:
- `timeout_ms = min(MULTI_WAIT_MAX_MS, time_until_next_retry_due)`
- This ensures it wakes to:
  - check for newly arrived tasks (without requiring external wake FDs)
  - schedule due retries promptly

#### 9.7.2 Progress
After wait, the worker SHALL call `curl_multi_perform()` until it returns no immediate work.

#### 9.7.3 Completion Harvesting
The worker SHALL drain all available messages from `curl_multi_info_read()` and for each completed easy handle:
- determine outcome (HTTP status, curl code)
- parse response if applicable
- emit result or schedule retry
- remove handle from multi
- reset/reuse handle (keep-alive enabled as appropriate)

### 9.8 Request Construction Requirements (DeepInfra)
Each request SHALL include:
- Authorization header with API key
- Model identifier `allenai/olmOCR-2-7B-1025`
- Input payload containing the page image (Base64-encoded JPEG) in the format required by the DeepInfra API for the model
- Any model parameters required for OCR extraction (if applicable)

The system MUST validate that the request JSON is well-formed and bounded in size.

### 9.9 Connection Reuse
- Easy handles SHOULD be reused to maximize keep-alive benefits.
- DNS caching and connection reuse SHOULD be enabled via curl defaults or explicit options where appropriate.

---

## 10. Output Stage: Disk Writing

### 10.1 Requirements
- Consume results until `OutputDone`.
- Write results to disk in the configured format.
- Ensure durable writes (flush/close files) at program end.

### 10.2 Ordering
The system SHALL support:
- **Unordered writing** (default throughput-optimized), OR
- **Ordered writing** by `page_id`:
  - buffer out-of-order results until the next expected page arrives
  - emit in order to produce deterministic output layout

Ordering mode MUST be configurable.

### 10.3 Failure Recording
For any failed page, output MUST include:
- page identifier
- final error classification
- last HTTP status / curl error (if available)
- attempt count

---

## 11. Shutdown Semantics

### 11.1 Normal Completion
Completion occurs when:
1. Producer has sent `InputDone`
2. Network worker has:
   - no in-flight requests
   - empty reservoir
   - empty delayed-retry queue
   - flushed pending results
3. Network worker sends `OutputDone`
4. Output thread finishes writing and exits
5. Program exits with success if all pages succeeded, else non-zero

### 11.2 Cancellation (Optional Extension)
If a cancel signal is supported (SIGINT):
- Producer stops generating new tasks.
- Network worker stops accepting new tasks and may:
  - either drain in-flight requests to completion, or
  - abort in-flight transfers (configurable)
- Output writes completed results and terminates cleanly.

Behavior MUST be explicitly defined if implemented.

---

## 12. Error Handling and Classification

The system SHALL classify errors at least into:
- `PDF_ERROR` (open, parse, render failures)
- `ENCODE_ERROR` (JPEG failures)
- `NETWORK_ERROR` (DNS, connect, TLS, transfer)
- `HTTP_ERROR` (non-2xx)
- `PARSE_ERROR` (invalid JSON / missing expected fields)
- `RATE_LIMIT` (429)
- `TIMEOUT`

Each result MUST carry a classification and a human-readable message.

Fatal errors that prevent any meaningful progress (e.g., cannot open PDF, missing API key) SHALL terminate the program early with non-zero exit code.

---

## 13. Observability (Logging and Metrics)

### 13.1 Logging (Required)
- Startup configuration snapshot (excluding secrets)
- Total pages selected
- Periodic progress:
  - completed pages
  - success/failure counts
  - current in-flight count
  - reservoir size
  - retry queue size
- Error logs include page id, attempt, http status/curl error, and short response excerpt (bounded)

### 13.2 Metrics (Recommended)
- request latency distribution
- throughput pages/min
- retry counts and reasons
- 429 rate
- bytes uploaded/downloaded
- memory usage estimate (queued JPEG bytes)

---

## 14. Performance and Resource Constraints

1. The system MUST maintain near-`MAX_INFLIGHT` in-flight requests whenever sufficient tasks remain, subject to:
   - available tasks in reservoir
   - external rate limiting/backoff
2. Memory usage MUST be bounded by:
   - input channel capacity
   - reservoir high watermark
   - JPEG byte storage strategy
3. The system SHOULD avoid per-task synchronization overhead by using batched messages into the input channel, while ensuring the network worker does not couple dispatch to batch boundaries.

---

## 15. Security and Privacy Considerations

- API key MUST not be logged.
- TLS certificate verification MUST be enabled.
- Output may contain sensitive extracted text; output directory permissions SHOULD be respected.
- Optional: provide a “redact logs” mode that suppresses response excerpts.

---

## 16. Acceptance Criteria (Implementation Review Checklist)

An implementation satisfies this specification if:
1. It processes the configured page range and produces per-page outputs.
2. Network concurrency remains stable (no systematic decline at the end of arbitrary internal grouping).
3. The network worker does not stall due to a full output channel.
4. HTTP 429 and transient failures trigger exponential backoff retries with jitter and a retry cap.
5. Memory does not grow unbounded with document size; backpressure is demonstrably effective.
6. Shutdown completes deterministically with correct exit status and a complete output set (success or failure recorded for every selected page).
