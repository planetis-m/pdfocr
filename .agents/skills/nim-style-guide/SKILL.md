---
name: nim-style-guide
description: Write clear, idiomatic Nim using consistent naming, formatting, type design, and control flow with concrete Do/Don't patterns.
---

# Nim Style Guide

Use this guide when writing or refactoring Nim.
Focus on readability, consistency, and predictable control flow.

## Primary references

- Nim Standard Library Style Guide (canonical style direction)
- Nim Manual (language semantics)
- Nim compiler and stdlib source (idiomatic patterns)

When in doubt, prefer consistency with existing local code and stdlib conventions.

## 1. Formatting and layout

### Rules

- Use 2 spaces for indentation. Never use tabs.
- Keep lines reasonably short (target <= 80 chars when practical).
- Use blank lines to separate logical blocks, not every statement.
- Avoid visual-alignment formatting that is fragile during edits.
- Use spaces around operators and after commas.
- Prefer `a..b` over `a .. b` for range operators.

### Do

```nim
type
  Handle = object
    fd: int
    open: bool
```

### Don't

```nim
type
  Handle     = object
    fd        : int
    open      : bool
```

## 2. Naming

### Rules

- Types: `PascalCase`
- Procs/templates/vars/fields: `camelCase`
- Constants: `camelCase` or `PascalCase` (be consistent within a module)
- Enum members:
  - non-`pure` enums: prefixed (`pcFile`, `pcDir`)
  - `pure` enums: `PascalCase`
- Use real-word casing: `parseUrl`, `httpStatus`, not `parseURL`
- Prefer subject-verb names: `fileExists`, not `existsFile`
- Error/defect types should end with `Error` or `Defect`
- For related variants, use suffixes like `Obj`, `Ref`, `Ptr` where useful

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
type
  path_component = enum
    File
    Dir

proc existsFile(path: string): bool = discard
```

### Do

```nim
type
  ValueError = object of CatchableError
  Node = object
  NodeRef = ref Node
```

## 3. Module structure

### Rules

- Group top-level declarations in this order:
  1. imports
  2. constants/types
  3. public API
  4. private helpers
- Keep helpers near their usage.
- Remove dead imports and dead declarations immediately.
- Use `std/...` import form for standard library modules.

### Do

```nim
import std/[os, strutils]

type
  Config = object
    rootDir: string

proc parseConfig(path: string): Config = discard
proc normalizePath(path: string): string = discard
```

## 4. Multi-line formatting

### Rules

- Long proc declarations should break across lines consistently.
- Multi-line calls should continue indented.
- Prefer readability over vertical alignment tricks.

### Do

```nim
proc parseRecord(
  input: string,
  allowEmpty: bool
): int =
  discard

discard parseRecord(
  someInput,
  allowEmpty = true
)
```

## 5. Control flow

### Rules

- Prefer structured `if/elif/else` and explicit loop exit conditions.
- Use early `return` when it improves semantics (guard/found/fatal precondition).
- Do not use early `return` only to flatten nesting.
- Avoid `continue`-driven logic; express branches directly.
- Keep a clear single "normal success path" in each proc.

### Do

```nim
proc findUser(users: seq[string]; target: string): int =
  for i, user in users:
    if user == target:
      return i
  result = -1
```

### Don't

```nim
proc work(x: int): int =
  if x < 0: return -1
  if x == 0: return 0
  if x == 1: return 1
  if x == 2: return 2
  result = x
```

## 6. `result` and returns

### Rules

- Prefer `result = ...` for normal flow.
- Use `return` when control-flow meaning is important.
- Keep return behavior consistent within a proc.

### Do

```nim
proc parsePort(text: string): int =
  let parsed = parseInt(text)
  if parsed < 1 or parsed > 65535:
    raise newException(ValueError, "invalid port")
  result = parsed
```

## 7. Type design

### Rules

- Name meaningful data shapes with `object`.
- Use tuples for short, local, obvious pair/group values.
- If tuple fields become numerous or semantic, promote to named object.
- Avoid nested `type` declarations inside procs.

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
proc render(): tuple[ok: bool, payload: seq[byte], errorMessage: string] = discard
```

## 8. Proc/template/macro boundaries

### Rules

- Default to `proc`.
- Use `template` for small expression-like helpers without hidden side effects.
- Use `macro` only when syntax transformation is truly required.
- Avoid "clever" metaprogramming for ordinary logic.

### Do

```nim
template slotIndex(i, k: int): int =
  i mod k
```

### Don't

```nim
macro computeSlot(i, k: untyped): untyped =
  # unnecessary macro for simple arithmetic
  discard
```

## 9. Error handling style

### Rules

- Raise specific exception types/messages at boundaries.
- Keep error text actionable and concise.
- Do not swallow exceptions silently unless intentional and documented.
- Prefer one place that maps internal errors to user-facing errors.

### Do

```nim
try:
  discard doWork()
except CatchableError:
  raise newException(IOError, "doWork failed: " & getCurrentExceptionMsg())
```

## 10. Mutability and declarations

### Rules

- Use `let` by default.
- Use `var` only when mutation is required.
- Keep variable scope tight (declare near first use).

### Do

```nim
let page = pages[idx]
var retries = 0
```

## 11. API naming conventions

### Rules

- Getter-like APIs should usually be named `foo`, not `getFoo`, when O(1) and side-effect free.
- Use `getFoo` / `setFoo` when side effects or non-trivial cost exist.
- Use conventional verb pairs: `sort/sorted`, `reverse/reversed`, `del/delete`.

### Do

```nim
proc len(data: Buffer): int = discard
proc sorted(values: seq[int]): seq[int] = discard
```

## 12. Comments and docs

### Rules

- Comment *why*, not *what*.
- Prefer short, precise comments over narrative blocks.
- Remove stale comments when behavior changes.

### Do

```nim
# Keep the original order; callers rely on stable sort behavior.
let sortedItems = items.sorted()
```

## 13. FFI and low-level boundaries

### Rules

- Keep FFI surface narrow and wrapped by safer Nim APIs.
- Make ownership explicit for foreign handles.
- Keep unsafe blocks minimal and localized.

### Do

```nim
type
  CurlEasy = ref object
    raw: pointer
```

## Quick Do/Don't summary

1. Do choose clear structure over clever shortcuts.
2. Do use named objects when data has semantic fields.
3. Do keep naming consistent with Nim conventions.
4. Don't rely on `continue` to drive control flow.
5. Don't overuse early returns just to reduce indentation.
6. Don't use macros/templates when a simple proc is enough.
