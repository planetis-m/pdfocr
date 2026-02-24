# Engineering Specification: Ordered-Stdout PDF OCR CLI (DeepInfra olmOCR)

## 1. Purpose and Scope

This CLI extracts text from selected PDF pages by:

1. rendering each selected page to WebP,
2. sending each image to DeepInfra's OpenAI-compatible chat completions endpoint (`allenai/olmOCR-2-7B-1025`),
3. emitting exactly one ordered JSON line per selected page to stdout.

This specification defines behavior, concurrency, ordering, retries, backpressure, and shutdown semantics for the current simplified design.

---

## 2. Goals

1. Strictly ordered stdout JSONL output by normalized page selection.
2. Streaming results as soon as ordering permits.
3. Bounded memory under normal and backpressured operation.
4. Robust retry behavior for transient network/API failures.
5. Simple, auditable concurrency model with minimal deadlock risk.

---

## 3. Non-Goals

1. Writing OCR results to files (stdout is the output channel).
2. Interactive UI.
3. User-tunable internal scheduling knobs beyond the runtime settings listed in Section 7.

---

## 4. Command-Line Interface

### 4.1 Usage

```bash
pdf-olmocr INPUT.pdf --pages "1,4-6,12" > results.jsonl
pdf-olmocr INPUT.pdf --all-pages > results.jsonl
```

### 4.2 Arguments

- `INPUT.pdf` (required positional): local PDF path.
- Exactly one of:
  - `--pages "<spec>"`:
    - `N` for a single page
    - `A-B` for inclusive range
    - comma-separated selectors
  - `--all-pages`:
    - selects all pages `1..total_pages`

### 4.3 Environment Variables

- `DEEPINFRA_API_KEY` (optional, overrides `api_key` in `config.json` when set)

### 4.4 JSON Runtime Config

Implementation SHALL attempt to read `config.json` from the executable directory
(`getAppDir()`) using `jsonx`. If it is missing, the implementation SHALL continue
with built-in defaults and log that defaults are being used.

Supported keys (all optional overrides):

- `api_key`
- `api_url`
- `model`
- `prompt`
- `max_inflight`
- `total_timeout_ms`
- `max_retries`
- `render_scale`
- `webp_quality`

### 4.5 Validation and Normalization

Implementation SHALL:

1. open the PDF and get total page count,
2. parse and validate page selectors,
3. normalize to sorted unique ascending page numbers,
4. fail fatally if selection is empty or invalid.

---

## 5. Output Contract (stdout)

### 5.1 Format

stdout SHALL contain JSON Lines only (one object per selected page).

### 5.2 Order

Output SHALL be strictly ordered by normalized page list.

### 5.3 Page Result Object

Required fields:

- `page` (1-based page number)
- `status` (`"ok"` or `"error"`)
- `attempts` (>= 1)

If `status == "ok"`:

- `text` (string)

If `status == "error"`:

- `error_kind`
- `error_message` (bounded length)
- `http_status` (optional)

### 5.4 stdout Purity

No logs, banners, or diagnostics on stdout.

---

## 6. Logging (stderr)

All logs and diagnostics SHALL go to stderr.
API keys MUST NOT be logged.

---

## 7. Runtime Settings and Fixed Constants

### 7.1 Runtime Configuration (JSON)

- `api_url`
- `model`
- `prompt`
- `max_inflight`
- `total_timeout_ms`
- `max_retries`
- `render_scale`
- `webp_quality`

### 7.2 Fixed Internal Invariants

- `MultiWaitMaxMs`
- `RenderFlags`
- `RenderRotate`
- `ConnectTimeoutMs`
- `RetryBaseDelayMs`
- `RetryMaxDelayMs`

### 7.3 Exit Codes (Fixed Contract)

- `0`: all pages `ok`
- `2`: at least one page `error`
- `>2` (current implementation uses `3`): fatal startup/runtime failure

---

## 8. Architecture (Current Design)

Exactly two threads:

1. `main` thread:
- CLI parsing and page normalization
- PDF rendering and WebP encoding
- retry scheduling / backoff decisions
- response parsing and final result classification
- orchestration and ordered stdout writes
- bounded in-memory reorder ring

2. Relay transport thread (inside the Relay client):
- libcurl multi request execution
- transport completion delivery to main-thread scheduler

No renderer thread and no writer thread exist in this design.

---

## 9. Communication Model

Main thread drives a local `NetworkScheduler` state machine and submits requests to Relay.
Relay internally manages transport concurrency with capacity `K = max_inflight`.

`main` maintains:

- `next_render` (next page seq to render)
- `next_write` (next seq expected on stdout)
- `outstanding` (submitted pages not yet written), invariant `0 <= outstanding <= K`
- fixed-size pending ring keyed by `seq_id mod K`

---

## 10. Page Identification and Ordering

Let normalized page list be `selected_pages` of length `N`.

- `seq_id` is in `[0, N-1]`
- `page = selected_pages[seq_id]`

Internal ordering is by `seq_id`; emitted JSON uses `page`.

---

## 11. Logical Data Types

### 11.1 OcrTask

- `seq_id`
- `page`
- `webp_bytes`

### 11.2 PageResult

- `seq_id`
- `page`
- `status`
- `attempts`
- `text` (if success)
- `error_kind`, `error_message`, `http_status` (if error)

---

## 12. Main Thread Algorithm

For each selected page sequence:

1. Fill pipeline while capacity is available (`outstanding < K`) and pages remain:
   - render+encode next page
   - render/encode failure: stage immediate final error result in pending ring (attempts=1)
   - render/encode success: submit task to `NetworkScheduler`
2. Drain available network results into pending ring.
3. If ordered writer is blocked and `outstanding > 0`, wait for next network result.
4. Flush the longest contiguous ready prefix from `next_write` to stdout.
5. Repeat until `next_write == N`.

After completion:

- flush stdout
- close `NetworkScheduler` / Relay client
- return exit code based on whether any page failed.

---

## 13. Network Thread Algorithm

Main-thread scheduler SHALL:

1. submit initial request attempts and ready retries while Relay has capacity,
2. process Relay completions and classify outcomes,
3. emit exactly one final `PageResult` per task,
4. retry only retryable failures up to max attempts.

Relay transport thread SHALL:

1. keep up to `K` active requests using curl multi,
2. run transfer I/O and surface transport completions.

---

## 14. Retry and Error Semantics

### 14.1 Error Classes

- `PdfError`
- `EncodeError`
- `NetworkError`
- `Timeout`
- `RateLimit`
- `HttpError`
- `ParseError`

### 14.2 Retryable Conditions

- transport/network failures
- timeout failures
- HTTP 429
- HTTP 5xx

Non-retryable by default:

- HTTP 4xx except 429
- parse errors

### 14.3 Attempts

- first network attempt is `1`
- max attempts is `1 + MaxRetries`
- render/encode failures emit terminal result with `attempts = 1`

### 14.4 Backoff

Exponential backoff with jitter and max cap.

Fatal main-thread unwind is an exception: retry/backoff may be skipped and pending work may
be dropped to ensure prompt process exit.

---

## 15. Deadlock and Backpressure Rules

The following are required for progress safety:

1. `main` MUST NOT render beyond bounded window / outstanding limits.
2. When `outstanding == K`, `main` switches from rendering to draining network results.
3. `main` may block waiting for network results only when `outstanding > 0`.

If stdout blocks, whole pipeline may stall intentionally.
This is external backpressure, not an internal deadlock.
Memory remains bounded by `K` and ring/scheduler state.

---

## 16. Diagnostics

The implementation may expose counters for diagnostics/progress (for example, total retries).
These counters are not required for correctness of ordering.

---

## 17. Shutdown and Exit Codes

### 17.1 Normal Completion

Program completes when all selected pages have emitted and written final results.

### 17.2 Exit Codes

- `0`: all pages `ok`
- `2`: at least one page `error`
- `>2` (current implementation uses `3`): fatal startup/runtime failure preventing full stream completion

### 17.3 Fatal Failures

Fatal errors are logged to stderr and may leave stdout stream incomplete.
After a fatal failure, `main` aborts Relay and shutdown does not wait for retry/timeout
exhaustion or completion of pending requests.

---

## 18. Security and Privacy

- API key must never appear in logs.
- TLS verification must remain enabled.
- Output may contain sensitive OCR text; by design results are streamed to stdout only.

---

## 19. Acceptance Criteria

Implementation is conformant when all are true:

1. CLI parsing/validation/normalization behaves as specified.
2. on non-fatal completion, stdout contains exactly one JSON object per selected page,
   in strict order.
3. stdout is pure JSONL, stderr carries diagnostics.
4. retries apply to retryable failures with bounded attempts and jittered backoff.
5. memory remains bounded under slow/blocked stdout.
6. two-thread runtime (`main` + Relay transport thread) and `K`-bounded in-flight behavior are preserved.
7. shutdown is deterministic with correct exit codes.
