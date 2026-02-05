# Shared config for tests.
switch("path", "$projectdir/../src")

when defined(windows):
  switch("cc", "vcc")

when defined(addressSanitizer):
  switch("debugger", "native")
  switch("define", "noSignalHandler")
  switch("define", "useMalloc")
  when defined(windows):
    switch("passC", "/fsanitize=address")
  else:
    # Logic for Linux/macOS
    switch("cc", "clang")
    switch("passC", "-fsanitize=address -fno-omit-frame-pointer")
    switch("passL", "-fsanitize=address -fno-omit-frame-pointer")
