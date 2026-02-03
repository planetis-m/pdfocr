import std/monotimes

type
  ErrorKind* = enum
    ekPdfError,
    ekEncodeError,
    ekNetworkError,
    ekHttpError,
    ekParseError,
    ekRateLimit,
    ekTimeout

  ResultStatus* = enum
    rsSuccess,
    rsFailure

  Task* = object
    pageId*: int
    pageNumberUser*: int
    attempt*: int
    jpegBytes*: seq[byte]
    createdAt*: MonoTime

  Result* = object
    pageId*: int
    pageNumberUser*: int
    status*: ResultStatus
    text*: string
    errorKind*: ErrorKind
    errorMessage*: string
    httpStatus*: int
    attemptCount*: int
    startedAt*: MonoTime
    finishedAt*: MonoTime

  InputMessageKind* = enum
    imTaskBatch,
    imInputDone

  InputMessage* = object
    case kind*: InputMessageKind
    of imTaskBatch:
      tasks*: seq[Task]
    of imInputDone:
      discard

  OutputMessageKind* = enum
    omPageResult,
    omOutputDone

  OutputMessage* = object
    case kind*: OutputMessageKind
    of omPageResult:
      result*: Result
    of omOutputDone:
      discard
