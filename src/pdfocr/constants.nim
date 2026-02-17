## Hardcoded constants from SPEC.md.

const
  ApiUrl* = "https://api.deepinfra.com/v1/openai/chat/completions"
  Model* = "allenai/olmOCR-2-7B-1025"

  MaxInflight* = 32

  ConnectTimeoutMs* = 10_000
  TotalTimeoutMs* = 120_000
  MultiWaitMaxMs* = 250

  MaxRetries* = 5
  RetryBaseDelayMs* = 500
  RetryMaxDelayMs* = 20_000

  RenderScale* = 2.0
  RenderFlags* = 0
  RenderRotate* = 0
  WebpQuality* = 80.0'f32

  ExitAllOk* = 0
  ExitHasPageErrors* = 2
  ExitFatalRuntime* = 3
