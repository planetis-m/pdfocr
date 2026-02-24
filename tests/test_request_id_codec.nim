import ../src/request_id_codec

proc expectValueError(action: proc()) =
  var raised = false
  try:
    action()
  except ValueError:
    raised = true
  doAssert raised

proc main() =
  ensureRequestIdCapacity(selectedCount = 1, maxAttempts = 1)
  ensureRequestIdCapacity(selectedCount = 10_000, maxAttempts = 32)

  let requestId = packRequestId(seqId = 42, attempt = 3)
  let decoded = unpackRequestId(requestId)
  doAssert decoded.seqId == 42
  doAssert decoded.attempt == 3

  let maxRequestId = packRequestId(seqId = RequestSeqIdMax.int, attempt = RequestAttemptMax)
  let maxDecoded = unpackRequestId(maxRequestId)
  doAssert maxDecoded.seqId == RequestSeqIdMax.int
  doAssert maxDecoded.attempt == RequestAttemptMax

  expectValueError(proc() = discard packRequestId(seqId = -1, attempt = 1))
  expectValueError(proc() = discard packRequestId(seqId = 0, attempt = 0))
  expectValueError(proc() = discard packRequestId(seqId = 0, attempt = RequestAttemptMax + 1))
  expectValueError(proc() = ensureRequestIdCapacity(
    selectedCount = RequestSeqIdMax.int + 2,
    maxAttempts = 1
  ))
  expectValueError(proc() = ensureRequestIdCapacity(
    selectedCount = 1,
    maxAttempts = RequestAttemptMax + 1
  ))

when isMainModule:
  main()
