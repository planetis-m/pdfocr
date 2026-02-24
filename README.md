# pdfocr

Ordered PDF page OCR to JSONL for shell pipelines and LLM workflows.

`pdfocr` renders selected PDF pages to WebP, sends them to DeepInfra's olmOCR model, and writes exactly one JSON object per page to stdout in deterministic order.

## Core guarantees

- stdout is results only (JSON Lines), stderr is logs only
- on non-fatal completion: one output object per selected page
- on non-fatal completion: strict output order by normalized page list
- bounded memory under backpressure
- retry handling for transient network/API failures
- fatal unwind aborts in-flight network work for prompt exit

## Design

`pdfocr` uses a two-thread runtime with bounded in-flight work:

1. `main` thread:
- parses CLI and page selection
- renders PDF pages and encodes WebP
- runs retry scheduling and response classification
- writes ordered JSONL to stdout

2. Relay transport thread (inside the Relay client):
- runs HTTP requests via libcurl multi
- keeps up to `K = max_inflight` requests active
- returns transport completions to the main thread

The main thread keeps a fixed-size reorder ring and only allows at most `K` outstanding pages at a time.

## Measured performance

Live benchmark on February 24, 2026 against `test_files/slides.pdf` (72 pages):

- Result quality: `72/72` pages succeeded
- Output contract: strict page order preserved, exit code `0`
- Measured runtime: `19.93s`
- Throughput: `3.61` pages/s
- Mean wall-clock per page (`runtime / pages`): `0.28s`
- Retry pressure: `0` total retries (`72` pages at `attempts=1`)

Sequential baseline comparison (`K=1`, same 72-page input):

- Sequential runtime: `316.66s` (`5m16.66s`)
- Current runtime: `19.93s`
- Speedup: `15.89x`
- Absolute time reduction: `296.73s` (`4m56.73s`)
- Relative reduction: `93.71%`
- Both runs: `72/72 ok`, ordered output, exit code `0`

## Installation

### Prebuilt binaries (recommended)

Download a release asset for your platform from:

- <https://github.com/planetis-m/pdfocr/releases/latest>

Runtime dependencies:

- Linux: `libcurl` and `libwebp` runtime libraries
- macOS: `curl` and `webp` (Homebrew)
- Windows: no extra runtime install (required DLLs are bundled in the archive)

<details>
<summary>Linux x86_64</summary>

```bash
sudo apt-get update
sudo apt-get install -y libcurl4 libwebp7
curl -L -o pdfocr-linux-x86_64.tar.gz \
  https://github.com/planetis-m/pdfocr/releases/latest/download/pdfocr-linux-x86_64.tar.gz
tar -xzf pdfocr-linux-x86_64.tar.gz
./pdfocr --help
```

</details>

<details>
<summary>macOS arm64</summary>

```bash
brew install curl webp
curl -L -o pdfocr-macos-arm64.tar.gz \
  https://github.com/planetis-m/pdfocr/releases/latest/download/pdfocr-macos-arm64.tar.gz
tar -xzf pdfocr-macos-arm64.tar.gz
./pdfocr --help
```

</details>

<details>
<summary>Windows x86_64 (PowerShell)</summary>

```powershell
curl.exe -L -o pdfocr-windows-x86_64.zip "https://github.com/planetis-m/pdfocr/releases/latest/download/pdfocr-windows-x86_64.zip"
tar.exe -xf pdfocr-windows-x86_64.zip
.\pdfocr.exe --help
```

</details>

Keep the executable and bundled runtime libraries in the same directory.

### Build from source

System dependencies and PDFium:

<details>
<summary>Linux x86_64</summary>

```bash
sudo apt-get update
sudo apt-get install -y libcurl4-openssl-dev libwebp-dev
mkdir -p third_party/pdfium
curl -L https://github.com/bblanchon/pdfium-binaries/releases/latest/download/pdfium-linux-x64.tgz -o pdfium-linux-x64.tgz
tar -xf pdfium-linux-x64.tgz -C third_party/pdfium
```

</details>

<details>
<summary>macOS arm64</summary>

```bash
brew install curl webp
mkdir -p third_party/pdfium
curl -L https://github.com/bblanchon/pdfium-binaries/releases/latest/download/pdfium-mac-arm64.tgz -o pdfium-mac-arm64.tgz
tar -xf pdfium-mac-arm64.tgz -C third_party/pdfium
```

</details>

<details>
<summary>Windows x86_64 (PowerShell)</summary>

```powershell
curl.exe -L -o pdfium-win-x64.tgz "https://github.com/bblanchon/pdfium-binaries/releases/latest/download/pdfium-win-x64.tgz"
New-Item -ItemType Directory -Force -Path third_party/pdfium | Out-Null
tar.exe -xf pdfium-win-x64.tgz -C third_party/pdfium
```

</details>

Build:

```bash
atlas install
nim c -d:release -o:pdfocr src/app.nim
```

For development-oriented setup, testing, and benchmarking notes, see `AGENTS.md`.

## Runtime configuration

Optional `config.json` next to the `pdfocr` executable overrides built-in defaults.
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
- if building from source: Nim `>= 2.2.6`, Atlas, platform dev packages for `libcurl`/`libwebp`, and a downloaded PDFium binary in `third_party/pdfium`

## License

MIT. See `LICENSE.md`.
