# config.nims for tests
# This file configures Nim compiler options for the tests directory

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# JPEG library
switch("passL", "-ljpeg")
import strutils

# --- Platform-specific settings ---
when defined(macosx):
  # macOS: jpeg-turbo from Homebrew
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib")
  when defined(curl_test):
    switch("passC", "-I" & staticExec("brew --prefix curl") & "/include")
    switch("passL", "-L" & staticExec("brew --prefix curl") & "/lib")
    switch("passL", "-lcurl")
  when not defined(curl_only):
    switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows: MinGW-Builds + libjpeg-turbo from chocolatey
  switch("gcc.path", "C:/mingw64/bin")
  switch("passC", "-IC:/libjpeg-turbo64/include")
  switch("passL", "-LC:/libjpeg-turbo64/lib")
  when defined(curl_test):
    let curlRoot = staticExec("powershell -NoProfile -Command \"(Get-ChildItem 'C:/ProgramData/chocolatey/lib/curl/tools' -Directory | Select-Object -First 1).FullName\"").strip()
    switch("passC", "-I" & curlRoot & "/include")
    switch("passL", "-L" & curlRoot & "/lib")
    switch("passL", "-lcurl")
  # Windows: PDFium library is pdfium.dll.lib
  when not defined(curl_only):
    switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  # Linux: system libjpeg
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  when defined(curl_test):
    switch("passL", "-lcurl")
  when not defined(curl_only):
    switch("passL", "-L../third_party/pdfium/lib -lpdfium")
