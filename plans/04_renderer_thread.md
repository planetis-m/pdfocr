# Phase 04: Renderer Thread (PDF -> WebP Tasks)

## Goal

Implement the renderer execution unit that owns PDF rendering and emits either rendered WebP tasks or terminal render failures.

## Inputs

1. `SPEC.md` sections 8, 10, 13, 14
2. `docs/pdfium.md`
3. Contracts from `plans/03_runtime_contracts_and_channels.md`

## Steps

1. Implement renderer thread entrypoint with inputs:
   - PDF path,
   - immutable `selectedPages` mapping (`seqId -> page`),
   - `renderReqCh`,
   - `renderOutCh`,
   - fatal-event channel.

2. Open PDF once for rendering lifecycle:
   - call `loadDocument(path)` once at renderer startup,
   - on failure send fatal event (`PDF_ERROR`) and terminate renderer.

3. Process render requests in a loop:
   - block on `renderReqCh.recv(...)`,
   - stop cleanly on stop signal,
   - map request `seqId` to 1-based page number from selected list.

4. Render requested page deterministically:
   - call `loadPage(doc, page-1)` (zero-based PDFium index),
   - render with fixed scale/flags (hardcoded constants),
   - use `renderPageAtScale(page, scale, alpha=false, rotate=0, flags=...)`.

5. Convert rendered bitmap to encoder input:
   - read dimensions via `width(bitmap)` / `height(bitmap)`,
   - read pixel pointer via `buffer(bitmap)` and row bytes via `stride(bitmap)`,
   - transform/forward into internal WebP encoder pipeline.

6. Encode to WebP bytes using internal encoder module:
   - hardcoded quality and deterministic settings,
   - no filesystem output,
   - produce `webpBytes: seq[byte]`.

7. Emit renderer output:
   - success: send `RenderedTask(seqId, page, webpBytes, attempt=1)` to `renderOutCh`,
   - page-level failure (`loadPage`, render, encode): send terminal renderer-failure variant with:
     - `errorKind = PDF_ERROR` for page/render failures,
     - `errorKind = ENCODE_ERROR` for encode failures,
     - bounded `errorMessage`.

8. Handle backpressure safely:
   - allow bounded blocking on `renderOutCh.send` (natural backpressure),
   - no unbounded local queue inside renderer.

9. Shutdown behavior:
   - on stop signal, exit loop and release resources,
   - ensure document/page/bitmap handles are scoped and dropped correctly.

## API References Required In This Phase

1. `docs/pdfium.md`:
   - `loadDocument`
   - `loadPage`
   - `renderPageAtScale`
   - `width`
   - `height`
   - `buffer`
   - `stride`

2. `docs/threading_channels.md`:
   - `recv`
   - `send`

## Completion Criteria

1. Renderer emits one output message per render request (success task or terminal render failure).
2. PDF objects are owned and used only inside renderer.
3. Renderer stops cleanly on control signal and does not perform stdout/file I/O.
