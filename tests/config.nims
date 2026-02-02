# config.nims for tests
# This file configures Nim compiler options for the tests directory

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

# --- Platform-specific settings ---
when defined(macosx):
  # macOS: jpeg-turbo from Homebrew
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib -ljpeg")
  # PDFium - simple linking, will copy dylib next to exe
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows: MinGW-Builds + libjpeg-turbo from chocolatey
  switch("gcc.path", "C:/mingw64/bin")
  switch("passC", "-IC:/libjpeg-turbo64/include")
  switch("passL", "-LC:/libjpeg-turbo64/lib -ljpeg")
  # PDFium - simple linking, will copy dll next to exe
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
else:
  # Linux and other Unix-like systems
  switch("passL", "-ljpeg")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
