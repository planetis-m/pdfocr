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
3. User-tunable internal scheduling knobs beyond fixed internal invariants.

---

## 4. Command-Line Interface

### 4.1 Usage

```bash
pdf-olmocr INPUT.pdf --pages "1,4-6,12" > results.jsonl
```

### 4.2 Arguments

- `INPUT.pdf` (required positional): local PDF path.
- `--pages "<spec>"` (required):
  - `N` for a single page
  - `A-B` for inclusive range
  - comma-separated selectors

### 4.3 Environment Variables

- `DEEPINFRA_API_KEY` (optional, overrides `api_key` in `config.json` when set)

### 4.4 JSON Runtime Config

Implementation SHALL attempt to read `./config.json` (current working directory)
using `jsonx`. If it is missing, the implementation SHALL continue with built-in defaults
and log that defaults are being used.

Supported keys (all optional overrides):

- `api_key`
- `api_url`
- `model`
- `prompt`
- `connect_timeout_ms`
- `total_timeout_ms`
- `max_retries`
- `retry_base_delay_ms`
- `retry_max_delay_ms`
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
- `connect_timeout_ms`
- `total_timeout_ms`
- `max_retries`
- `retry_base_delay_ms`
- `retry_max_delay_ms`
- `render_scale`
- `webp_quality`

### 7.2 Fixed Internal Invariants

- `MaxInflight` (`K`) = maximum in-flight requests and bounded queue capacity.
- `MultiWaitMaxMs`
- `RenderFlags`
- `RenderRotate`

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
- orchestration and ordered stdout writes
- bounded in-memory reorder ring

2. `network` thread:
- libcurl multi request execution
- retries/backoff/jitter
- response parsing
- final page result emission

No renderer thread and no writer thread exist in this design.

---

## 9. Communication Model

Two bounded channels, both capacity `K = MaxInflight`:

1. `TaskQ` (`main -> network`) carrying `OcrTask`
2. `ResultQ` (`network -> main`) carrying final `PageResult`

`main` maintains:

- `next_render` (next page seq to render)
- `next_write` (next seq expected on stdout)
- `outstanding` (submitted to network, not yet written), invariant `0 <= outstanding <= K`
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
   - render/encode success: try to submit task to `TaskQ`
2. If submission cannot proceed (queue/capacity bound), switch to draining `ResultQ`.
3. Drain at least one network result when needed; store in pending ring.
4. Flush the longest contiguous ready prefix from `next_write` to stdout.
5. Repeat until `next_write == N`.

After completion:

- flush stdout
- send stop task to network thread
- join network thread
- return exit code based on whether any page failed.

---

## 13. Network Thread Algorithm

Network thread SHALL:

1. keep up to `K` active requests using curl multi,
2. pull new tasks from `TaskQ` and ready retries,
3. process completions and classify outcomes,
4. emit exactly one final `PageResult` per task,
5. retry only retryable failures up to max attempts,
6. stop cleanly after receiving stop token and draining active/retry work.

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

---

## 15. Deadlock and Backpressure Rules

The following are required for progress safety:

1. `main` MUST NOT block indefinitely trying to enqueue work.
   - It attempts non-blocking submit.
   - If submit is not possible, it drains `ResultQ`.
2. When `outstanding == K` or `TaskQ` cannot accept new work, `main` switches to draining.
3. `network` is allowed to block on sending to `ResultQ`.

If stdout blocks, whole pipeline may stall intentionally.
This is external backpressure, not an internal deadlock.
Memory remains bounded by `K`, channel capacities, and ring size.

---

## 16. Shared Atomics

The implementation may expose atomic counters for diagnostics/progress:

- `NextToWrite`
- `OkCount`
- `ErrCount`
- `RetryCount`
- `InflightCount`

These are not required for correctness of ordering.

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

---

## 18. Security and Privacy

- API key must never appear in logs.
- TLS verification must remain enabled.
- Output may contain sensitive OCR text; by design results are streamed to stdout only.

---

## 19. Acceptance Criteria

Implementation is conformant when all are true:

1. CLI parsing/validation/normalization behaves as specified.
2. stdout contains exactly one JSON object per selected page, in strict order.
3. stdout is pure JSONL, stderr carries diagnostics.
4. retries apply to retryable failures with bounded attempts and jittered backoff.
5. memory remains bounded under slow/blocked stdout.
6. two-thread architecture and `K`-bounded in-flight behavior are preserved.
7. shutdown is deterministic with correct exit codes.
