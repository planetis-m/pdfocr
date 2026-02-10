## Hardcoded constants from SPEC.md.

const
  API_URL* = "https://api.deepinfra.com/v1/openai/chat/completions"
  MODEL* = "allenai/olmOCR-2-7B-1025"

  MAX_INFLIGHT* = 32
  WINDOW* = 64
  HIGH_WATER* = 64
  LOW_WATER* = 16
  # WINDOW + bounded channel capacities are the core memory bound.

  CONNECT_TIMEOUT_MS* = 10_000
  TOTAL_TIMEOUT_MS* = 120_000
  MULTI_WAIT_MAX_MS* = 250

  MAX_RETRIES* = 5
  RETRY_BASE_DELAY_MS* = 500
  RETRY_MAX_DELAY_MS* = 20_000

  RENDER_SCALE* = 2.0
  RENDER_DPI* = 144
  RENDER_FLAGS* = 0
  RENDER_ROTATE* = 0
  RENDER_PIXEL_FORMAT* = "BGR"
  WEBP_QUALITY* = 80.0'f32

  EXIT_ALL_OK* = 0
  EXIT_HAS_PAGE_ERRORS* = 2
  EXIT_FATAL_RUNTIME* = 3

static:
  doAssert HIGH_WATER <= WINDOW
  doAssert LOW_WATER < HIGH_WATER
