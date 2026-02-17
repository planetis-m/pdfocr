---
name: nim-style-guide
description: Enforce idiomatic, readable Nim with strict control-flow, template/proc boundaries, type modeling, and naming rules.
---

# Nim Style Guide

Use this guide when writing or refactoring Nim.
Default to simple, explicit code over clever shortcuts.

## Non-negotiable rules

- `continue` is banned.
- Nested `type` declarations are banned.
- Do not use early `return` only to reduce nesting.
- Do not rewrite normal helper procs into templates unless the helper is a single expression.
- If a helper uses `if`, `case`, loops, `try`, or `block`, it must be a `proc`.
- Do not weaken proc contracts (e.g., `Positive` -> `int`) and then add manual checks.
- Do not add redundant runtime checks that restate existing type/proc contracts unless the spec explicitly requires them.
- Avoid one-argument-per-line function call formatting for normal calls.
- Use helper-proc extraction when a large block under one condition hurts readability.
- Prefer object-construction syntax (`TypeName(field: ...)`) over field-by-field `result.field = ...`
  when creating a value object.

## 1. Formatting

### Rules

- Indent with 2 spaces. No tabs.
- Keep lines reasonably short (target <= 100 chars; prefer about 90-100).
- Do not manually align columns with extra spaces.
- Use `a..b` (not `a .. b`) unless spacing is needed for clarity with unary operators.
- For wrapped declarations/conditions, indent continuation lines one extra level.
  Use +4 spaces relative to the wrapped line's base indent.

### Do

```nim
type
  Handle = object
    fd: int
    valid: bool
```

```nim
proc enterDrainErrorMode(ctx: NetworkWorkerContext; message: string;
    multi: var CurlMulti; active: var Table[uint, RequestContext];
    retryQueue: var seq[RetryItem]; idleEasy: var seq[CurlEasy]) =
  discard
```

```nim
if WebPConfigInitInternal(addr config, WEBP_PRESET_DEFAULT, quality,
      WEBP_ENCODER_ABI_VERSION) == 0:
  raise newException(ValueError, "WebPConfigInitInternal failed")
```

### Don't

```nim
type
  Handle    = object
    fd       : int
    valid    : bool
```

```nim
proc enterDrainErrorMode(ctx: NetworkWorkerContext; message: string;
  multi: var CurlMulti; active: var Table[uint, RequestContext];
  retryQueue: var seq[RetryItem]; idleEasy: var seq[CurlEasy]) =
  discard
```

```nim
if WebPConfigInitInternal(addr config, WEBP_PRESET_DEFAULT, quality,
    WEBP_ENCODER_ABI_VERSION) == 0:
  raise newException(ValueError, "WebPConfigInitInternal failed")
```

## 2. Naming

### Rules

- Types: `PascalCase`.
- Procs/templates/vars/fields: `camelCase`.
- Enum values: prefixed for non-pure enums (`pcFile`), PascalCase for pure enums.
- Use normal word casing: `parseUrl`, `httpStatus`.
- Prefer subject-verb names: `fileExists`, not `existsFile`.

### Do

```nim
type
  PathComponent = enum
    pcFile
    pcDir

proc fileExists(path: string): bool = discard
```

### Don't

```nim
proc existsFile(path: string): bool = discard
proc parseURL(text: string): string = discard
```

## 3. Procs, templates, macros

### Rules

- Default to `proc`.
- `template` is allowed only for tiny expression substitutions.
- A template body should be exactly one expression.
- Never use expression templates with `block:` wrappers to hide statements.
- Use `macro` only when syntax transformation is required.
- For multi-line calls, prefer compact wrapped calls over one-argument-per-line blocks.
- This call-formatting rule is for proc/function calls, not object constructors.

### Do

```nim
finalizeOrRetry(ctx, retryQueue, rng, req.task, req.attempt,
  retryable = true, kind = NetworkError,
  message = boundedErrorMessage(getCurrentExceptionMsg()))
```

```nim
proc runOrchestrator*(cliArgs: seq[string]): int =
  let runtimeConfig = buildRuntimeConfig(cliArgs)
  result = runOrchestratorWithConfig(runtimeConfig)
```

```nim
template slotIndex(i, k: int): int =
  i mod k
```

```nim
proc initWorkerState(seed: int): WorkerState =
  WorkerState(
    active: initTable[uint, RequestContext](),
    retryQueue: @[],
    idleEasy: @[],
    rng: initRand(seed),
    stopRequested: false
  )
```

### Don't

```nim
template nextReady(): bool =
  (block:
    let idx = slotIndex(nextToWrite, k)
    pending[idx].isSome() and pending[idx].get() == nextToWrite
  )
```

```nim
finalizeOrRetry(
  ctx,
  retryQueue,
  rng,
  req.task,
  req.attempt,
  retryable = true,
  kind = NetworkError,
  message = boundedErrorMessage(getCurrentExceptionMsg())
)
```

```nim
proc initWorkerState(seed: int): WorkerState =
  result.active = initTable[uint, RequestContext]()
  result.retryQueue = @[]
  result.idleEasy = @[]
  result.rng = initRand(seed)
  result.stopRequested = false
```

## 4. Control flow

### Rules

- Prefer structured control flow (`if/elif/else`, explicit loop conditions).
- `continue` is banned; structure branches instead.
- Use early `return` for real guard exits (found/fatal/precondition), not as default style.
- Keep one clear normal success path.

### Do

```nim
proc findUser(users: seq[string]; target: string): int =
  for i, user in users:
    if user == target:
      return i
  result = -1
```

```nim
proc process(values: seq[int]): int =
  for value in values:
    if value >= 0:
      result.inc(value)
```

### Don't

```nim
proc process(values: seq[int]): int =
  for value in values:
    if value < 0:
      continue
    result.inc(value)
```

## 5. Returns and `result`

### Rules

- Use `result = ...` for normal flow.
- Use `return` only when the control-flow meaning is important.
- Keep return style consistent inside each proc.

### Do

```nim
proc parsePort(text: string): int =
  let parsed = parseInt(text)
  if parsed < 1 or parsed > 65535:
    raise newException(ValueError, "invalid port")
  result = parsed
```

## 6. Type design

### Rules

- Use named `object` types for semantic data.
- Use tuples for short local values only.
- If a tuple grows beyond a small pair/triple, create a named object.
- Never declare `type` blocks inside procs.

### Do

```nim
type
  RenderOutcome = object
    ok: bool
    payload: seq[byte]
    errorMessage: string
```

### Don't

```nim
proc render(): tuple[ok: bool, payload: seq[byte], errorMessage: string] =
  discard
```

## 7. Local declarations and mutability

### Rules

- Use `let` by default.
- Use `var` only for mutated values.
- Keep declarations close to first use.

### Do

```nim
let page = pages[idx]
var attempts = 0
```

## 8. Errors

### Rules

- Raise clear, bounded, actionable errors.
- Do not silently swallow exceptions.
- Convert low-level errors at module boundaries.

### Do

```nim
try:
  discard doWork()
except CatchableError:
  raise newException(IOError, "doWork failed: " & getCurrentExceptionMsg())
```

## 9. Module hygiene

### Rules

- Remove dead imports and dead declarations immediately.
- Keep exports intentional; do not export internals by default.
- Prefer `std/...` imports for standard library modules.

### Review checklist

- Is every template a true single-expression helper?
- Are there any `continue` statements?
- Are there nested `type` declarations?
- Are return paths structured and readable?
- Did this change introduce dead code or dead exports?
