# config.nims for test_webp_encode.nim

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

switch("passL", "-lwebp")

when defined(macosx):
  switch("passC", "-I" & staticExec("brew --prefix webp") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix webp") & "/lib")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
elif defined(windows):
  switch("gcc.path", "C:/mingw64/bin")
  switch("passC", "-I../third_party/libwebp/include")
  switch("passL", "../third_party/libwebp/lib/libwebp.lib")
  # Windows: PDFium library is pdfium.dll.lib
  switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
