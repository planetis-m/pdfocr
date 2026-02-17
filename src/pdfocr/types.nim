import std/atomics
import threading/channels
import ./[errors, curl]

type
  SeqId* = int

  RuntimeConfig* = object
    inputPath*: string
    apiKey*: string
    selectedPages*: seq[int] # seq_id -> selectedPages[seq_id]
    selectedCount*: int

  OcrTaskKind* = enum
    otkPage,
    otkStop

  OcrTask* = object
    kind*: OcrTaskKind
    seqId*: SeqId
    page*: int
    webpBytes*: seq[byte]

  PageStatus* = enum
    psOk,
    psError

  PageResult* = object
    seqId*: SeqId
    page*: int
    status*: PageStatus
    attempts*: int
    text*: string
    errorKind*: ErrorKind
    errorMessage*: string
    httpStatus*: HttpCode

  NetworkWorkerContext* = object
    taskCh*: Chan[OcrTask]
    resultCh*: Chan[PageResult]
    apiKey*: string

# Shared atomics: NextToWrite is correctness-critical.
var
  NextToWrite*: Atomic[int]
  OkCount*: Atomic[int]
  ErrCount*: Atomic[int]
  RetryCount*: Atomic[int]
  InflightCount*: Atomic[int]

proc resetSharedAtomics*() =
  NextToWrite.store(0, moRelaxed)
  OkCount.store(0, moRelaxed)
  ErrCount.store(0, moRelaxed)
  RetryCount.store(0, moRelaxed)
  InflightCount.store(0, moRelaxed)

# Channel payloads intentionally use value types / strings / byte sequences only.
