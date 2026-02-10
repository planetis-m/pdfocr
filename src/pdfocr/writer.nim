import std/[atomics, tables]
import threading/channels
import ./json_codec
import ./logging
import ./types

proc runWriter*(ctx: WriterContext) {.thread.} =
  let totalSelected =
    if ctx.selectedCount > 0: ctx.selectedCount
    else: ctx.selectedPages.len

  var expectedSeq = 0
  var okCount = 0
  var errCount = 0
  var bufferBySeq = initTable[int, PageResult]()

  while expectedSeq < totalSelected:
    var incoming: PageResult
    ctx.writerInCh.recv(incoming)

    if incoming.seqId < 0 or incoming.seqId >= totalSelected:
      logWarn("writer ignoring out-of-range seq_id")
      continue
    if incoming.seqId < expectedSeq:
      logWarn("writer ignoring duplicate already-written seq_id")
      continue
    if bufferBySeq.hasKey(incoming.seqId):
      logWarn("writer ignoring duplicate buffered seq_id")
      continue

    let mappedPage = ctx.selectedPages[incoming.seqId]
    if incoming.page != mappedPage:
      logWarn("writer corrected mismatched page for seq_id")
      incoming.page = mappedPage

    bufferBySeq[incoming.seqId] = incoming

    while bufferBySeq.hasKey(expectedSeq):
      let pageResult = bufferBySeq[expectedSeq]
      bufferBySeq.del(expectedSeq)

      let line = encodeResultLine(pageResult)
      stdout.write(line)
      stdout.write('\n')

      if pageResult.status == psOk:
        inc okCount
      else:
        inc errCount

      inc expectedSeq
      NEXT_TO_WRITE.store(expectedSeq, moRelaxed)
      OK_COUNT.store(okCount, moRelaxed)
      ERR_COUNT.store(errCount, moRelaxed)

  flushFile(stdout)
