import pdfocr/[bindings/curl, constants, curl, errors, network_scheduler]

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

  doAssert slidingWindowAllows(63, 0)
  doAssert not slidingWindowAllows(64, 0)
  doAssert slidingWindowAllows(110, 47)
  doAssert not slidingWindowAllows(111, 47)

when isMainModule:
  main()
