# config.nims for src/
# This file configures Nim compiler options for the main application

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
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows: MinGW-Builds + libjpeg-turbo + curl from vcpkg
  switch("gcc.path", "C:/mingw64/bin")
  let vcpkgRoot = getEnv("VCPKG_ROOT", "C:/vcpkg")
  let vcpkgTriplet = getEnv("VCPKG_DEFAULT_TRIPLET", "x64-mingw")
  let vcpkgInstalled = vcpkgRoot & "/installed/" & vcpkgTriplet
  switch("passC", "-I" & vcpkgInstalled & "/include")
  switch("passL", "-L" & vcpkgInstalled & "/lib")
  # Windows: PDFium library is pdfium.dll.lib
  switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  # Linux: system libjpeg
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
