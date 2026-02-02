# config.nims for test_jpeglib.nim

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# JPEG library
switch("passL", "-ljpeg")

when defined(macosx):
  # macOS: jpeg-turbo from Homebrew
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib")
elif defined(windows):
  # Windows: MinGW-Builds + libjpeg-turbo from vcpkg
  switch("gcc.path", "C:/mingw64/bin")
  let vcpkgRoot = getEnv("VCPKG_ROOT", "C:/vcpkg")
  let vcpkgTriplet = getEnv("VCPKG_DEFAULT_TRIPLET", "x64-mingw")
  let vcpkgInstalled = vcpkgRoot & "/installed/" & vcpkgTriplet
  switch("passC", "-I" & vcpkgInstalled & "/include")
  switch("passL", "-L" & vcpkgInstalled & "/lib")
else:
  # Linux: system libjpeg
  discard
