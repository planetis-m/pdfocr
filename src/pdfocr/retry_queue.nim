import std/[heapqueue, monotimes, times]

type
  RetryItem* = object
    seqId*: int
    attempt*: int
    dueAt*: MonoTime

  RetryQueue* = HeapQueue[RetryItem]

proc `<`(a, b: RetryItem): bool =
  if a.dueAt != b.dueAt: a.dueAt < b.dueAt
  elif a.seqId != b.seqId: a.seqId < b.seqId
  else: a.attempt < b.attempt

proc initRetryQueue*(): RetryQueue =
  result = initHeapQueue[RetryItem]()

proc addRetry*(queue: var RetryQueue; item: sink RetryItem) =
  queue.push(item)

proc popDueRetry*(queue: var RetryQueue; now = getMonoTime();
    item: var RetryItem): bool =
  if queue.len > 0 and queue[0].dueAt <= now:
    item = queue.pop()
    result = true
  else:
    result = false

proc nextRetryDueAt*(queue: RetryQueue; dueAt: var MonoTime): bool =
  if queue.len > 0:
    dueAt = queue[0].dueAt
    result = true
  else:
    result = false

proc nextRetryDelayMs*(queue: RetryQueue; now = getMonoTime()): int =
  var dueAt: MonoTime
  if nextRetryDueAt(queue, dueAt):
    let delayMs = (dueAt - now).inMilliseconds
    if delayMs > 0:
      result = int(delayMs)
    else:
      result = 0
  else:
    result = -1
