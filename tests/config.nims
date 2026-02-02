# config.nims for tests
# This file configures Nim compiler options for the tests directory

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# --- Platform-specific settings ---
when defined(macosx):
  # macOS: set rpath before linking, and jpeg-turbo from Homebrew
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib")
  switch("passL", "-ljpeg")
  switch("passL", "-Wl,-rpath,@loader_path/../third_party/pdfium/lib")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows: Configure Nim to use MSYS2 MINGW64 gcc toolchain
  # This ensures consistent C runtime between Nim stdlib and external libraries
  switch("gcc.path", "/mingw64/bin")
  switch("gcc.options.always", "-I/mingw64/include")
  switch("gcc.options.linker", "-L/mingw64/lib")
  switch("passL", "-ljpeg")
  # PDFium library is named pdfium.dll.lib on Windows
  switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  # Linux and other Unix-like systems
  switch("passL", "-Wl,-rpath,\\$ORIGIN/../third_party/pdfium/lib")
  switch("passL", "-ljpeg")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
