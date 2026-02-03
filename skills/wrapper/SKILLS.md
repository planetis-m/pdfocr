# C→Nim Manual Wrapping Skills

## 1. Purpose
A C→Nim wrapper exposes a C library to Nim while preserving ABI correctness and offering an idiomatic Nim API. The goals are:

- ABI correctness: exact layouts, calling conventions, and signatures.
- Nim ergonomics: safer, clearer, and more “Nim-like” usage.

**Recommended two-layer design:**

1. **Raw FFI layer**: faithful bindings to C with minimal interpretation.
2. **Ergonomic Nim layer**: safe, friendly wrappers that hide pitfalls and add conveniences.

Keep the raw layer stable and thin. Build the ergonomic layer on top so you can adjust usability without changing the ABI surface.

---

## 2. Project Layout & Module Strategy
Split modules by library domain and keep raw bindings isolated from idiomatic wrappers.

**Suggested module pattern (conceptual):**

- `lib_raw_*`: raw FFI modules (structs, enums, `importc` procs)
- `lib_*`: ergonomic modules (overloads, helpers, resource management)

**Public vs private symbols:**

- Export raw symbols only if needed for advanced users.
- Re-export selected symbols from ergonomic modules to provide a clean public API.
- Keep internal helpers private to avoid API bloat.

**When splitting a large library:**

- Mirror the C header structure (by subsystem).
- Avoid cyclic imports by centralizing shared types in a `lib_raw_types` module.
- Keep public surface small and predictable.

---

## 3. Naming & API Conventions (Idiomatic Nim)

**Prefix stripping:**

- Remove common prefixes like `LIB_`, `foo_`, `FOO_` when they don’t add clarity.
- Preserve names when they disambiguate or match common documentation terminology.

**Casing rules:**

- Types/enums/objects: `PascalCase`
- Procs/vars: `lowerCamelCase`
- Constants: `const` in Nim with `PascalCase` (or `CamelCase`) as appropriate

**When to keep original C names:**

- Well-known API names that are part of the library’s identity.
- Names that would collide after stripping prefixes.
- When upstream docs refer to exact names heavily.

**Reserved names / keywords:**

- Add a suffix like `*` in docs but in code use a consistent rename (e.g., `type` → `typ`, `addr` → `address`).
- Consider `importc: "..."` to preserve the C name while using a safe Nim name.

---

## 4. FFI Mechanics Cheatsheet

**Core pragmas:**

- `importc`: bind a Nim symbol to a C symbol.
- `cdecl`: default C calling convention (use `stdcall` or others if C library requires).
- `header`: specify header for C compilation (static linking scenarios).
- `dynlib`: resolve symbols from a shared library at runtime.

**Static vs dynamic linking:**

- **Static**: use `{.header.}` and link the C objects at build time.
- **Dynamic**: use `{.dynlib.}` and optionally specify a library name with `dynlib: "libfoo"`.

**Platform/architecture conditionals:**

- Use `when defined(windows):` etc. for library names and ABI differences.

**Don’t accidentally change ABI rules:**

- Don’t reorder fields in structs.
- Don’t use Nim’s default enums if C expects explicit integer sizes.
- Don’t “helpfully” convert pointer types in the raw layer.

---

## 5. C→Nim Type Mapping (Table + Examples)

### Mapping Table

| C Type | Nim Type | Notes |
|---|---|---|
| `int` | `cint` | Exact C int width |
| `unsigned int` | `cuint` | |
| `long` | `clong` | Platform-dependent |
| `unsigned long` | `culong` | |
| `long long` | `clonglong` | |
| `size_t` | `csize_t` | Use for sizes |
| `intptr_t` | `cintPtr` | Pointer-sized int |
| `uintptr_t` | `cuintPtr` | |
| `float` | `cfloat` | |
| `double` | `cdouble` | |
| `char*` | `cstring` | NUL-terminated |
| `const char*` | `cstring` | Treat as read-only |
| `void*` | `pointer` | Generic pointer |
| `T*` | `ptr T` | Nullable by default |
| `T**` | `ptr ptr T` | |

### Structs and alignment

- Use `object` with fields in C order.
- Use `packed` only if C headers specify packing.
- If alignment is unclear, add `static: doAssert sizeof(T) == ...` in tests.

### Arrays

- Fixed-size array in struct: `array[N, T]`
- Pointer+length: `ptr T` + `csize_t`
- Raw buffers: `ptr UncheckedArray[T]`

### Opaque handles

- Represent as `pointer` or `ptr OpaqueObj` where `OpaqueObj` is an empty object.

**Example: fixed array in struct**

C:
```c
typedef struct LIB_Color {
  unsigned char rgba[4];
} LIB_Color;
```

Raw Nim:
```nim
type
  LibColor* {.importc: "LIB_Color".} = object
    rgba*: array[4, cuchar]
```

---

## 6. Wrapping Enums, Flags, and Constants

**Enums:**

- Use explicit values to match C.
- Use `enum` with explicit base type if needed.

```c
typedef enum LIB_Mode {
  LIB_ModeA = 0,
  LIB_ModeB = 2
} LIB_Mode;
```

```nim
type
  LibMode* {.size: sizeof(cint), importc: "LIB_Mode".} = enum
    ModeA = 0,
    ModeB = 2
```

**Bitflags:**

- Prefer `set[Enum]` if values are powers of two and max bit count is small.
- Otherwise use a distinct integer type and helper procs.

```nim
type
  LibFlags* = distinct cuint

proc has*(flags: LibFlags; flag: LibFlags): bool {.inline.} =
  (flags.uint and flag.uint) != 0
```

**Macros:**

- Simple numeric macros → `const`.
- Function-like macros → wrap as inline procs or templates.

If a macro depends on `sizeof` or expressions with side effects, prefer a Nim template.

---

## 7. Wrapping Functions

**Raw signatures must match C exactly.**

### Example: create/destroy (Automatic Resource Management)

C:

```c
typedef struct LIB_Handle LIB_Handle;
LIB_Handle* LIB_Create(int width, int height);
void LIB_Destroy(LIB_Handle* h);
```

Raw Nim:

```nim
type
  LibHandle* {.importc: "LIB_Handle".} = object

proc libCreate*(width, height: cint): ptr LibHandle
  {.importc: "LIB_Create", cdecl.}
proc libDestroy*(h: ptr LibHandle)
  {.importc: "LIB_Destroy", cdecl.}
```

Ergonomic Nim (Move-Only):

```nim
type
  Handle* = object
    raw: ptr LibHandle

proc `=destroy`(h: Handle) =
  if h.raw != nil:
    libDestroy(h.raw)

proc `=wasMoved`(h: var Handle) = h.raw = nil

proc `=sink`(dest: var Handle; src: Handle) =
  `=destroy`(dest)
  dest.raw = src.raw

proc `=copy`(dest: var Handle; src: Handle) {.error: "Handle cannot be copied".}

proc initHandle*(width, height: int): Handle =
  result.raw = libCreate(cint width, cint height)
  if result.raw.isNil:
    raise newException(ValueError, "Failed to create handle")
```

### Example: in/out parameters

C:
```c
int LIB_GetSize(LIB_Handle* h, int* w, int* hgt);
```

Raw Nim:
```nim
proc libGetSize*(h: ptr LibHandle; w, hgt: ptr cint): cint
  {.importc: "LIB_GetSize", cdecl.}
```

Ergonomic Nim:
```nim
proc size*(h: Handle): tuple[w, hgt: int] =
  var wC, hC: cint
  if libGetSize(h.raw, addr wC, addr hC) != 0:
    raise newException(IOError, "LIB_GetSize failed")
  (int wC, int hC)
```

### Example: string parameters

C:
```c
int LIB_SetName(LIB_Handle* h, const char* name);
```

Raw Nim:
```nim
proc libSetName*(h: ptr LibHandle; name: cstring): cint
  {.importc: "LIB_SetName", cdecl.}
```

Ergonomic Nim:
```nim
proc setName*(h: Handle; name: string) =
  if libSetName(h.raw, name.cstring) != 0:
    raise newException(ValueError, "LIB_SetName failed")
```

---

## 8. Callbacks / Function Pointers

**Declare callback types with `cdecl`:**

```c
typedef void (*LIB_LogFn)(void* userdata, const char* msg);
void LIB_SetLogFn(LIB_LogFn fn, void* userdata);
```

Raw Nim:
```nim
type
  LibLogFn* = proc(userdata: pointer; msg: cstring) {.cdecl.}

proc libSetLogFn*(fn: LibLogFn; userdata: pointer)
  {.importc: "LIB_SetLogFn", cdecl.}
```

Ergonomic Nim:

- **Avoid capturing closures.** C expects a plain function pointer.
- Store state in a global table keyed by `userdata` if needed.

```nim
proc logBridge(userdata: pointer; msg: cstring) {.cdecl.} =
  # Convert and dispatch safely
  let s = $msg
  discard s

proc setLogCallback*(fn: LibLogFn; userdata: pointer) =
  libSetLogFn(fn, userdata)
```

**GC safety:**

- Don’t pass Nim closures to C as callbacks.
- If you store Nim data for callbacks, ensure it is globally rooted or manually managed.
- Consider `gcsafe` only if the callback never touches GC-managed data.

---

## 9. Memory Ownership, Lifetime, and Safety

**Define ownership clearly:**

* **Owned (Move-Only)**: Use the destructor pattern. The Nim object "owns" the C pointer. Use `ensureMove` to transfer ownership.
* **Borrowed**: C owns memory; caller must not free. Return a raw `ptr` or thin wrapper without a `=destroy` hook.

**When to use `{.error.}` on `=copy` hook:**

* **No C Copy Mechanism**: Because the C library offers no way to copy the object, the wrapper does not offer it either.
* **Pointer Stability**: To prevent multiple Nim objects from managing the same C pointer, which causes double-free crashes.

---

## 10. Error Handling Patterns

**C error reporting:**

- Return codes (0 / non-zero)
- `errno`
- Null pointers

**Provide both layers:**

- Raw layer returns the exact codes.
- Ergonomic layer raises exceptions or avoid a `Result`, `Option` types, or "success" boolean tuples for error states.

```nim
proc openDevice*(path: string): Handle =
  result.raw = libOpen(path.cstring)
  if result.raw.isNil:
    raise newException(IOError, "open failed")
```

Keep error behavior predictable and testable.

---

## 11. Testing & Verification Checklist

* **Compile check**: Ensure Nim compiles with library headers.
* **Link check**: Confirm library links (static or dynamic).
- **Smoke test**: call one simple function.
* **ABI checks**: `sizeof`, `alignof`, field offsets.
- **Runtime checks**: verify ownership rules and callback invocation.

**Common failure symptoms:**

- Crashes at call sites → wrong calling convention or struct layout.
- Garbage values → wrong integer width or alignment.
- Random crashes → lifetime issues or freed memory.

---

## 12. Common Pitfalls (Concrete)

- Wrong calling convention (`cdecl` vs `stdcall`).
- Wrong integer widths (`int` vs `long` vs `size_t`).
- Passing Nim `string` directly to C without `.cstring`.
- Struct packing mismatch (missing `packed`, wrong field order).
- Returning pointers to temporary memory or stack buffers.
- Callbacks capturing GC-managed state or closures.
- Using `seq` where C expects stable memory (reallocation risk).
- Lifetime issues with `cstring` (temporary pointer invalid after call).

---

## Example Set (Minimal, Generic)

### A. Strings in/out

C:
```c
const char* LIB_GetName(LIB_Handle* h);
int LIB_SetName(LIB_Handle* h, const char* name);
```

Raw Nim:
```nim
proc libGetName*(h: ptr LibHandle): cstring
  {.importc: "LIB_GetName", cdecl.}
proc libSetName*(h: ptr LibHandle; name: cstring): cint
  {.importc: "LIB_SetName", cdecl.}
```

Ergonomic Nim:
```nim
proc name*(h: Handle): string =
  let p = libGetName(h.raw)
  if p.isNil: return ""
  $p

proc setName*(h: Handle; name: string) =
  if libSetName(h.raw, name.cstring) != 0:
    raise newException(ValueError, "setName failed")
```

### B. Pointer + length buffer

C:
```c
int LIB_Read(LIB_Handle* h, unsigned char* out, size_t len);
```

Raw Nim:
```nim
proc libRead*(h: ptr LibHandle; outBuf: ptr cuchar; len: csize_t): cint
  {.importc: "LIB_Read", cdecl.}
```

Ergonomic Nim:
```nim
proc read*(h: Handle; buf: var openArray[byte]): int =
  if buf.len == 0: return 0
  let rc = libRead(h.raw, cast[ptr cuchar](addr buf[0]), csize_t buf.len)
  int rc
```

### C. Create / destroy resource (Move-Only)

C:

```c
LIB_Handle* LIB_Open(const char* path);
void LIB_Close(LIB_Handle* h);
```

Raw Nim:

```nim
proc libOpen*(path: cstring): ptr LibHandle
  {.importc: "LIB_Open", cdecl.}
proc libClose*(h: ptr LibHandle)
  {.importc: "LIB_Close", cdecl.}
```

Ergonomic Nim:

```nim
type
  Handle* = object
    raw: ptr LibHandle

proc `=destroy`(h: Handle) =
  if h.raw != nil:
    libClose(h.raw)

proc `=wasMoved`(h: var Handle) =
  h.raw = nil

proc `=sink`(dest: var Handle; src: Handle) =
  `=destroy`(dest)
  dest.raw = src.raw

proc `=copy`(dest: var Handle; src: Handle) {.error: "Use move() or ensureMove()".}

proc open*(path: string): Handle =
  result.raw = libOpen(path.cstring)
  if result.raw.isNil:
    raise newException(IOError, "open failed")
```

### D. Reference Counted Resource (Alternative)

If the resource should be copyable (shared ownership), use the RC pattern instead of `.error`:

```nim
type
  Asset* = object
    raw: ptr LibAsset
    rc: ptr int

proc `=destroy`(a: Asset) =
  if a.raw != nil:
    if a.rc[] == 0:
      libFreeAsset(a.raw)
      dealloc(a.rc)
    else: dec a.rc[]

proc `=copy`(dest: var Asset; src: Asset) =
  if src.raw != nil: inc src.rc[]
  `=destroy`(dest)
  dest.raw = src.raw
  dest.rc = src.rc

proc `=sink`(dest: var Asset; src: Asset) =
  `=destroy`(dest)
  dest.raw = src.raw
  dest.rc = src.rc

proc `=wasMoved`(a: var Asset) =
  a.raw = nil
  a.rc = nil

proc loadAsset*(path: string): Asset =
  Asset(raw: libLoad(path.cstring), rc: cast[ptr int](alloc0(sizeof(int))))
```

### E. Callback registration

C:
```c
typedef void (*LIB_OnEvent)(void* userdata, int code);
void LIB_SetOnEvent(LIB_OnEvent cb, void* userdata);
```

Raw Nim:
```nim
type
  LibOnEvent* = proc(userdata: pointer; code: cint) {.cdecl.}

proc libSetOnEvent*(cb: LibOnEvent; userdata: pointer)
  {.importc: "LIB_SetOnEvent", cdecl.}
```

Ergonomic Nim:
```nim
proc onEventBridge(userdata: pointer; code: cint) {.cdecl.} =
  discard userdata
  discard code

proc setOnEvent*(cb: LibOnEvent; userdata: pointer) =
  libSetOnEvent(cb, userdata)
```

---

## Quick Do / Don’t

**Do:**

- Keep raw bindings minimal and ABI-faithful.
- Use `cint`, `csize_t`, `cstring` for C interop.
- Provide safe wrappers that validate errors and manage resources.

**Don’t:**

- Pass Nim `string` directly as `char*`.
- Convert pointers in the raw layer.
- Use closures for callbacks unless you fully manage lifetime and GC safety.
