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
  # Windows: MinGW-Builds + libjpeg-turbo
  switch("passC", "-IC:/libjpeg-turbo-gcc64/include")
  switch("passL", "-LC:/libjpeg-turbo-gcc64/lib")
else:
  # Linux: system libjpeg
  discard

when defined(windows):
  switch("cc", "vcc")  # Use MSVC
  switch("passC", "/fsanitize=address")

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
