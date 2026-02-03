# Phase 1: Project Setup and Scaffolding

## Goals
- Establish the project entrypoint, configuration loading, and shared types.
- Ensure required libraries (PDFium, libjpeg, libcurl) are initialized and cleaned up correctly.
- Create foundational modules to be used by later phases.

## Steps
1. Create a `src/app.nim` entrypoint that:
   - Parses CLI args (pdf path, page range, output dir, config overrides).
   - Loads env/config for `deepinfra_api_key`.
   - Initializes global libraries in the correct order:
     - `pdfocr.pdfium.initPdfium()` / `pdfocr.pdfium.destroyPdfium()`
     - `pdfocr.curl.initCurlGlobal()` / `pdfocr.curl.cleanupCurlGlobal()`
   - Sets up main pipeline threads but does not implement them yet.
   - Ensures non-zero exit on fatal errors.

2. Define a configuration module (e.g., `src/pdfocr/config.nim`) that:
   - Holds all parameters from SPEC §6: `MAX_INFLIGHT`, `HIGH_WATER`, `LOW_WATER`, `PRODUCER_BATCH`, timeouts, retry settings, `MULTI_WAIT_MAX_MS`, render DPI/scale, JPEG quality, ordering mode, output format.
   - Validates invariants (`HIGH_WATER >= LOW_WATER >= MAX_INFLIGHT`).
   - Exposes defaults as constants or a builder.

3. Define shared types in `src/pdfocr/types.nim`:
   - `Task`, `Result`, channel message enums, error classification enum from SPEC §12.
   - Include `page_id`, `page_number_user`, `attempt`, `jpeg_bytes` (bytes), timestamps.
   - Include `Result` fields from SPEC §7.2.

4. Create minimal logging helper `src/pdfocr/logging.nim`:
   - Startup config snapshot (excluding API key), and basic structured log helpers.
   - Progress log counters placeholder for later phases.

5. Add placeholder modules for the pipeline stages (`producer`, `network`, `output`) with empty procs and clear interfaces so compilation can succeed as modules are filled.

## API References
- PDFium init/cleanup: `pdfocr.pdfium.initPdfium`, `destroyPdfium` (docs/pdfium.md)
- Curl global init/cleanup: `pdfocr.curl.initCurlGlobal`, `cleanupCurlGlobal` (docs/curl.md)
