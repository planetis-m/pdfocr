# config.nims for test_curl_bindings.nim

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# libcurl
switch("passL", "-lcurl")

when defined(macosx):
  switch("passC", "-I" & staticExec("brew --prefix curl") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix curl") & "/lib")
elif defined(windows):
  # Windows: MinGW-Builds + curl from vcpkg
  switch("gcc.path", "C:/mingw64/bin")
  let vcpkgRoot = getEnv("VCPKG_ROOT", "C:/vcpkg")
  let vcpkgTriplet = getEnv("VCPKG_DEFAULT_TRIPLET", "x64-mingw")
  let vcpkgInstalled = vcpkgRoot & "/installed/" & vcpkgTriplet
  switch("passC", "-I" & vcpkgInstalled & "/include")
  switch("passL", "-L" & vcpkgInstalled & "/lib")
else:
  # Linux: system libcurl
  discard
