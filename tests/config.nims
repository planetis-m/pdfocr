# config.nims for tests
# This file configures Nim compiler options for the tests directory

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# --- Platform-specific settings ---
when defined(macosx):
  # macOS: set rpath before linking, and jpeg-turbo from Homebrew
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib")
  switch("passL", "-Wl,-rpath,@loader_path/../third_party/pdfium/lib")
  switch("passL", "-ljpeg")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows: PDFium library is named pdfium.dll.lib (not libpdfium.a)
  # Rely on MSYS2 environment for jpeg paths
  switch("passL", "-ljpeg")
  switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  # Linux and other Unix-like systems
  switch("passL", "-Wl,-rpath,\\$ORIGIN/../third_party/pdfium/lib")
  switch("passL", "-ljpeg")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
