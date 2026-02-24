proc runTest(cmd: string) =
  echo "Running: " & cmd
  exec cmd

task test, "Run CI tests (network live tests disabled)":
  runTest "nim c -r test_page_selection.nim"
  runTest "nim c -r test_retry_and_errors.nim"
  runTest "nim c -r test_request_id_codec.nim"
