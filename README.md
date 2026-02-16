# pdfocr

Turn big PDFs into clean, page-ordered OCR JSONL you can pipe straight into LLM workflows.

`pdfocr` is built for real automation, not demos: it streams results in strict page order, handles retries, and stays stable when downstream consumers are slow.

## Why it is useful

- It works well in pipelines: stdout is results only, stderr is logs only.
- It emits one JSON object per selected page, in deterministic order.
- It avoids temp-file sprawl.
- It is resilient to transient API issues (timeouts, rate limits, 5xx).
- It keeps memory bounded under backpressure.

If you have ever had OCR output arrive out-of-order, block unpredictably, or pollute stdout with logs, this is the fix.

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

## Grounded result

Live run on `tests/slides.pdf` (72 pages) completed on February 16, 2026 with:
- `72/72` pages `ok`
- strict output order preserved
- exit code `0`
- wall time `0:21.13` in this environment

Your runtime will vary with hardware, PDF complexity, and network conditions.

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
