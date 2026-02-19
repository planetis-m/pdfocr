# config.nims for src/
# This file configures Nim compiler options for the main application.

# threading/channels supports multiple ARC-family memory models.
# This project intentionally pins `atomicArc` for thread-safe cross-thread refs.
switch("mm", "atomicArc")

# Allocator selection (`useMimalloc` / `useMalloc`) is set in top-level
# `config.nims` (outer scope) or by explicit CLI `-d:` flags.
import mimalloc/config

# libcurl
switch("passC", "-DCURL_DISABLE_TYPECHECK")

when not defined(windows):
  switch("passL", "-lcurl")
  switch("passL", "-lwebp")
  switch("passL", "-lpdfium")

# jsonx: allow ignoring unknown/extra fields in API responses
switch("define", "jsonxLenient")

# --- Platform-specific settings ---
when defined(macosx):
  switch("passC", "-I" & staticExec("brew --prefix curl") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix curl") & "/lib")
  switch("passC", "-I" & staticExec("brew --prefix webp") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix webp") & "/lib")
  switch("passL", "-L./third_party/pdfium/lib")
elif defined(windows):
  switch("cc", "vcc")
  let vcpkgRoot = getEnv("VCPKG_ROOT", "C:/vcpkg/installed/x64-windows-release")
  switch("passC", "-I" & vcpkgRoot & "/include")
  switch("passL", vcpkgRoot & "/lib/libcurl.lib")
  switch("passL", vcpkgRoot & "/lib/libwebp.lib")
  # Windows: PDFium library is pdfium.dll.lib
  switch("passL", "./third_party/pdfium/lib/pdfium.dll.lib")
else:
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  switch("passL", "-L./third_party/pdfium/lib")

when defined(threadSanitizer) or defined(addressSanitizer):
  switch("debugger", "native")
  switch("define", "noSignalHandler")

  when defined(windows):
    when defined(addressSanitizer):
      switch("passC", "/fsanitize=address")
    else:
      {.warning: "Thread Sanitizer is not supported on Windows.".}
  else:
    # Logic for Linux/macOS
    switch("cc", "clang")
    when defined(threadSanitizer):
      switch("passC", "-fsanitize=thread -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer")
      switch("passL", "-fsanitize=thread -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer")
    elif defined(addressSanitizer):
      switch("passC", "-fsanitize=address -fno-omit-frame-pointer")
      switch("passL", "-fsanitize=address -fno-omit-frame-pointer")
