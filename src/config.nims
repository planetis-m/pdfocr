# config.nims for src/
# This file configures Nim compiler options for the main application

# threading/channels requires ARC/ORC.
switch("mm", "arc")

# JPEG library
switch("passL", "-ljpeg")
# libcurl
switch("passL", "-lcurl")

# --- Platform-specific settings ---
when defined(macosx):
  # macOS: jpeg-turbo from Homebrew
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib")
  switch("passC", "-I" & staticExec("brew --prefix curl") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix curl") & "/lib")
  switch("passL", "-L./third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows: MinGW-Builds + libjpeg-turbo from chocolatey
  switch("gcc.path", "C:/mingw64/bin")
  switch("passC", "-IC:/libjpeg-turbo64/include")
  switch("passL", "-LC:/libjpeg-turbo64/lib")
  let curlRoot = getEnv("CURL_ROOT", "C:/ProgramData/chocolatey/lib/curl/tools")
  switch("passC", "-I" & curlRoot & "/include")
  switch("passL", "-L" & curlRoot & "/lib")
  # Windows: PDFium library is pdfium.dll.lib
  switch("passL", "./third_party/pdfium/lib/pdfium.dll.lib")
else:
  # Linux: system libjpeg
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  switch("passL", "-L./third_party/pdfium/lib -lpdfium")
