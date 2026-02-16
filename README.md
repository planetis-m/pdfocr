# pdfocr

Turn big PDFs into clean, page-ordered OCR JSONL you can pipe straight into LLM workflows.

`pdfocr` is built for production automation: strict output order, retry resilience, bounded memory, and clean pipeline behavior.

## Why it is useful

- It works well in pipelines: stdout is results only, stderr is logs only.
- It emits one JSON object per selected page, in deterministic order.
- It avoids temp-file sprawl.
- It is resilient to transient API issues (timeouts, rate limits, 5xx).
- It keeps memory bounded under backpressure.

If you have ever had OCR output arrive out-of-order, block unpredictably, or pollute stdout with logs, this is the fix.

## Measured performance

Live benchmark on February 16, 2026 against `tests/slides.pdf` (72 pages):

- Result quality: `72/72` pages succeeded
- Output contract: strict page order preserved, exit code `0`
- Measured runtime: `32.52s`
- Measured average request latency: `10.34s` per request
- Total summed request latency (serial baseline): `744.63s` (`12m24.63s`)
- Theoretical runtime at `MaxInflight=32` with perfect utilization: `23.27s`
- Effective concurrency achieved: `22.90x` vs serial baseline
- Utilization of concurrency ceiling: `71.56%`

This is the key point: page-level requests are long, but concurrency collapses wall-clock time from minutes to seconds while keeping output deterministic.

## Quick start

```bash
nim c -d:release -o:app src/app.nim
export DEEPINFRA_API_KEY="your_key_here"
LD_LIBRARY_PATH="third_party/pdfium/lib:${LD_LIBRARY_PATH}" \
./app INPUT.pdf --pages:"1,4-6,12" > results.jsonl
```

Page spec is 1-based:
- `N` for a single page
- `A-B` for an inclusive range
- comma-separated combinations like `"1,4-6,12"`

Input is normalized to sorted unique pages automatically.

## What you get

One JSON line per page:

```json
{"page":12,"status":"ok","attempts":1,"text":"..."}
```

On failure:

```json
{"page":12,"status":"error","attempts":3,"error_kind":"Timeout","error_message":"...","http_status":504}
```

Status fields:
- `status`: `ok` or `error`
- `attempts`: total attempts used for that page
- `error_kind`: one of `PdfError|EncodeError|NetworkError|Timeout|RateLimit|HttpError|ParseError`

Your runtime will vary with hardware, PDF complexity, upstream latency, and network conditions.

## Minimal runtime requirements

- Nim `>= 2.2.6`
- `DEEPINFRA_API_KEY`
- `libcurl`, `libwebp`, `libpdfium` (repo expects `third_party/pdfium/lib`)

## Exit codes

- `0`: all selected pages succeeded
- `2`: at least one page failed
- `3`: fatal startup/runtime failure

## Trust and contracts

- `SPEC.md` defines the behavioral contract.
- `tests/phase08/` contains acceptance coverage for ordering, retries, backpressure, and exit semantics.

Run acceptance suite:

```bash
nim e tests/phase08/ci.nims test
```

## License

MIT. See `LICENSE.md`.
