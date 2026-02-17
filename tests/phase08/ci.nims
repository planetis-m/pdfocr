proc runTest(cmd: string) =
  echo "Running: " & cmd
  exec cmd

task test, "Run Phase 08 acceptance suite":
  # Fast unit/contract/policy tests first.
  runTest "nim c -r tests/phase08/test_parser_normalization.nim"
  runTest "nim c -r tests/phase08/test_data_contracts.nim"
  runTest "nim c -r tests/phase08/test_scheduler_policy.nim"

  # Integration/purity tests second.
  runTest "nim c -d:testing -r tests/phase08/test_integration_exit_codes.nim"
  runTest "nim c -d:testing -r tests/phase08/test_stdout_stderr_purity.nim"
