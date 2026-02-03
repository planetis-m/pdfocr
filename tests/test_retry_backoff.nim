import pdfocr/network_worker

proc main() =
  doAssert computeBackoffMs(0, 500, 20_000) == 500
  doAssert computeBackoffMs(1, 500, 20_000) == 500
  doAssert computeBackoffMs(2, 500, 20_000) == 1000
  doAssert computeBackoffMs(3, 500, 20_000) == 2000
  doAssert computeBackoffMs(6, 500, 20_000) == 16_000
  doAssert computeBackoffMs(10, 500, 20_000) == 20_000

  let delay = computeBackoffMs(4, 500, 20_000)
  let jitterMax = delay div 2
  doAssert jitterMax == 2000
  doAssert delay + jitterMax <= 20_000

when isMainModule:
  main()
