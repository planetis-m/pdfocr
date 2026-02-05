# Engineering Specification: Ordered-Stdout PDF Slide OCR CLI (DeepInfra olmOCR via OpenAI-Compatible API)

## 1. Purpose and Scope

This system is a command-line application that extracts text from selected pages of a PDF by:

1. Rendering each selected page into an image (WebP),
2. Sending the image to DeepInfra’s OpenAI-compatible chat completion endpoint using the `allenai/olmOCR-2-7B-1025` model,
3. Emitting one **ordered** result per selected page to **stdout** as **JSON Lines**.

The tool is designed for use by AI assistants and shell pipelines: stdout is the machine-readable result stream; stderr is reserved for logs and progress.

This specification defines required behaviors, constraints, concurrency model, backpressure rules, error handling, and shutdown semantics.

---

## 2. Goals

1. **Strictly ordered stdout output**: results are written in the same ascending order as the normalized page selection.
2. **Streaming operation**: results are emitted as soon as possible while preserving order.
3. **Bounded memory usage** under all conditions, including slow or blocked stdout consumers.
4. **Robustness** to transient network errors and rate limits with retries and exponential backoff with jitter.
5. **Stable network concurrency** while work remains schedulable within ordering constraints.
6. **Deadlock-free execution** with explicit backpressure and non-blocking progress loops.
7. **Minimal CLI surface** suitable for AI assistants.

---

## 3. Non-Goals

1. Any filesystem outputs (no manifests, no temp files, no output directory).
2. Interactive UI or incremental user feedback on stdout (stdout is results only).
3. Distributed execution across machines.
4. Fine-grained user tuning of internal throughput parameters (hardcoded constants are used).

---

## 4. Command-Line Interface

### 4.1 Usage
```bash
pdf-olmocr INPUT.pdf --pages "1,4-6,12" > results.jsonl
```

### 4.2 Arguments
- `INPUT.pdf` (positional, required): path to a local PDF file.
- `--pages "<spec>"` (required): a comma-separated list of page selectors using 1-based page numbering.
  - Grammar:
    - `N` (single page)
    - `A-B` (inclusive range)
    - selectors separated by commas
  - Examples:
    - `"1"`
    - `"1,4-6,12"`
    - `"10-20,25"`

### 4.3 Environment Variables
- `DEEPINFRA_API_KEY` (required): API key used for authorization.

### 4.4 Validation and Normalization Requirements
The implementation SHALL:
1. Open the PDF and determine total page count.
2. Parse `--pages` and validate:
   - all pages are positive integers (>= 1),
   - ranges have `A <= B`,
   - all pages are within the PDF page count.
3. Normalize the selection into a **sorted, unique** ascending list of page numbers:
   - duplicates are removed,
   - ordering is ascending regardless of the input order.
4. If normalization results in an empty selection, exit with a fatal error.

---

## 5. Output Specification (stdout)

### 5.1 Format
Output SHALL be **JSON Lines** to stdout, exactly one JSON object per selected page.

### 5.2 Ordering Guarantee
Objects SHALL be written strictly in ascending order of the normalized page list.

### 5.3 Per-Page Output Object
Each JSON object SHALL contain at least:

- `page` (integer): the 1-based PDF page number as selected/normalized.
- `status` (string): `"ok"` or `"error"`.
- `attempts` (integer): total attempts made for this page (>= 1).

If `status == "ok"`:
- `text` (string): extracted OCR text (may be empty if the model returns empty content).

If `status == "error"`:
- `error_kind` (string): one of the defined error classes in §12.
- `error_message` (string): human-readable, bounded-length description.
- `http_status` (integer, optional): if an HTTP response was obtained.

### 5.4 stdout Purity
stdout SHALL contain **only** JSONL page results (no progress, no logs, no banners).

---

## 6. Logging (stderr)

All logs, warnings, and progress reporting SHALL be written to **stderr**.

The implementation SHOULD emit periodic progress logs including:
- completed pages count / total selected pages
- ok count, error count
- in-flight request count
- retry count
- current “next page to write” index/page number

Logging MUST NOT include the API key.

---

## 7. Hardcoded Constants

The following constants SHALL be hardcoded (not configurable via CLI):

### 7.1 API
- `API_URL` = `https://api.deepinfra.com/v1/openai/chat/completions`
- `MODEL` = `allenai/olmOCR-2-7B-1025`

### 7.2 Concurrency and Ordering Window
- `MAX_INFLIGHT` (e.g., 32): maximum number of simultaneous HTTP requests.
- `WINDOW` (e.g., 64): maximum number of pages allowed “ahead” of the next page to be written to stdout.

### 7.3 Render Buffer Watermarks (bounded prefetch)
- `HIGH_WATER` (e.g., 64): maximum number of rendered WebP tasks buffered for network dispatch.
- `LOW_WATER` (e.g., 16): threshold at which the scheduler requests more renders.

Constraints:
- `HIGH_WATER <= WINDOW`
- `LOW_WATER < HIGH_WATER`

### 7.4 Timeouts
- `CONNECT_TIMEOUT_MS` (e.g., 10_000)
- `TOTAL_TIMEOUT_MS` per request (e.g., 120_000)
- `MULTI_WAIT_MAX_MS` (e.g., 250): maximum poll/wait duration in the network loop.

### 7.5 Retries
- `MAX_RETRIES` (e.g., 5) additional retries after the first attempt (or equivalently max attempts = 1 + MAX_RETRIES; implementation SHALL define and apply consistently).
- `RETRY_BASE_DELAY_MS` (e.g., 500)
- `RETRY_MAX_DELAY_MS` (e.g., 20_000)
- Jitter MUST be applied to backoff delays.

### 7.6 Channels / Queues (bounded)
All inter-component queues SHALL be bounded to prevent unbounded memory growth.

---

## 8. High-Level Architecture

The system SHALL be implemented as three cooperating execution units (threads or equivalent concurrency primitives):

1. **Renderer**: owns PDF rendering and WebP encoding.
2. **Network Scheduler/Worker**: owns HTTP client multi-request machinery and scheduling policy.
3. **Ordered Writer**: owns stdout writing and ordering buffer.

Communication SHALL be message-based via bounded queues plus a small set of shared atomic variables for progress coordination.

No component may directly access another component’s internal resources (e.g., the network worker does not touch PDF objects; the renderer does not touch HTTP handles; only the writer touches stdout).

---

## 9. Page Identification and Ordering Model

### 9.1 Page Plan
Let `selected_pages` be the normalized ascending list of 1-based page numbers of length `N`.

Define a stable internal sequential identifier:
- `seq_id` in `[0, N-1]`
- `page = selected_pages[seq_id]`

All internal scheduling and ordering SHALL be based on `seq_id`. Output JSON objects use the `page` number.

### 9.2 Output Ordering Requirement
The writer MUST emit results in increasing `seq_id` order (0,1,2,...,N-1).

---

## 10. Data Types (Logical)

### 10.1 Render Request
- `seq_id` (integer)

### 10.2 Rendered Task
- `seq_id` (integer)
- `page` (integer, 1-based)
- `webp_bytes` (byte array)
- `attempt` (integer, starts at 0 or 1 per chosen convention; MUST be consistent)

### 10.3 Page Result
- `seq_id`
- `page`
- `status`: success/failure
- `text` (if success)
- `error_kind`, `error_message`, `http_status` (if failure)
- `attempts`

---

## 11. Shared Atomics (Progress Coordination)

The system SHALL use shared atomic variables (or equivalent lock-free primitives) for:

- `NEXT_TO_WRITE` (integer): writer-owned progress marker.
  - Definition: the smallest `seq_id` not yet written to stdout.
  - Initialized to 0.
  - Updated by the writer after each successful write of the next ordered result.

Additional atomic counters (recommended):
- `OK_COUNT`, `ERR_COUNT`, `RETRY_COUNT`
- `INFLIGHT_COUNT`

These counters are for diagnostics/progress only and SHALL NOT be required for correctness.

---

## 12. Error Classification

Each failure result SHALL be classified as one of:

- `PDF_ERROR`: PDF open/parse/render failures.
- `ENCODE_ERROR`: image encoding failures.
- `NETWORK_ERROR`: transport-level failures (DNS, connect, TLS, etc.).
- `TIMEOUT`: request timed out (connect or total).
- `RATE_LIMIT`: HTTP 429.
- `HTTP_ERROR`: non-2xx HTTP response (excluding 429).
- `PARSE_ERROR`: invalid/unexpected response body structure.

Error messages MUST be bounded in size (e.g., truncate response excerpts).

---

## 13. Scheduling and Backpressure (Core Correctness)

### 13.1 Sliding Window Constraint
The network scheduler MUST enforce:

> At any time, it SHALL NOT schedule work for any `seq_id >= NEXT_TO_WRITE + WINDOW`.

This is the primary mechanism ensuring:
- bounded out-of-order buffering,
- bounded rendered-image buffering,
- bounded pending results even if stdout is slow.

### 13.2 Render Demand Policy (Pull-Based)
Rendering SHALL be **demand-driven** by the network scheduler.

The scheduler requests renders for `seq_id` values within the current window, maintaining a bounded buffer of rendered tasks:
- If buffered rendered tasks fall below `LOW_WATER`, request additional renders up to `HIGH_WATER`,
- but never request beyond the window end.

Renderer SHALL block (or naturally backpressure) when the rendered-task output queue is full.

### 13.3 Network Dispatch Policy
The scheduler SHALL maintain up to `MAX_INFLIGHT` active HTTP requests while:
- there exists schedulable work within the window, and
- stdout backpressure has not halted progress (which halts the window).

### 13.4 stdout Backpressure Behavior
If stdout blocks:
- the writer stops advancing `NEXT_TO_WRITE`,
- the window stops advancing,
- the scheduler naturally stops requesting/scheduling pages beyond the window,
- memory remains bounded by queue sizes + `WINDOW` + `MAX_INFLIGHT`.

The system MAY stall (intentionally) under a blocked stdout consumer; it MUST NOT deadlock internally or grow memory without bound.

---

## 14. Renderer Requirements

### 14.1 PDF Handling
Renderer SHALL:
1. Open the PDF once.
2. Render requested pages by `seq_id` mapping to the corresponding 1-based page number.
3. Use a deterministic render configuration (hardcoded DPI/scale and pixel format).
4. Encode rendered output to WebP (hardcoded quality).

### 14.2 Ownership
Renderer SHALL be the only component that owns/uses PDF rendering library objects.

### 14.3 Failure Handling
If rendering or encoding fails for a page:
- the renderer SHALL produce an immediate failure result for that `seq_id` (via a defined path to the writer, typically by sending a “render failure result” to the network scheduler which forwards it to the writer), OR
- send a rendered task marked failed (implementation choice),
but in all cases the writer MUST eventually receive exactly one final result per selected page unless a fatal error terminates the entire run.

Fatal renderer errors that prevent continuing (e.g., PDF cannot be opened) SHALL terminate the program early with a fatal exit code.

---

## 15. Network Scheduler/Worker Requirements

### 15.1 HTTP Endpoint
Requests SHALL be sent to:
- `POST https://api.deepinfra.com/v1/openai/chat/completions`

### 15.2 Authorization
- `Authorization: Bearer ${DEEPINFRA_API_KEY}`

### 15.3 Request Body (OpenAI-Compatible)
The request SHALL use:
- `model = "allenai/olmOCR-2-7B-1025"`
- A message containing:
  - a text instruction to extract readable text
  - the page image as a `data:image/webp;base64,...` URL

The scheduler SHOULD base64-encode `webp_bytes` during request construction (not earlier), to avoid inflating queued memory.

### 15.4 Response Parsing
On HTTP 2xx, the system SHALL parse OCR text from:
- `choices[0].message.content` (string)

If missing/unparseable, classify as `PARSE_ERROR`.

### 15.5 Retry Rules
Retryable conditions:
- HTTP 429 (`RATE_LIMIT`)
- HTTP 5xx
- transport errors (`NETWORK_ERROR`)
- timeouts (`TIMEOUT`)

Non-retryable by default:
- HTTP 4xx except 429

### 15.6 Backoff with Jitter
Retries SHALL use exponential backoff:
- `delay = min(RETRY_MAX_DELAY_MS, RETRY_BASE_DELAY_MS * 2^attempt) + jitter`

Jitter MUST be applied (uniform or decorrelated jitter acceptable).

### 15.7 Non-Blocking Progress Loop
The network scheduler MUST NOT block indefinitely on sending results to the writer queue.

If the writer-result queue is full, the scheduler SHALL buffer results in a bounded in-memory structure whose maximum growth is bounded by the sliding window and in-flight limit (i.e., it MUST NOT allow unbounded accumulation beyond what `WINDOW` and `MAX_INFLIGHT` imply).

---

## 16. Ordered Writer Requirements

### 16.1 Exclusive stdout Ownership
Only the writer component may write to stdout.

### 16.2 Ordering Buffer
The writer SHALL buffer out-of-order results until `seq_id == NEXT_TO_WRITE` becomes available, then write sequentially until the next missing `seq_id`.

Because the scheduler enforces the sliding window constraint, the writer’s out-of-order buffer SHALL remain bounded by `WINDOW`.

### 16.3 Atomic Progress Updates
After writing the JSONL line for `seq_id = k`, the writer SHALL:
- increment its expected `seq_id`,
- update `NEXT_TO_WRITE` atomically.

### 16.4 Output Durability
The writer SHOULD flush stdout periodically or rely on line buffering when appropriate. At program end it SHALL flush any buffered stdout content.

---

## 17. Completion and Shutdown Semantics

### 17.1 Normal Completion
Normal completion occurs when:
1. Every selected `seq_id` has produced a final result (success or terminal failure),
2. The writer has written all `N` JSONL lines to stdout (i.e., `NEXT_TO_WRITE == N`),
3. All components terminate cleanly.

### 17.2 Exit Codes
- `0`: all pages succeeded (`status="ok"` for all).
- `2`: at least one page failed (`status="error"` for one or more).
- `>2`: fatal initialization/runtime failure preventing completion of the result stream (e.g., missing API key, cannot open PDF).

### 17.3 Fatal Errors
Fatal errors SHALL be reported to stderr and terminate the program with an exit code `>2`. In such cases the stdout stream MAY be incomplete; the implementation SHOULD avoid emitting partial non-JSON data to stdout.

### 17.4 Cancellation (Optional)
If SIGINT/termination handling is implemented:
- The system SHOULD stop scheduling new work.
- It MAY either:
  - attempt to finish in-flight requests and emit completed results, or
  - abort in-flight requests and emit terminal error results for unfinished pages.
The chosen behavior MUST be consistent and documented in implementation notes/logs.

---

## 18. Security and Privacy

- API key MUST NOT be logged.
- TLS verification MUST be enabled.
- OCR output may contain sensitive content; the tool SHALL not write any files by design.
- stderr logs SHOULD avoid printing full OCR text or full response bodies; if including excerpts, they MUST be bounded.

---

## 19. Acceptance Criteria (Implementation Review Checklist)

An implementation satisfies this specification if:

1. **CLI correctness**: parses and validates `--pages`, normalizes to sorted unique selection, rejects invalid pages.
2. **Ordered stdout**: emits exactly one JSONL line per selected page, strictly ordered by ascending page number (via `seq_id` order).
3. **No filesystem writes**: does not create manifests, temp files, or per-page files.
4. **Bounded memory**: memory does not grow unbounded with document size or out-of-order completions; the sliding window constraint is enforced.
5. **Backpressure correctness**: if stdout is slow/blocked, the system does not deadlock internally and does not leak memory; it stalls safely.
6. **Robust retries**: retries occur for 429/5xx/timeouts/transport errors with exponential backoff and jitter, capped by `MAX_RETRIES`.
7. **Stable concurrency (within constraints)**: maintains up to `MAX_INFLIGHT` in-flight requests when schedulable work exists within the sliding window.
8. **Deterministic shutdown**: clean completion with correct exit codes; all pages produce a final success or error result unless a fatal error prevents completion.

---
