# Phase 2: CLI, Output Contracts, and Manifest

## Goals
- Define the CLI interface and output structures required by SPEC §4.
- Implement output path resolution and per-run metadata structures.

## Steps
1. Implement CLI parsing in `src/app.nim` (or a new `src/pdfocr/cli.nim`) for:
   - `pdf_path`, `page_range` (e.g., `1-10` inclusive).
   - `--output-dir`, `--output-format` (jsonl or per-page), `--ordered`.
   - Performance knobs from SPEC §6 (optional overrides).

2. Implement page range parsing and validation:
   - Use `pdfocr.pdfium.loadDocument` and `pageCount` to validate boundaries.
   - Normalize to 0-based internal indices and store 1-based user index per page.

3. Define output format structures in `src/pdfocr/output_format.nim`:
   - JSONL schema: includes `page_id`, `page_number_user`, `text`, `error_kind`, `error_message`, `attempt_count`, `http_status`, timestamps.
   - Per-page files: `page_0001.txt` + `page_0001.json` metadata.

4. Define a run manifest structure (e.g., `RunManifest`) and write to disk at completion:
   - Input file name, optional checksum, page range, config snapshot, per-page status summary, timings.
   - Ensure API key is excluded.

5. Define exit codes per SPEC §4.4 and wire program exit to success/failure counts.

## API References
- PDF page count for validation: `pdfocr.pdfium.pageCount` (docs/pdfium.md)
- Document load: `pdfocr.pdfium.loadDocument` / `close` (docs/pdfium.md)
