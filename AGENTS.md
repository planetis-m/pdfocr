# AGENTS

These are project-specific instructions for coding agents working in this repo.

## Operating Mode
- Follow `SPEC.md` and the current plan file order in `plans/`.
- Implement exactly what the active plan specifies. No extras.
- Do not refactor unrelated code.
- Prefer minimal, conservative changes.

## Build and Flags
- Use ARC/ORC memory model (required by threading/channels).
- When compiling with sanitizers, use system malloc (not mimalloc).
- Default builds should use mimalloc (pass `-d:useMimalloc`), unless sanitizers are enabled.

## Concurrency
- Use `threading/channels` (external package). Do not fall back to `std/channels`.
- Do not send `JsonNode` or other ref-heavy types over channels. Serialize to `string` at boundaries.

## JSON Handling
- Use `eminim` for JSON serialization/deserialization.
- Avoid `std/json` in production code unless explicitly required.
- If parsing partial responses, use `-d:emiLenient` as needed.

## Output
- `results.jsonl` is per-run output; do not append across runs.
- Output writer is the only thread that performs file I/O.

## Communication
- If unclear or a plan conflicts with the spec, stop and ask for clarification.
- Show file references for all changes.
