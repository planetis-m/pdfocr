# config.nims for test_pdfium_wrapper.nim

# Add the src directory to the import path so tests can find the modules

when defined(macosx):
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  # Windows: PDFium library is pdfium.dll.lib
  switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
