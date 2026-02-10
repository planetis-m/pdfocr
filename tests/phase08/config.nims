# Shared config for Phase 08 tests.
switch("path", "$projectdir/../../src")
switch("mm", "orc")

when defined(windows):
  switch("cc", "vcc")

when defined(addressSanitizer):
  switch("debugger", "native")
  switch("define", "noSignalHandler")
  switch("define", "useMalloc")
  when defined(windows):
    switch("passC", "/fsanitize=address")
  else:
    switch("cc", "clang")
    switch("passC", "-fsanitize=address -fno-omit-frame-pointer")
    switch("passL", "-fsanitize=address -fno-omit-frame-pointer")
