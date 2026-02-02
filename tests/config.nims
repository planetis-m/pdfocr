# config.nims for tests
# This file configures Nim compiler options for the tests directory

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# --- Platform-specific settings ---
when defined(macosx):
  # macOS: set rpath before linking, and jpeg-turbo from Homebrew
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib -ljpeg")
  switch("passL", "-Wl,-rpath,@loader_path/../third_party/pdfium/lib")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows: Use pre-installed MinGW-Builds at C:\mingw64
  # libjpeg-turbo from chocolatey is at C:\tools\jpeg-turbo
  switch("gcc.path", "C/mingw64/bin")
  switch("passC", "-Ic/tools/jpeg-turbo/include")
  switch("passL", "-Lc/tools/jpeg-turbo/lib -ljpeg")
  # PDFium library is named pdfium.dll.lib on Windows
  switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  # Linux and other Unix-like systems
  switch("passL", "-Wl,-rpath,\\$ORIGIN/../third_party/pdfium/lib")
  switch("passL", "-ljpeg")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
