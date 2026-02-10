import ./types

# Writer is the exclusive stdout owner and emits results in ascending seq_id order.
proc runWriter*(ctx: WriterContext) {.thread.} =
  discard ctx
