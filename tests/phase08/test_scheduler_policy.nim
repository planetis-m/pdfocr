import std/atomics
import pdfocr/[bindings/curl, constants, curl, errors, network_scheduler, types]

proc main() =
  doAssert classifyCurlErrorKind(CURLE_OPERATION_TIMEDOUT) == TIMEOUT
  doAssert classifyCurlErrorKind(CURLE_COULDNT_CONNECT) == NETWORK_ERROR

  doAssert httpStatusRetryable(Http429)
  doAssert httpStatusRetryable(Http500)
  doAssert httpStatusRetryable(Http503)
  doAssert not httpStatusRetryable(Http400)
  doAssert not httpStatusRetryable(Http404)

  doAssert backoffBaseMs(1) == RETRY_BASE_DELAY_MS
  doAssert backoffBaseMs(2) == RETRY_BASE_DELAY_MS * 2
  doAssert backoffBaseMs(3) == RETRY_BASE_DELAY_MS * 4
  doAssert backoffBaseMs(20) == RETRY_MAX_DELAY_MS
  for attempt in 1 .. 20:
    let base = backoffBaseMs(attempt)
    doAssert base <= RETRY_MAX_DELAY_MS
  doAssert MAX_INFLIGHT > 0
  doAssert MULTI_WAIT_MAX_MS > 0

  doAssert not abortRequested()
  AbortSignal.store(1)
  doAssert abortRequested()
  AbortSignal.store(0)

when isMainModule:
  main()
