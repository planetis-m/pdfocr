## Defaults and fixed invariants from SPEC.md.

const
  # Runtime-configurable defaults.
  DefaultConfigPath* = "config.json"
  ApiUrl* = "https://api.deepinfra.com/v1/openai/chat/completions"
  Model* = "allenai/olmOCR-2-7B-1025"
  Prompt* = "Extract all readable text exactly."
  ConnectTimeoutMs* = 10_000
  TotalTimeoutMs* = 120_000
  MaxRetries* = 5
  RetryBaseDelayMs* = 500
  RetryMaxDelayMs* = 20_000
  RenderScale* = 2.0
  WebpQuality* = 80.0'f32

  # Fixed internal scheduling invariants.
  MaxInflight* = 32
  MultiWaitMaxMs* = 250
  RenderFlags* = 0
  RenderRotate* = 0

  ExitAllOk* = 0
  ExitHasPageErrors* = 2
  ExitFatalRuntime* = 3
