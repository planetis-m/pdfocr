# config.nims for src/
# This file configures Nim compiler options for the main application
import mimalloc/config

# threading/channels requires ARC/ORC.
switch("mm", "arc")

# libcurl
switch("passC", "-DCURL_DISABLE_TYPECHECK")

when not defined(windows):
  switch("passL", "-lcurl")
  switch("passL", "-lwebp")
  switch("passL", "-lpdfium")

# eminim: allow ignoring unknown/extra fields in API responses
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
  switch("define", "useMalloc")

  when defined(windows):
    when defined(threadSanitizer):
      switch("passC", "/fsanitize=address")
    else:
      {.warning: "Thread Sanitizer is not supported on Windows.".}
  else:
    # Logic for Linux/macOS
    switch("cc", "clang")
    when defined(threadSanitizer):
      switch("passC", "-fsanitize=thread -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer")
      switch("passL", "-fsanitize=thread -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer")

    when defined(addressSanitizer):
      switch("passC", "-fsanitize=address -fno-omit-frame-pointer")
      switch("passL", "-fsanitize=address -fno-omit-frame-pointer")
