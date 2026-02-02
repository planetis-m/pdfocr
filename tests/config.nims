# config.nims for tests
# This file configures Nim compiler options for the tests directory

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# JPEG library
switch("passL", "-ljpeg")

# --- Link Settings for PDFium ---
# Library is in third_party/pdfium/lib relative to project root
# When building from tests/, use ../third_party/pdfium/lib
switch("passL", "-L../third_party/pdfium/lib -lpdfium")

when defined(macosx):
  # macOS uses @loader_path for rpath in executables
  switch("passL", "-Wl,-rpath,@loader_path/../third_party/pdfium/lib")
elif defined(windows):
  # Windows doesn't use rpath; DLLs are found via PATH or alongside executable
  discard
else:
  # Linux and other Unix-like systems - use $ORIGIN for relocatable rpath
  switch("passL", "-Wl,-rpath,\\$ORIGIN/../third_party/pdfium/lib")
