# config.nims for src/
# This file configures Nim compiler options for the main application
import mimalloc/config

# threading/channels requires ARC/ORC.
switch("mm", "arc")

# libcurl
switch("passL", "-lcurl")
switch("passC", "-DCURL_DISABLE_TYPECHECK")
switch("passL", "-lwebp")

# eminim: allow ignoring unknown/extra fields in API responses
switch("define", "emiLenient")

# --- Platform-specific settings ---
when defined(macosx):
  switch("passC", "-I" & staticExec("brew --prefix curl") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix curl") & "/lib")
  switch("passC", "-I" & staticExec("brew --prefix webp") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix webp") & "/lib")
  switch("passL", "-L./third_party/pdfium/lib -lpdfium")
elif defined(windows):
  switch("gcc.path", "C:/mingw64/bin")
  let curlRoot = getEnv("CURL_ROOT", "C:/ProgramData/chocolatey/lib/curl/tools")
  switch("passC", "-I" & curlRoot & "/include")
  switch("passL", "-L" & curlRoot & "/lib")
  switch("passC", "-I./third_party/libwebp/include")
  switch("passL", "./third_party/libwebp/lib/libwebp.lib")
  # Windows: PDFium library is pdfium.dll.lib
  switch("passL", "./third_party/pdfium/lib/pdfium.dll.lib")
else:
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  switch("passL", "-L./third_party/pdfium/lib -lpdfium")

when defined(threadSanitizer) or defined(addressSanitizer):
  when defined(windows):
    {.warning: "Google Sanitizers (ASan/TSan) are not supported on Windows.".}
  else:
    # Logic for Linux/macOS
    switch("cc", "clang")
    switch("debugger", "native")
    switch("define", "noSignalHandler")
    switch("define", "useMalloc")

    when defined(threadSanitizer):
      switch("passC", "-fsanitize=thread -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer")
      switch("passL", "-fsanitize=thread -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer")

    when defined(addressSanitizer):
      switch("passC", "-fsanitize=address -fno-omit-frame-pointer")
      switch("passL", "-fsanitize=address -fno-omit-frame-pointer")
