# Ordered Implementation Plan

This folder defines the full implementation plan for `SPEC.md`. Execute phases in numeric order.

## Global Constraints (Apply In Every Phase)

1. Build with ARC/ORC memory management (`--mm:arc` or `--mm:orc`) because `threading/channels` requires it (`docs/threading_channels.md`).
2. Use `threading/channels` (external package), never `std/channels`.
3. Use `eminim` for JSON serialization/deserialization in production code.
4. Do not send `JsonNode` or other ref-heavy payloads over channels; use value types, `string`, and byte sequences.
5. stdout must contain only per-page JSONL results; all diagnostics/progress go to stderr.
6. The ordered writer is the only execution unit allowed to perform stdout I/O.
7. Enforce bounded memory with:
   - bounded channels,
   - scheduler sliding window (`seq_id < NEXT_TO_WRITE + WINDOW`),
   - bounded in-memory pending buffers.
8. Implement exactly the behavior in `SPEC.md` (no extra features).

## Phase Sequence

1. `plans/01_foundation_and_build.md`
2. `plans/02_cli_and_page_selection.md`
3. `plans/03_runtime_contracts_and_channels.md`
4. `plans/04_renderer_thread.md`
5. `plans/05_network_scheduler_worker.md`
6. `plans/06_ordered_writer.md`
7. `plans/07_orchestration_shutdown_exit_codes.md`
8. `plans/08_testing_and_acceptance.md`

## Consistency Rules While Executing The Plan

1. If a later phase requires a contract change, update the earlier phase file before implementing code.
2. Keep a single attempt-numbering convention everywhere:
   - first request attempt is `1`,
   - `MAX_RETRIES` means additional attempts after the first,
   - max attempts = `1 + MAX_RETRIES`.
3. Keep a single final-result contract:
   - exactly one final `PageResult` per selected `seq_id`,
   - writer emits exactly one JSON line per selected page.
