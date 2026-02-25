const
  RequestAttemptBits* = 16
  RequestAttemptMask = (1'u64 shl RequestAttemptBits) - 1'u64
  RequestAttemptMax* = int(RequestAttemptMask)
  RequestSeqIdBits = 63 - RequestAttemptBits
  RequestSeqIdMax* = (1'i64 shl RequestSeqIdBits) - 1'i64

proc ensureRequestIdCapacity*(selectedCount: int; maxAttempts: int) =
  if selectedCount > 0 and selectedCount.int64 - 1 > RequestSeqIdMax:
    raise newException(ValueError,
      "selected page count exceeds request-id packing capacity")
  if maxAttempts > RequestAttemptMax:
    raise newException(ValueError,
      "max attempts exceeds request-id packing capacity")

proc packRequestId*(seqId: int; attempt: int): int64 =
  if seqId < 0 or seqId.int64 > RequestSeqIdMax:
    raise newException(ValueError, "seqId out of range for request id")
  if attempt < 1 or attempt > RequestAttemptMax:
    raise newException(ValueError, "attempt out of range for request id")
  let packed = (uint64(seqId) shl RequestAttemptBits) or uint64(attempt)
  result = int64(packed)

proc unpackRequestId*(requestId: int64): tuple[seqId, attempt: int] =
  let packed = cast[uint64](requestId)
  result = (
    seqId: int(packed shr RequestAttemptBits),
    attempt: int(packed and RequestAttemptMask)
  )
