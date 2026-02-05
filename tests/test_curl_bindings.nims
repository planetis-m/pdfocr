# config.nims for test_curl_bindings.nim

# Add the src directory to the import path so tests can find the modules

# libcurl
switch("passL", "-lcurl")
switch("passC", "-DCURL_DISABLE_TYPECHECK")

when defined(macosx):
  switch("passC", "-I" & staticExec("brew --prefix curl") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix curl") & "/lib")
elif defined(windows):
  # Windows: MinGW-Builds + curl from chocolatey
  let curlRoot = getEnv("CURL_ROOT")
  switch("passC", "-I" & curlRoot & "/include")
  switch("passL", "-L" & curlRoot & "/lib")
else:
  # Linux: system libcurl
  discard
