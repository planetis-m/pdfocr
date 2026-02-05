# config.nims for test_jpeglib.nim

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# JPEG library


when defined(macosx):
  # macOS: jpeg-turbo from Homebrew
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib")
  switch("passL", "-ljpeg")
elif defined(windows):
  # Windows: MinGW-Builds + libjpeg-turbo (official GCC build)
  switch("passC", "-IC:/libjpeg-turbo-gcc64/include")
else:
  # Linux: system libjpeg
  switch("passL", "-ljpeg")

when defined(addressSanitizer):
  when defined(windows):
    {.warning: "Google Sanitizers (ASan) are not supported on Windows.".}
  else:
    # Logic for Linux/macOS
    switch("cc", "clang")
    switch("debugger", "native")
    switch("define", "noSignalHandler")
    switch("define", "useMalloc")
    switch("passC", "-fsanitize=address -fno-omit-frame-pointer")
    switch("passL", "-fsanitize=address -fno-omit-frame-pointer")
