# pdfocr

A fast, concurrent PDF-to-text OCR pipeline built in Nim. It renders PDF pages with PDFium, encodes to JPEG, sends OCR requests to DeepInfra, and writes results as JSONL or per-page files. The architecture is a three-stage pipeline (producer → network worker → output writer) designed for throughput and deterministic output ordering.

## Features
- Concurrent, bounded pipeline with backpressure
- Deterministic output ordering (optional)
- JSONL output (`results.jsonl`) or per-page text + metadata
- Configurable retries, timeouts, and rate control
- Debug dumps for requests/responses and extracted text

## Requirements
- Nim (ARC/ORC enabled)
- PDFium shared library in `third_party/pdfium/lib`
- libcurl
- libwebp
- DeepInfra API key

## Quick Start

```bash
# build (adjust flags as needed)
nim c -r -d:release --threads:on src/app.nim

# run
export DEEPINFRA_API_KEY=...  # or load .env
# for .env:
# set -a; source .env; set +a
./src/app tests/input.pdf --pages:1-1 --output-dir:/tmp/pdfocr_run_test
```

Output is written to the directory you pass via `--output-dir`. For JSONL output, see:
- `/tmp/pdfocr_run_test/results.jsonl`
- `/tmp/pdfocr_run_test/manifest.json`

## Configuration
The app is configured via CLI flags and compiled defaults. Key runtime options include:
- `--pages:START-END` page range (1-based)
- `--output-dir:PATH` output directory
- `--output-format:jsonl|perpage`
- `--ordering-mode:input|asap`
- `--max-inflight:N` concurrent HTTP requests

See `SPEC.md` for the full contract and behavior.

## Sanitizers
Thread/Address sanitizer support is wired via `src/config.nims` (non-Windows). Examples:

```bash
nim c --threads:on -d:threadSanitizer src/app.nim
nim c --threads:on -d:addressSanitizer src/app.nim
```

## Project Layout
- `src/app.nim` main entry
- `src/pdfocr/producer.nim` PDF rendering & JPEG encode
- `src/pdfocr/network_worker.nim` HTTP + OCR parsing
- `src/pdfocr/output_writer.nim` disk output
- `SPEC.md` implementation contract

## License
MIT. See `LICENSE.md`.
