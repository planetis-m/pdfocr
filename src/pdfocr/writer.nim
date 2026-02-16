import std/[atomics, tables]
import threading/channels
import ./errors
import ./json_codec
import ./logging
import ./types

proc runWriter*(ctx: WriterContext) {.thread.} =
  try:
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
      elif incoming.seqId < expectedSeq:
        logWarn("writer ignoring duplicate already-written seq_id")
      elif bufferBySeq.hasKey(incoming.seqId):
        logWarn("writer ignoring duplicate buffered seq_id")
      else:
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
          NextToWrite.store(expectedSeq, moRelaxed)
          OkCount.store(okCount, moRelaxed)
          ErrCount.store(errCount, moRelaxed)

    flushFile(stdout)
  except CatchableError:
    ctx.fatalCh.send(FatalEvent(
      source: fesWriter,
      errorKind: NetworkError,
      message: boundedErrorMessage(getCurrentExceptionMsg())
    ))
