import std/monotimes
import threading/channels
import std/deques
import pdfocr/[types, network_worker]

proc makeTask(id: int): Task =
  Task(pageId: id, pageNumberUser: id + 1, attempt: 0, jpegBytes: @[], createdAt: getMonoTime())

proc main() =
  let inputChan = newChan[InputMessage](Positive(10))
  var reservoir = initDeque[Task]()
  var inputDone = false

  inputChan.send(InputMessage(kind: imTaskBatch, tasks: @[makeTask(0), makeTask(1), makeTask(2)]))
  refillReservoir(reservoir, inputChan, lowWater = 2, highWater = 4, inputDone = inputDone)
  doAssert reservoir.len == 3
  doAssert inputDone == false

  discard reservoir.popFirst()
  discard reservoir.popFirst()
  doAssert reservoir.len == 1

  inputChan.send(InputMessage(kind: imTaskBatch, tasks: @[makeTask(3), makeTask(4), makeTask(5)]))
  refillReservoir(reservoir, inputChan, lowWater = 2, highWater = 4, inputDone = inputDone)
  doAssert reservoir.len == 4

  discard reservoir.popFirst()
  discard reservoir.popFirst()
  discard reservoir.popFirst()
  doAssert reservoir.len == 1

  inputChan.send(InputMessage(kind: imInputDone))
  refillReservoir(reservoir, inputChan, lowWater = 2, highWater = 4, inputDone = inputDone)
  doAssert inputDone == true

when isMainModule:
  main()
