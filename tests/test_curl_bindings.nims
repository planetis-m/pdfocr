# config.nims for test_curl_bindings.nim

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# libcurl
switch("passL", "-lcurl")

when defined(macosx):
  switch("passC", "-I" & staticExec("brew --prefix curl") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix curl") & "/lib")
elif defined(windows):
  # Windows: MinGW-Builds + curl from chocolatey
  switch("gcc.path", "C:/mingw64/bin")
  let curlRoot = "C:/ProgramData/chocolatey/lib/curl/tools/curl-8.18.0_1-win64-mingw"
  switch("passC", "-I" & curlRoot & "/include")
  switch("passL", "-L" & curlRoot & "/lib")
else:
  # Linux: system libcurl
  discard
