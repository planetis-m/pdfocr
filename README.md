# pdfocr

`pdfocr` is a Nim CLI that extracts text from selected PDF pages by:
1. Rendering each selected page to WebP.
2. Sending the image to DeepInfra's OpenAI-compatible chat completion endpoint using the `allenai/olmOCR-2-7B-1025` model.
3. Emitting exactly one JSON Lines result per selected page to stdout, strictly ordered by page number.

This README describes the behavior implemented based on `SPEC.md`.

## Behavior
- Strictly ordered stdout output (JSON Lines only).
- No filesystem outputs (stdout is the sole result stream, stderr for logs).
- Bounded memory usage with explicit backpressure handling.
- Retries with exponential backoff and jitter for transient failures.
- Fixed concurrency limits (hardcoded constants; not user-configurable).

## CLI
```bash
pdf-olmocr INPUT.pdf --pages "1,4-6,12" > results.jsonl
```

Arguments:
- `INPUT.pdf` (positional, required): path to a local PDF file.
- `--pages "<spec>"` (required): comma-separated list of 1-based selectors.
  - `N` single page
  - `A-B` inclusive range

Environment:
- `DEEPINFRA_API_KEY` (required): API key for DeepInfra.

## Output (stdout)
JSON Lines, one object per selected page, ordered by ascending page number. Each object includes:
- `page` (int)
- `status` (`ok` or `error`)
- `attempts` (int)
- `text` (string, only on `ok`)
- `error_kind`, `error_message`, `http_status` (only on `error`)

## Logs (stderr)
All progress and diagnostics will go to stderr. Stdout will remain JSONL-only.

## Requirements
- Nim with ARC/ORC enabled.
- PDF rendering + WebP encoding dependencies (exact library choices TBD).
- HTTP client support for TLS.
- DeepInfra API key.

## Specification
`SPEC.md` is the contract for the system design, ordering guarantees, error handling, and concurrency model.

## License
MIT. See `LICENSE.md`.
