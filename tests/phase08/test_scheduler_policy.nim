import std/sets
import pdfocr/[bindings/curl, constants, errors, network_scheduler]

proc main() =
  doAssert classifyCurlErrorKind(CURLE_OPERATION_TIMEDOUT) == TIMEOUT
  doAssert classifyCurlErrorKind(CURLE_COULDNT_CONNECT) == NETWORK_ERROR

  doAssert httpStatusRetryable(429)
  doAssert httpStatusRetryable(500)
  doAssert httpStatusRetryable(503)
  doAssert not httpStatusRetryable(400)
  doAssert not httpStatusRetryable(404)

  doAssert backoffBaseMs(1) == RETRY_BASE_DELAY_MS
  doAssert backoffBaseMs(2) == RETRY_BASE_DELAY_MS * 2
  doAssert backoffBaseMs(3) == RETRY_BASE_DELAY_MS * 4
  doAssert backoffBaseMs(20) == RETRY_MAX_DELAY_MS
  for attempt in 1 .. 20:
    let base = backoffBaseMs(attempt)
    doAssert base <= RETRY_MAX_DELAY_MS

  let base4 = backoffBaseMs(4)
  let jitterMax = max(1, base4 div 2)
  var seen = initHashSet[int]()
  for seed in 1 .. 64:
    let d = backoffWithJitterMs(4, seed)
    doAssert d >= base4
    doAssert d <= base4 + jitterMax
    seen.incl(d)
  doAssert seen.len > 1

  doAssert slidingWindowAllows(63, 0)
  doAssert not slidingWindowAllows(64, 0)
  doAssert slidingWindowAllows(110, 47)
  doAssert not slidingWindowAllows(111, 47)

when isMainModule:
  main()
