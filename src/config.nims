# config.nims for src/
# This file configures Nim compiler options for the main application

# --- Link Settings ---

# JPEG library (system library)
switch("passL", "-ljpeg")

# PDFium library (in third_party/)
# -L path is relative to compilation directory (project root)
switch("passL", "-Lthird_party/pdfium/lib -lpdfium")

# Platform-specific rpath for PDFium
# rpath is relative to executable location (src/app)
when defined(macosx):
  # macOS uses @loader_path for rpath
  # If executable is in src/, we need to go up one level to find third_party/
  switch("passL", "-Wl,-rpath,@loader_path/../third_party/pdfium/lib")
elif defined(windows):
  # Windows doesn't use rpath
  discard
else:
  # Linux and other Unix-like systems - use $ORIGIN for relocatable rpath
  switch("passL", "-Wl,-rpath,\\$ORIGIN/../third_party/pdfium/lib")
