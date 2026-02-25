import pdfocr/retry_queue
import std/[monotimes, times]

proc main() =
  block:
    let base = getMonoTime()
    var queue = initRetryQueue()
    queue.addRetry(RetryItem(seqId: 1, attempt: 2,
      dueAt: base + initDuration(milliseconds = 300)))
    queue.addRetry(RetryItem(seqId: 2, attempt: 1,
      dueAt: base + initDuration(milliseconds = 100)))
    queue.addRetry(RetryItem(seqId: 3, attempt: 4,
      dueAt: base + initDuration(milliseconds = 200)))

    var dueAt: MonoTime
    doAssert nextRetryDueAt(queue, dueAt)
    doAssert dueAt == base + initDuration(milliseconds = 100)
    doAssert nextRetryDelayMs(queue, base) == 100
    doAssert nextRetryDelayMs(queue, base + initDuration(milliseconds = 99)) == 1
    doAssert nextRetryDelayMs(queue, base + initDuration(milliseconds = 100)) == 0

    var item: RetryItem
    doAssert not popDueRetry(queue, base + initDuration(milliseconds = 99), item)
    doAssert popDueRetry(queue, base + initDuration(milliseconds = 100), item)
    doAssert item.seqId == 2
    doAssert item.attempt == 1
    doAssert item.dueAt == base + initDuration(milliseconds = 100)

    doAssert popDueRetry(queue, base + initDuration(milliseconds = 250), item)
    doAssert item.seqId == 3
    doAssert item.attempt == 4
    doAssert item.dueAt == base + initDuration(milliseconds = 200)

    doAssert popDueRetry(queue, base + initDuration(milliseconds = 999), item)
    doAssert item.seqId == 1
    doAssert item.attempt == 2
    doAssert item.dueAt == base + initDuration(milliseconds = 300)

    doAssert not popDueRetry(queue, base + initDuration(milliseconds = 999), item)
    doAssert not nextRetryDueAt(queue, dueAt)
    doAssert nextRetryDelayMs(queue, base) == -1

  block:
    let base = getMonoTime()
    var queue = initRetryQueue()
    queue.addRetry(RetryItem(seqId: 7, attempt: 2,
      dueAt: base + initDuration(milliseconds = 50)))
    queue.addRetry(RetryItem(seqId: 8, attempt: 3,
      dueAt: base + initDuration(milliseconds = 50)))

    var first: RetryItem
    var second: RetryItem
    doAssert popDueRetry(queue, base + initDuration(milliseconds = 50), first)
    doAssert popDueRetry(queue, base + initDuration(milliseconds = 50), second)
    doAssert first.seqId == 7
    doAssert second.seqId == 8

when isMainModule:
  main()
