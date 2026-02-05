# config.nims for test_webp_encode.nim

# Add the src directory to the import path so tests can find the modules
switch("path", "$projectdir/../src")

when defined(macosx):
  switch("passL", "-L" & staticExec("brew --prefix webp") & "/lib")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
  switch("passL", "-lwebp")
elif defined(windows):
  switch("passC", "-I../third_party/libwebp/libwebp-1.6.0-windows-x64/include")
  switch("passL", "../third_party/libwebp/libwebp-1.6.0-windows-x64/lib/libwebp.lib")
  switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  switch("passL", "-L../third_party/pdfium/lib -lpdfium")
  switch("passL", "-lwebp")
