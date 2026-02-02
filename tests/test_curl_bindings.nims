# config.nims for test_curl_bindings.nim

import strutils

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
  let curlRoot = staticExec("powershell -NoProfile -Command \"(Get-ChildItem 'C:/ProgramData/chocolatey/lib/curl/tools' -Directory | Select-Object -First 1).FullName\"").strip()
  switch("passC", "-I" & curlRoot & "/include")
  switch("passL", "-L" & curlRoot & "/lib")
else:
  # Linux: system libcurl
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
