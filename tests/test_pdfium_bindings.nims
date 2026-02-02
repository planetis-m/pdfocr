# config.nims for test_pdfium_bindings.nim

import strutils

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# JPEG library (used by shared code paths)
switch("passL", "-ljpeg")

when defined(macosx):
  # macOS: jpeg-turbo from Homebrew
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows: MinGW-Builds + libjpeg-turbo from chocolatey
  switch("gcc.path", "C:/mingw64/bin")
  switch("passC", "-IC:/libjpeg-turbo64/include")
  switch("passL", "-LC:/libjpeg-turbo64/lib")
  # Windows: PDFium library is pdfium.dll.lib
  switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  # Linux: system libjpeg
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  let testDir = staticExec("pwd").strip()
  switch("passL", "-L" & testDir & " -lpdfium")
