const
  DefaultConfigPath* = "config.json"

  ApiUrl* = "https://api.deepinfra.com/v1/openai/chat/completions"
  Model* = "allenai/olmOCR-2-7B-1025"
  Prompt* = "Extract all readable text exactly."
  MaxInflight* = 32
  TotalTimeoutMs* = 120_000
  MaxRetries* = 5
  MaxOutputTokens* = 1024
  RenderScale* = 2.0
  WebpQuality* = 80.0'f32

  ExitAllOk* = 0
  ExitPartialFailure* = 2
  ExitFatalRuntime* = 3
