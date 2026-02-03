# Phase 5: Output Stage (Writer + Ordering)

## Goals
- Write per-page results in the configured format without blocking upstream processing.
- Support ordered and unordered output modes.

## Steps
1. Implement `src/pdfocr/output_writer.nim` running in its own thread:
   - Receives `PageResult` and `OutputDone` messages.
   - Writes output to disk as JSONL or per-page files.

2. JSONL mode:
   - Open `results.jsonl` for append in the output directory.
   - For each result, serialize JSON and append a single line.

3. Per-page mode:
   - Write `page_XXXX.txt` and `page_XXXX.json` metadata files.

4. Ordering mode:
   - If ordered, buffer results keyed by `page_id` until next expected ID arrives.
   - Flush in-order to disk; keep remaining out-of-order in memory.

5. On `OutputDone`:
   - Flush all pending buffered results.
   - Close files and ensure durable writes.

6. Failure recording:
   - Include `error_kind`, `error_message`, `attempt_count`, `http_status` in output.

## API References
- No direct external APIs; uses shared types and output format definitions from Phase 2.
