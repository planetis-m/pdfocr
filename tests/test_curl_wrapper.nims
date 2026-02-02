# config.nims for test_curl_wrapper.nim

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
  let curlRoot = getEnv("CURL_ROOT")
  switch("passC", "-I" & curlRoot & "/include")
  switch("passL", "-L" & curlRoot & "/lib")
else:
  # Linux: system libcurl
  discard
