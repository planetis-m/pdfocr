# Engineering Specification: `pdfocr` Ordered-Stdout PDF OCR CLI

## 1. Purpose

`pdfocr` renders selected PDF pages to WebP, sends each page image to DeepInfra's OpenAI-compatible chat completions API, and streams ordered JSONL page results to stdout.

This document describes the current implemented behavior in `src/`.

## 2. CLI Contract

### 2.1 Program name and usage

```bash
pdfocr INPUT.pdf --pages:"1,4-6,12" > results.jsonl
pdfocr INPUT.pdf --all-pages > results.jsonl
```

### 2.2 Arguments

- `INPUT.pdf` is a required positional argument.
- Exactly one selector mode is required: `--pages:<spec>` or `--all-pages`.
- `--help` and `-h` print help text and exit `0`.

CLI parse errors (missing input, multiple input files, unknown option, invalid selector mode combination) terminate with exit code `3`.

### 2.3 Page selector semantics (`--pages`)

- Tokens are comma-separated.
- Token form `N` is a single page where `N >= 1`.
- Token form `A-B` is an inclusive range where `A >= 1`, `B >= 1`, and `A <= B`.
- Selection is normalized to sorted unique ascending pages.
- Empty or malformed specs fail.
- After normalization, any selected page greater than the PDF page count fails.

### 2.4 `--all-pages`

- Selects `1..total_pages`.
- Empty resulting selection (for example a zero-page document) is a fatal error.

## 3. Runtime Configuration

### 3.1 Configuration sources

- Built-in defaults from `src/pdfocr/constants.nim`.
- Optional `config.json` loaded from executable directory (`getAppDir()/config.json`).
- `DEEPINFRA_API_KEY` environment variable overrides `config.json.api_key` when non-empty.

If `config.json` is missing, defaults are used.  
If `config.json` exists but parsing fails, the file is ignored and defaults are used.

### 3.2 Supported config keys

- `api_key`
- `api_url`
- `model`
- `prompt`
- `max_inflight`
- `total_timeout_ms`
- `max_retries`
- `render_scale`
- `webp_quality`

Unknown extra keys are tolerated (`jsonxLenient`).

### 3.3 Value normalization rules

- `api_url`, `model`, `prompt`: empty string falls back to defaults.
- `max_inflight`, `total_timeout_ms`, `render_scale`: must be `> 0`, else default.
- `max_retries`: must be `>= 0`, else default.
- `webp_quality`: must be in `[0, 100]`, else default.

### 3.4 Built-in defaults

- `api_url`: `https://api.deepinfra.com/v1/openai/chat/completions`
- `model`: `allenai/olmOCR-2-7B-1025`
- `prompt`: `Extract all readable text exactly.`
- `max_inflight`: `32`
- `total_timeout_ms`: `120000`
- `max_retries`: `5`
- `render_scale`: `2.0`
- `webp_quality`: `80.0`

Missing API key after resolution is fatal.

## 4. Output Contract

### 4.1 Stream and ordering

- stdout contains JSON Lines only.
- On non-fatal completion, exactly one JSON object is emitted per selected page.
- Emission order is strictly the normalized page order.

### 4.2 Result object schema

Common fields:

- `page` (1-based PDF page number)
- `status` (`"ok"` or `"error"`)
- `attempts` (`>= 1`)

For `status == "ok"`:

- `text` (string)

For `status == "error"`:

- `error_kind` (`PdfError`, `EncodeError`, `NetworkError`, `Timeout`, `RateLimit`, `HttpError`, `ParseError`)
- `error_message` (string)
- `http_status` only when non-zero

## 5. Concurrency and Architecture

Exactly two threads are used:

- `main` thread handles CLI/config loading, page normalization, PDF render+WebP encode, request submission, retry scheduling, completion processing, and ordered stdout emission.
- Relay transport thread (inside `Relay`) executes HTTP requests via libcurl multi and returns completions to the main thread.

No dedicated renderer thread and no dedicated writer thread exist.

## 6. Pipeline State and Invariants

Let `N = selectedPages.len` and `K = max(1, network.maxInflight)`.

Main orchestration tracks:

- `nextSubmitSeqId` (next page sequence to render/submit)
- `nextEmitSeqId` (next sequence required for ordered output)
- `inFlightCount` (submitted attempts not yet completed)
- `activeCount` (pages with active lifecycle, including retry-waiting pages)
- `remaining` (final page results not yet emitted)
- `retryQueue` (time-ordered retries)
- `staged` (`seq[PageResult]`, length `N`)
- `cachedPayloads` (`seq[CachedPayload]`, length `N`)

Key invariants:

- `activeCount <= K`
- `inFlightCount <= K`
- At most `K` payloads are non-empty at once.
- Output order is determined by sequence id (`seqId`), mapped to `selectedPages[seqId]`.

Memory model in practice:

- O(`N`) metadata for staged/result bookkeeping.
- O(`K`) large WebP payload retention.

## 7. Request and Response Handling

### 7.1 Request construction

Each attempt submits one chat completion request with:

- model from runtime config
- one user message containing the text prompt and a `data:image/webp;base64,...` image URL
- `temperature = 0.0`
- `max_tokens = 1024`
- `tool_choice = none`
- `response_format = text`

Per-request timeout uses `total_timeout_ms`.

### 7.2 OCR response parsing

- Successful HTTP responses are parsed as `ChatCreateResult`.
- Text extraction uses `firstText(...)`.
- Parse failure becomes terminal `ParseError`.

## 8. Retry and Final Error Semantics

### 8.1 Attempt accounting

- Initial network attempt is `1`.
- `maxAttempts = max(1, max_retries + 1)`.
- Render/encode failures are terminal with `attempts = 1`.

### 8.2 Retryable conditions

Retry is allowed only when `attempt < maxAttempts` and condition is retryable.

Retryable transport kinds:

- `teTimeout`
- `teNetwork`
- `teDns`
- `teTls`
- `teInternal`

Retryable HTTP statuses:

- `408`, `409`, `425`, `429`
- any `5xx`

### 8.3 Backoff policy

`openai_retry.defaultRetryPolicy(maxAttempts = maxAttempts)` is used:

- base delay `250ms`
- exponential growth with cap `8000ms`
- additive jitter (`divisor = 4`)

### 8.4 Final classification

When no more retries occur:

- Transport timeout -> `Timeout`
- Other transport error -> `NetworkError`
- HTTP `429` -> `RateLimit`
- HTTP `408` or `504` -> `Timeout`
- Other non-success HTTP -> `HttpError`
- Parse failure after HTTP success -> `ParseError`

## 9. Request ID Encoding Contract

`request_id` packs `(seqId, attempt)` into a signed 64-bit integer.

- low 16 bits: attempt (`1..65535`)
- remaining 47 bits: sequence id (`0..2^47-1`)

Capacity is validated before pipeline start:

- selected page count must fit sequence range
- `maxAttempts` must be `<= 65535`

## 10. Logging, Shutdown, and Exit Codes

- Logs/diagnostics go to stderr only.
- API keys must not be logged.
- Normal completion closes Relay (`client.close()`).
- Fatal unwind aborts Relay (`client.abort()`) for prompt shutdown.

Exit codes:

- `0`: all emitted page results are `"ok"`
- `2`: non-fatal completion with at least one `"error"` page result
- `3`: fatal startup/runtime failure (stdout may be incomplete)

## 11. Acceptance Criteria

Implementation is conformant when:

1. CLI behavior and page normalization match Section 2.
2. Runtime config resolution and fallback rules match Section 3.
3. On non-fatal completion, stdout is pure JSONL with one ordered result per selected page.
4. Retry/backoff/final-error mapping matches Section 8.
5. Two-thread architecture and `K`-bounded active/in-flight behavior are preserved.
6. Exit codes and fatal abort semantics match Section 10.
