# Phase 07: Orchestration, Lifecycle, And Exit Behavior

## Goal

Wire all components into a deadlock-free lifecycle with deterministic completion, fatal-error handling, and correct exit codes.

## Inputs

1. `SPEC.md` sections 8, 17, 18
2. Phase outputs from `plans/01` through `plans/06`

## Steps

1. Implement top-level runtime sequence in `orchestrator.nim`:
   - parse/validate runtime config (Phase 02),
   - initialize global libraries in deterministic order:
     - `initPdfium()`
     - `initCurlGlobal()`
   - ensure reverse-order cleanup in `finally`:
     - `cleanupCurlGlobal()`
     - `destroyPdfium()`.

2. Create atomics and bounded channels (Phase 03), then start threads in this order:
   - writer first (to ensure result sink exists),
   - renderer second (to consume render requests),
   - scheduler last (drives whole pipeline).

3. Implement fatal-event propagation:
   - all threads can send `FatalEvent` to bounded fatal channel,
   - orchestrator monitors fatal channel and sets global cancel flag.

4. Implement cancel behavior on fatal event:
   - stop scheduling new work,
   - signal renderer stop,
   - allow writer to finish already-delivered ordered results when possible,
   - if completion guarantees cannot be met, terminate with fatal code (`>2`).

5. Optional SIGINT policy (choose one and keep consistent):
   - policy selected: stop scheduling new work and emit terminal error results for unfinished pages where feasible, then exit `2`;
   - if immediate abort is required by runtime constraints, exit `>2` with stderr explanation.

6. Implement join/shutdown ordering:
   - wait scheduler termination first,
   - wait renderer termination,
   - wait writer termination last (writer must flush final output).

7. Compute final process exit code:
   - if fatal flag set or fatal initialization failure: `>2`,
   - else if writer `errCount > 0`: `2`,
   - else: `0`.

8. Ensure stderr-only diagnostics:
   - startup summary,
   - fatal errors,
   - completion summary,
   - never print API key.

## API References Required In This Phase

1. `docs/pdfium.md`:
   - `initPdfium`
   - `destroyPdfium`
2. `docs/curl.md`:
   - `initCurlGlobal`
   - `cleanupCurlGlobal`
3. `docs/threading_channels.md`:
   - channels used for fatal/control/result orchestration

## Completion Criteria

1. All non-fatal runs terminate with complete ordered JSONL output and correct exit code.
2. Fatal paths terminate cleanly with stderr diagnostics and exit code `>2`.
3. Global init/cleanup for PDFium and curl always occur in matched pairs.
