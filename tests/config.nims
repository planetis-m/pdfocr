# config.nims for tests
# This file configures Nim compiler options for the tests directory

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

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
  when not defined(curl_only):
    switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows: MinGW-Builds + libjpeg-turbo from chocolatey
  switch("gcc.path", "C:/mingw64/bin")
  switch("passC", "-IC:/libjpeg-turbo64/include")
  switch("passL", "-LC:/libjpeg-turbo64/lib")
  switch("passC", "-IC:/ProgramData/chocolatey/lib/curl/tools/include")
  switch("passL", "-LC:/ProgramData/chocolatey/lib/curl/tools/lib")
  # Windows: PDFium library is pdfium.dll.lib
  when not defined(curl_only):
    switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  # Linux: system libjpeg
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  when not defined(curl_only):
    switch("passL", "-L../third_party/pdfium/lib -lpdfium")
