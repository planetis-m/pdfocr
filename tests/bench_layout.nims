# config.nims for bench_layout.nim

let rootDir = staticExec("pwd") & "/.."

switch("path", "$projectdir/../src")

switch("passL", "-ljpeg")

when defined(macosx):
  switch("passC", "-I" & staticExec("brew --prefix jpeg-turbo") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix jpeg-turbo") & "/lib")
  switch("passL", "-L" & rootDir & "/third_party/pdfium/lib")
  switch("passL", "-lpdfium")
elif defined(windows):
  switch("gcc.path", "C:/mingw64/bin")
  switch("passC", "-IC:/libjpeg-turbo64/include")
  switch("passL", "-LC:/libjpeg-turbo64/lib")
  switch("passL", "../third_party/pdfium/lib/pdfium.dll.lib")
else:
  switch("passL", "-Wl,-rpath,\\$ORIGIN")
  switch("passL", "-L" & rootDir & "/third_party/pdfium/lib")
  switch("passL", "-lpdfium")
