# pdfocr

Ordered PDF page OCR to JSONL for shell pipelines and LLM workflows.

`pdfocr` renders selected PDF pages to WebP, sends them to DeepInfra's olmOCR model, and writes exactly one JSON object per page to stdout in deterministic order.

## Core guarantees

- stdout is results only (JSON Lines), stderr is logs only
- one output object per selected page
- strict output order by normalized page list
- bounded memory under backpressure
- retry handling for transient network/API failures

## Installation

### Prebuilt binaries (recommended)

Download a release asset for your platform from:

- <https://github.com/planetis-m/pdfocr/releases/latest>

Linux x86_64:

```bash
curl -L -o pdfocr-linux-x86_64.tar.gz \
  https://github.com/planetis-m/pdfocr/releases/latest/download/pdfocr-linux-x86_64.tar.gz
tar -xzf pdfocr-linux-x86_64.tar.gz
./pdfocr --help
```

macOS arm64:

```bash
curl -L -o pdfocr-macos-arm64.tar.gz \
  https://github.com/planetis-m/pdfocr/releases/latest/download/pdfocr-macos-arm64.tar.gz
tar -xzf pdfocr-macos-arm64.tar.gz
./pdfocr --help
```

Windows x86_64 (PowerShell):

```powershell
curl.exe -L -o pdfocr-windows-x86_64.zip "https://github.com/planetis-m/pdfocr/releases/latest/download/pdfocr-windows-x86_64.zip"
tar.exe -xf pdfocr-windows-x86_64.zip
.\pdfocr.exe --help
```

Keep the executable and bundled runtime libraries in the same directory.

### Build from source

```bash
atlas install
nim c -d:release -o:pdfocr src/app.nim
```

For development-oriented setup, testing, and benchmarking notes, see `AGENTS.md`.

## Runtime configuration

Optional `config.json` in the current working directory overrides built-in defaults.
It can also override the OCR `prompt` sent to the model.
It can also override `max_inflight` to control parallelism.
If `DEEPINFRA_API_KEY` is set, it overrides `api_key` from `config.json`.

## CLI

```bash
./pdfocr INPUT.pdf --pages:"1,4-6,12"
./pdfocr INPUT.pdf --all-pages
```

Page spec is 1-based:

- `N` for a single page
- `A-B` for an inclusive range
- comma-separated combinations like `"1,4-6,12"`
- use `--all-pages` to OCR every page in the input PDF

Selection is normalized to sorted unique pages.
Provide exactly one of `--pages` or `--all-pages`.

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

## Requirements

- DeepInfra API key (via `DEEPINFRA_API_KEY` or `config.json`)
- input PDF file
- if building from source: Nim `>= 2.2.6`, `libcurl`, `libwebp`, `libpdfium`

## License

MIT. See `LICENSE.md`.
