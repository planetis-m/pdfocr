# Phase 08 Acceptance Mapping (`SPEC.md` §19)

1. CLI correctness:
- `tests/phase08/test_parser_normalization.nim`
- `tests/phase08/test_integration_exit_codes.nim` (fatal startup validation paths)

2. Ordered stdout (one JSONL per selected page, strict order):
- `tests/phase08/test_writer_ordering.nim`
- `tests/phase08/harness_writer_out_of_order.nim`

3. No filesystem outputs (runtime behavior stays stdout/stderr):
- `tests/phase08/test_stdout_stderr_purity.nim` (stdout-only JSONL validation)

4. Bounded memory and sliding window:
- `tests/phase08/test_scheduler_policy.nim` (`slidingWindowAllows`, bounded backoff checks)
- `tests/phase08/test_backpressure.nim` + `tests/phase08/harness_writer_backpressure.nim` (safe stall/resume under blocked consumer)

5. Backpressure correctness:
- `tests/phase08/test_backpressure.nim`

6. Robust retries and jitter:
- `tests/phase08/test_scheduler_policy.nim`

7. Stable concurrency under scheduler policy:
- `tests/phase08/test_scheduler_policy.nim` (eligibility/retry policy invariants)

8. Deterministic shutdown and exit codes:
- `tests/phase08/test_integration_exit_codes.nim`
- `tests/phase08/test_renderer_failures.nim` (fatal renderer open failure contract)
