# AGENTS

Repository-specific instructions for coding agents working in `pdfocr`.

## 1. Purpose and Source of Truth

- This repository implements an ordered-stdout PDF OCR CLI.
- Behavioral contract is defined in `SPEC.md`.
- Usage and operator-facing commands are documented in `README.md`.
- Compiler flags and memory model are defined by `config.nims` files:
  root `config.nims`, `src/config.nims`, and test configs under `tests/`.

## 2. Repository Layout

- `src/app.nim`: CLI entrypoint.
- `src/pipeline.nim`: main orchestration loop (render, submit, ordered write).
- `src/runtime_config.nim`: CLI parsing, config loading, and environment overrides.
- `src/ocr_client.nim`: OpenAI-compatible request construction and response parsing.
- `src/pdf_render.nim`: page render + WebP encode composition.
- `src/pdfium_wrap.nim`, `src/webp_wrap.nim`: ergonomic wrappers over low-level bindings.
- `src/page_selection.nim`: page selector parsing/normalization.
- `src/request_id_codec.nim`: request-id packing/unpacking and bounds checks.
- `src/retry_and_errors.nim`: retry decisions and final error classification.
- `src/types.nim`, `src/constants.nim`, `src/logging.nim`: shared types/constants/log helpers.
- `src/pdfocr/bindings/`: low-level C bindings (currently `pdfium`, `webp`).
- `tests/`: current test suite and CI test task.

## 3. Dependencies and Build System

- Use Atlas-managed dependencies and paths from `nim.cfg`/`deps/`.
- Prefer `atlas install` for dependency setup.
- Do not use `nimble install` for project dependency management.
- Do not bypass `config.nims` with ad-hoc compiler flags unless the task explicitly requires it.

Common commands:

```bash
atlas install
nim c -d:release -o:pdfocr src/app.nim
```

## 4. Build Flags and Memory Model

- The project memory model is `atomicArc` (set in `src/config.nims`).
- Do not override the memory model from CLI flags; use project `config.nims` defaults.
- Default allocator should be mimalloc (`-d:useMimalloc`, configured by root `config.nims`).
- With sanitizers (`-d:addressSanitizer` or `-d:threadSanitizer`), use system malloc (`-d:useMalloc`).

## 5. Runtime and Contract Invariants

- `stdout` must contain JSONL results only (one object per selected page).
- `stderr` is for logs/diagnostics only; never leak API keys.
- Output order must be strictly by normalized selected pages.
- Exit codes are contractually fixed:
  - `0`: all selected pages succeeded
  - `2`: at least one selected page failed
  - `3`: fatal startup/runtime failure
- Preserve bounded in-flight behavior (`K = max_inflight`) and bounded memory.

## 6. Concurrency Rules

- Keep the two-context architecture unless explicitly asked to change it:
  - `main` thread: CLI/config, render/encode, retry policy, ordered write
  - Relay transport thread (inside Relay): HTTP/libcurl execution
- Keep orchestration state explicit in `PipelineState`; avoid hidden shared mutable state.
- If introducing channels, use `threading/channels` (external package), not `std/channels`.
- Avoid nested helper procs that capture mutable orchestration locals; extract helpers and pass explicit state.

## 7. JSON and Config Handling

- Prefer `jsonx` for runtime config and JSONL encoding/decoding behavior.
- Keep lenient parsing behavior where expected (`jsonxLenient` is enabled).
- Avoid introducing `std/json` in production paths unless explicitly required by the task.

## 8. Testing and Verification

Primary CI test task runs from `tests/`.
- Keep default compiler settings from `tests/config.nims`.
- Do not override memory model flags in test commands.

- Current CI task:
  - `cd tests && nim test ci.nims`
- Single-test example:
  - `cd tests && nim c -r test_retry_and_errors.nim`
- Repository-root equivalent for CI task:
  - `(cd tests && nim test ci.nims)`
- Optional live/manual runs require `DEEPINFRA_API_KEY`.
- In Codex/sandbox sessions, always request terminal permission approval before running live network commands.
- ASan build/run example (repository root):
  - `nim c -d:addressSanitizer -o:pdfocr_asan src/app.nim`
  - `set -a; source .env; set +a` to export `DEEPINFRA_API_KEY` from `.env` into the shell environment.
  - `ASAN_OPTIONS=detect_leaks=0 LD_LIBRARY_PATH=./third_party/pdfium/lib ./pdfocr_asan test_files/input.pdf --all-pages`
  - `ASAN_OPTIONS=detect_leaks=0` is required in this environment because LeakSanitizer is not usable under ptrace/sandbox.

When behavior changes, update or add tests under `tests/` first.

## 9. Code Change Policy

- Prefer minimal, conservative diffs.
- Do not refactor unrelated code.
- Preserve public behavior unless explicitly asked to change it.
- If behavior or contract changes, update `SPEC.md` and `README.md` in the same change.
- Show file references for all user-visible change summaries.

## 10. Style

- Follow `.agents/skills/nim-style-guide/SKILL.md`.
- Keep code explicit and readable over cleverness.
- Favor object constructors (`TypeName(field: ...)`) over field-by-field result mutation.

## 11. Benchmarking Notes

Live network benchmarks are noisy. For fair branch comparison:

1. Run interleaved pairs (`master`, `candidate`, `master`, `candidate`, ...).
2. Run sequentially without overlapping network traffic.
3. Compare medians/trimmed means, not just one sample.
4. Track retry pressure (`attempts`, 429/5xx) per run.
