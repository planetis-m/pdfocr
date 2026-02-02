# config.nims for tests
# This file configures Nim compiler options for the tests directory

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# JPEG library
switch("passL", "-ljpeg")

# --- Platform-specific settings ---
when defined(macosx):
  # macOS: set rpath before linking, and jpeg-turbo from Homebrew
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib")
  # PDFium: rpath must come before -lpdfium for dyld to find it at runtime
  switch("passL", "-Wl,-rpath,@loader_path/../third_party/pdfium/lib")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows with MSYS2/UCRT64 - jpeg-turbo paths
  switch("passC", "-IC:/msys64/ucrt64/include")
  switch("passL", "-LC:/msys64/ucrt64/lib")
  # PDFium on Windows
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
else:
  # Linux and other Unix-like systems
  switch("passL", "-Wl,-rpath,\\$ORIGIN/../third_party/pdfium/lib")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
