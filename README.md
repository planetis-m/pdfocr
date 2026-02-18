# pdfocr

Ordered PDF page OCR to JSONL for shell pipelines and LLM workflows.

`pdfocr` renders selected PDF pages to WebP, sends them to DeepInfra's olmOCR model, and writes exactly one JSON object per page to stdout in deterministic order.

## Core guarantees

- stdout is results only (JSON Lines), stderr is logs only
- one output object per selected page
- strict output order by normalized page list
- bounded memory under backpressure
- retry handling for transient network/API failures

## Current design

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

## Measured performance

Live benchmark on February 17, 2026 against `tests/slides.pdf` (72 pages):

- Result quality: `72/72` pages succeeded
- Output contract: strict page order preserved, exit code `0`
- Measured runtime: `24.88s`
- Throughput: `2.89` pages/s
- Mean wall-clock per page (`runtime / pages`): `0.35s`
- Retry pressure: `1` total retry (`71` pages at `attempts=1`, `1` page at `attempts=2`)

Sequential baseline comparison (`K=1`, same 72-page input):

- Sequential runtime: `316.66s` (`5m16.66s`)
- Current runtime: `24.88s`
- Speedup: `12.73x`
- Absolute time reduction: `291.78s` (`4m51.78s`)
- Relative reduction: `92.14%`
- Both runs: `72/72 ok`, ordered output, exit code `0`

## Quick start

```bash
nim c -d:release -o:app src/app.nim
LD_LIBRARY_PATH="third_party/pdfium/lib:${LD_LIBRARY_PATH}" \
./app INPUT.pdf --pages:"1,4-6,12" > results.jsonl
```

Optional `config.json` in the current working directory overrides built-in defaults.
It can also override the OCR `prompt` sent to the model.
If `DEEPINFRA_API_KEY` is set, it overrides `api_key` from `config.json`.

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
- Optional `config.json` to override defaults
- Optional `DEEPINFRA_API_KEY` env var to override `api_key` from config
- `libcurl`, `libwebp`, `libpdfium`
- repo expects `third_party/pdfium/lib` at runtime

## Test suite

Run current phase acceptance tests:

```bash
nim test tests/phase08/ci.nims
```

## License

MIT. See `LICENSE.md`.
