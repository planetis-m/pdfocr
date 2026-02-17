---
name: nim-code-quality
description: Write idiomatic, maintainable, and concurrency-safe Nim with clear control flow, explicit ownership, and strong test discipline.
---

# Nim Code Quality Skill

Use this guidance when writing or refactoring Nim code.

## Goals

1. Keep code easy to reason about.
2. Preserve correctness under concurrency and failure.
3. Make ownership and lifecycle explicit.
4. Prefer maintainable structure over clever shortcuts.

## Core style rules

### 1. Control flow: prioritize clarity

- Prefer structured `if/elif/else` and clear loop boundaries.
- Use early returns when they are semantically meaningful (guard clauses, fast-path lookup, fatal preconditions).
- Do not use early returns only to flatten nesting.
- Avoid `continue`-heavy loops; rewrite with explicit branches.
- Keep one obvious path for "normal success" through a proc.

### 2. Types: name important shapes

- If a tuple has more than 2 meaningful fields, use a named `object`.
- Favor descriptive object fields over positional tuple semantics.
- Avoid nested `type` declarations inside procs; define types at module scope.
- Use enums for explicit states instead of stringly-typed branching.

### 3. Proc and template usage

- Use `proc` for real behavior and state transitions.
- Use `template` for small, local, expression-like helpers where duplication hurts readability.
- Keep templates simple and side-effect transparent.
- Avoid macro/template metaprogramming unless it clearly reduces risk or boilerplate.

## Error handling

### 4. Make failures explicit and bounded

- Classify errors into stable categories.
- Preserve actionable context in error messages.
- Bound/truncate untrusted or large error payloads.
- Catch `CatchableError` at boundaries, not deep in every helper unless recovery is local and intentional.

### 5. Results contracts

- For pipelines, enforce "exactly one final result per unit of work".
- Track attempts consistently (`1`-based recommended).
- Validate invariants with `doAssert` where violation indicates programmer error.

## Ownership and memory safety

### 6. Resource wrappers

- Wrap C handles in owning Nim types.
- Implement `=destroy` for cleanup and disable unsafe copy/dup where needed.
- Use explicit move/sink semantics for ownership transfer.
- Keep FFI boundary code narrow and deterministic.

### 7. Allocation discipline

- Avoid unnecessary conversions/allocations in hot paths.
- Delay expensive expansions (for example, base64) until required at I/O boundaries.
- Reuse expensive handles/buffers when correctness permits.

## Concurrency and channels

### 8. Prefer ownership over shared mutability

- Assign each mutable subsystem to one owner (thread/proc).
- Communicate through bounded channels.
- Keep shared atomics for counters/progress, not core correctness if avoidable.

### 9. Progress and deadlock safety

- Define explicit invariants (for example, `outstanding <= K`).
- When producers cannot submit, switch to draining consumer outputs.
- Treat blocked external sinks as backpressure, not internal deadlock.
- Keep queue capacities and in-memory buffers bounded by design.

## Testing and benchmarking

### 10. Test behavior contracts, not implementation trivia

- Test ordering, retries, exit codes, and error classification.
- Keep fast deterministic tests for policy logic.
- Keep integration tests for end-to-end contracts.

### 11. Benchmarking discipline

- For live network workloads, interleave variants (`A/B/A/B/...`).
- Run sequentially (no overlapping load).
- Report medians/trimmed means and retry pressure, not only mean runtime.
- Treat outliers as signal to investigate, not automatic regressions.

## Code review checklist (quick)

1. Is the control flow straightforward without hidden jumps?
2. Are key data shapes named and self-describing?
3. Are resource ownership and cleanup explicit?
4. Are concurrency invariants documented and asserted?
5. Is failure handling classified, bounded, and test-covered?
6. Are benchmarks fair and statistically robust?
