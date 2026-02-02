# Nim ↔ C Bindings — Operational Rules

## Scope
- This is a prescriptive rulebook for building Nim bindings to C libraries across Linux, macOS, and Windows.
- Use it as a checklist for reliable CI builds and portable runtime behavior.

## Core Workflow (Binding + Build)
- Use `importc` with `callconv: cdecl` for C APIs unless the library explicitly uses a different calling convention.
- Represent opaque C handles as `distinct pointer` types in Nim.
- For partial or opaque C structs, use `incompleteStruct` to avoid size/layout mismatches.
- For value structs that Nim must pass by value, use `bycopy`.
- Declare the C header in the binding (`header: "<...>"`) when the compiler needs definitions.

## System vs Local/Third-Party Libraries
- System libraries:
  - Link with `-l<name>` only; do not hardcode `-L` paths when the OS toolchain can locate them.
- Local/third-party libraries (vendored or downloaded):
  - Add `-L<dir>` plus `-l<name>` (or the platform import library on Windows).
  - Use repository-relative paths (e.g., `third_party/...`) to keep builds hermetic.

## Runtime and Portability Assumptions
- Prefer colocating required shared libraries next to the executable at runtime.
- Do not rely on environment variables (`LD_LIBRARY_PATH`, `DYLD_LIBRARY_PATH`, `PATH`) for runtime resolution.
- On Linux, add rpath to the executable directory:
  - `--passL:"-Wl,-rpath,\\$ORIGIN"`

## CI-Driven Constraints (Generalized)
- Treat CI as the authoritative spec for supported platforms, toolchains, and flags.
- Any local workflow not compatible with CI is disallowed.
- Keep test builds simple and reproducible: compile, then run, with minimal environment mutation.

## Platform-Specific Rules

### Linux
- Toolchain: system GCC/Clang on the CI image.
- System deps: install via the OS package manager.
- Link flags (typical):
  - `--passL:"-l<systemlib>"`
  - `--passL:"-L<local_lib_dir> -l<locallib>"`
- Runtime: copy local shared libraries next to the executable when used.
- Incompatible: rpath pointing to build-tree-only locations.

### macOS
- Toolchain: Apple Clang on the CI image.
- System deps: install via the platform’s package manager (e.g., Homebrew).
- Include/link flags (typical):
  - `--passC:"-I" & staticExec("<pkg-manager> --prefix <formula>") & "/include"`
  - `--passL:"-L" & staticExec("<pkg-manager> --prefix <formula>") & "/lib"`
  - `--passL:"-l<systemlib>"`
  - `--passL:"-L<local_lib_dir> -l<locallib>"`
- Runtime: copy local shared libraries next to the executable.
- Incompatible: relying on `DYLD_LIBRARY_PATH` or full-path linking to a `.dylib`.

### Windows
- Toolchain: MinGW64 as used by Nim on CI.
- System deps: install via a package manager (e.g., Chocolatey) with fixed install roots.
- Include/link flags (typical):
  - `--passC:"-I<dep_root>/include"`
  - `--passL:"-L<dep_root>/lib"`
  - `--passL:"-l<systemlib>"`
  - `--passL:"<local_lib_dir>/<name>.dll.lib"` (for DLL import libraries)
- Runtime: copy required `.dll` files next to the executable.
- Incompatible: MSYS2 toolchains.

## How to Locate Include/Lib Directories
- Use explicit, deterministic paths:
  - Linux: package manager default locations (`/usr/include`, `/usr/lib`) via toolchain search.
  - macOS: resolve prefixes via `staticExec("<pkg-manager> --prefix <formula>")`.
- Windows: use the known install root from the package manager (avoid probing `PATH`).
- For vendored libs, always prefer repository-relative paths under `third_party/`.

## Anti-Patterns
- Embedding `-l<name>` inside `-L...` strings.
- Relying on environment variables for runtime library discovery.
- Using build-tree-only rpaths or absolute paths to shared libraries.
