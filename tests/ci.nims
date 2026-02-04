proc runTest(cmd: string) =
  echo "Running: " & cmd
  exec cmd

task test, "Run CI tests (network live tests disabled)":
  when false:
    runTest "nim c -r test_jpeglib_bindings.nim"
  when false:
    runTest "nim c -r test_jpeglib_wrapper.nim"
  runTest "nim c -r test_pdfium_bindings.nim input.pdf"
  runTest "nim c -r test_pdfium_wrapper.nim input.pdf"
  runTest "nim c -r test_curl_bindings.nim"
  runTest "nim c -r test_curl_wrapper.nim"
