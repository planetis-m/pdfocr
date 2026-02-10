# Phase 01: Foundation And Build Baseline

## Goal

Create the project skeleton, hardcoded constants, and build defaults needed by all later phases.

## Inputs

1. `SPEC.md` sections 4, 7, 8, 11, 12
2. `docs/pdfium.md`
3. `docs/curl.md`
4. `docs/threading_channels.md`

## Steps

1. Create module boundaries for the implementation (no behavior yet):
   - `src/app.nim` (CLI entrypoint + orchestration call)
   - `src/pdfocr/constants.nim`
   - `src/pdfocr/types.nim`
   - `src/pdfocr/errors.nim`
   - `src/pdfocr/page_selection.nim`
   - `src/pdfocr/renderer.nim`
   - `src/pdfocr/network_scheduler.nim`
   - `src/pdfocr/writer.nim`
   - `src/pdfocr/orchestrator.nim`
   - `src/pdfocr/json_codec.nim`
   - `src/pdfocr/logging.nim`

2. Set build defaults in project config:
   - default release build uses mimalloc (`-d:useMimalloc`),
   - channel-safe memory model (`--mm:orc` preferred, `--mm:arc` acceptable),
   - sanitizer builds documented to use system malloc (no mimalloc).

3. Add hardcoded constants from spec into `constants.nim`:
   - `API_URL`, `MODEL`
   - `MAX_INFLIGHT`, `WINDOW`
   - `HIGH_WATER`, `LOW_WATER` with runtime or compile-time assertions:
     - `HIGH_WATER <= WINDOW`
     - `LOW_WATER < HIGH_WATER`
   - `CONNECT_TIMEOUT_MS`, `TOTAL_TIMEOUT_MS`, `MULTI_WAIT_MAX_MS`
   - `MAX_RETRIES`, `RETRY_BASE_DELAY_MS`, `RETRY_MAX_DELAY_MS`
   - deterministic render constants (scale/DPI, flags, WebP quality).

4. Define shared error taxonomy in `errors.nim`:
   - `PDF_ERROR`
   - `ENCODE_ERROR`
   - `NETWORK_ERROR`
   - `TIMEOUT`
   - `RATE_LIMIT`
   - `HTTP_ERROR`
   - `PARSE_ERROR`
   Add bounded error-message helper (truncate long strings to a fixed max length).

5. Define strict success/failure exit code constants:
   - `0` all pages ok,
   - `2` at least one page error result,
   - `>2` fatal startup/runtime failure.

6. Add initialization wrappers for global libraries:
   - PDFium: `initPdfium()` and `destroyPdfium()` from `docs/pdfium.md`.
   - curl: `initCurlGlobal()` and `cleanupCurlGlobal()` from `docs/curl.md`.
   Wrap with `try/finally` lifecycle in orchestrator design.

7. Add JSON module scaffolding using `eminim` only:
   - result-line encoder,
   - chat-completion request builder,
   - chat-completion response parser contract.

8. Document invariants in code comments (short, targeted):
   - output ordering is by `seq_id`,
   - writer-only stdout,
   - bounded queues and sliding window enforce memory bounds.

## API References Required In This Phase

1. `docs/pdfium.md`: `initPdfium`, `destroyPdfium`
2. `docs/curl.md`: `initCurlGlobal`, `cleanupCurlGlobal`
3. `docs/threading_channels.md`: ARC/ORC memory requirement for channels

## Completion Criteria

1. All scaffolding modules compile together without functional logic.
2. Constants and error kinds exactly match `SPEC.md`.
3. Build profile documentation clearly states mimalloc default and sanitizer exception.
