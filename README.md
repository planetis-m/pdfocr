# pdfocr

Ordered PDF page OCR to JSONL for shell pipelines and LLM workflows.

`pdfocr` renders selected PDF pages to WebP, sends them to DeepInfra's olmOCR model, and writes exactly one JSON object per page to stdout in deterministic order.

## Core guarantees

- stdout is results only (JSON Lines), stderr is logs only
- one output object per selected page
- strict output order by normalized page list
- bounded memory under backpressure
- retry handling for transient network/API failures

## Current design (simplified)

This branch uses a two-thread design with bounded in-flight work:

1. `main` thread:
- parses CLI and page selection
- renders PDF pages and encodes WebP
- submits OCR tasks
- writes ordered JSONL to stdout

2. `network` thread:
- runs HTTP requests via libcurl multi
- keeps up to `K = MaxInflight` requests active
- applies retries/backoff/jitter
- returns final per-page results

Bounded channels:
- `TaskQ` (`main -> network`) capacity `K`
- `ResultQ` (`network -> main`) capacity `K`

The main thread keeps a fixed-size reorder ring and only allows at most `K` outstanding pages at a time.

## Quick start

```bash
nim c -d:release -o:app src/app.nim
export DEEPINFRA_API_KEY="your_key_here"
LD_LIBRARY_PATH="third_party/pdfium/lib:${LD_LIBRARY_PATH}" \
./app INPUT.pdf --pages:"1,4-6,12" > results.jsonl
```

## CLI

```bash
./app INPUT.pdf --pages:"1,4-6,12"
```

Page spec is 1-based:
- `N` for a single page
- `A-B` for an inclusive range
- comma-separated combinations like `"1,4-6,12"`

Selection is normalized to sorted unique pages.

## Output format

Success line:

```json
{"page":12,"status":"ok","attempts":1,"text":"..."}
```

Error line:

```json
{"page":12,"status":"error","attempts":3,"error_kind":"Timeout","error_message":"...","http_status":504}
```

`error_kind` values:
- `PdfError`
- `EncodeError`
- `NetworkError`
- `Timeout`
- `RateLimit`
- `HttpError`
- `ParseError`

## Exit codes

- `0`: all selected pages succeeded
- `2`: at least one page failed
- `3`: fatal startup/runtime failure

## Benchmarking notes

Live network benchmarks are noisy. For fair comparison between branches:

1. run interleaved pairs (`master`, `candidate`, `master`, `candidate`, ...)
2. run sequentially (no overlapping network traffic)
3. compare medians/trimmed means, not only a single average
4. track retry pressure (`attempts`, 429/5xx) per run

## Requirements

- Nim `>= 2.2.6`
- `DEEPINFRA_API_KEY`
- `libcurl`, `libwebp`, `libpdfium`
- repo expects `third_party/pdfium/lib` at runtime

## Test suite

Run current phase acceptance tests:

```bash
nim e tests/phase08/ci.nims test
```

## License

MIT. See `LICENSE.md`.
