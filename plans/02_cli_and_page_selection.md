# Phase 02: CLI, Validation, And Page Normalization

## Goal

Implement argument/env validation and produce the canonical selected-page plan used by every subsystem.

## Inputs

1. `SPEC.md` sections 4, 9, 17
2. `docs/pdfium.md` (document open + page count APIs)

## Steps

1. Implement CLI parser in `app.nim`/`page_selection.nim`:
   - required positional `INPUT.pdf`,
   - required `--pages "<spec>"`,
   - reject missing/extra/unknown required arguments with fatal error (`>2`).

2. Read and validate `DEEPINFRA_API_KEY`:
   - required non-empty value,
   - never print key in logs or error messages.

3. Initialize PDFium for preflight metadata check:
   - call `initPdfium()`,
   - open input document via `loadDocument(path)`,
   - get total page count with `pageCount(doc)`,
   - clean up via `destroyPdfium()` in `finally`.

4. Implement `--pages` grammar parser:
   - token types: `N` and `A-B`,
   - comma-separated selectors,
   - trim whitespace around tokens,
   - reject malformed tokens immediately.

5. Validate numeric semantics:
   - pages must be `>= 1`,
   - ranges must satisfy `A <= B`,
   - every selected page must be `<= totalPageCount`.

6. Normalize selection:
   - expand ranges,
   - deduplicate,
   - sort ascending,
   - fail fatally if resulting list is empty.

7. Build stable sequence mapping:
   - `selectedPages: seq[int]` (ascending unique 1-based page numbers),
   - `N = selectedPages.len`,
   - internal mapping: `seq_id -> page = selectedPages[seq_id]`.

8. Emit normalized selection metadata to stderr (not stdout):
   - total pages in PDF,
   - selected count,
   - first/last selected page.

9. Return runtime config object used by orchestrator:
   - input path, API key, selected page map, selected count.

## API References Required In This Phase

1. `docs/pdfium.md`:
   - `initPdfium`
   - `loadDocument`
   - `pageCount`
   - `destroyPdfium`

## Completion Criteria

1. Invalid CLI/env/page specs fail early with fatal exit code (`>2`) and stderr-only diagnostics.
2. Valid input produces deterministic normalized ascending unique page list.
3. No stdout output is produced during preflight validation.
