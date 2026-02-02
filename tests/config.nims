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
elif defined(windows):
  # Windows: rely on MSYS2 environment to provide paths via C_INCLUDE_PATH/LIBRARY_PATH
  # No hardcoded paths needed when running in MSYS2 shell
  discard
else:
  # Linux and other Unix-like systems
  switch("passL", "-Wl,-rpath,\\$ORIGIN/../third_party/pdfium/lib")

# --- Link Settings for PDFium, jpeg-turbo ---
switch("passL", "-ljpeg")
switch("passL", "-L../third_party/pdfium/lib -lpdfium")
