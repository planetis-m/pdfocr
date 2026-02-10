# config.nims for test_renderer_failures.nim

when defined(windows):
  let vcpkgRoot = getEnv("VCPKG_ROOT", "C:/vcpkg/installed/x64-windows-release")
  switch("passL", vcpkgRoot & "/lib/libwebp.lib")
  switch("passL", "./third_party/pdfium/lib/pdfium.dll.lib")
else:
  switch("passL", "-lwebp")
  switch("passL", "-lpdfium")
  switch("passL", "-L./third_party/pdfium/lib")
  switch("passL", "-Wl,-rpath,\\$ORIGIN/../../third_party/pdfium/lib")
