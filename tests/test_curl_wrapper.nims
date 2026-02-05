# config.nims for test_curl_wrapper.nim

# Add the src directory to the import path so tests can find the modules

# libcurl
switch("passC", "-DCURL_DISABLE_TYPECHECK")

when defined(macosx):
  switch("passC", "-I" & staticExec("brew --prefix curl") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix curl") & "/lib")
elif defined(windows):
  # Windows: MSVC-compatible curl
  let curlRoot = getEnv("CURL_ROOT")
  switch("passC", "-I" & curlRoot & "/include")
  switch("passL", curlRoot & "/lib/libcurl.lib")
else:
  # Linux: system libcurl
  switch("passL", "-lcurl")
  discard
