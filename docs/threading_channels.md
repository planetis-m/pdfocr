# `threading/channels` API

> **Project note**: `pdfocr` uses `--mm:atomicArc` via `config.nims`.

This module implements **multi-producer, multi-consumer (MPMC) channels** backed by a shared-memory, fixed-size circular buffer. Channels provide a high-level, type-safe concurrency primitive for communication and synchronization between threads, supporting both blocking and non-blocking operations.

Internally, the implementation is based on a C-to-Nim translation of Andreas Prell’s shared-memory channel design, adapted and extended for Nim’s memory model and isolation semantics.

---

## Overview

* Channels are **typed** and **fixed-capacity**.
* Multiple producers and consumers may operate concurrently.
* Messages are transferred using **move semantics** via `Isolated[T]` to ensure thread safety.
* Both **blocking** (`send`, `recv`) and **non-blocking** (`trySend`, `tryRecv`) APIs are provided.

See also:

* [`std/isolation`](https://nim-lang.org/docs/isolation.html)

---

## Types

### `Chan[T]`

```nim
Chan[T]
```

A typed channel capable of carrying values of type `T` between threads.

* Channels are reference-counted internally.
* Copying or assigning a `Chan[T]` shares the underlying channel.
* When the last reference is destroyed, the channel’s resources are freed.

---

## Channel Creation

### `newChan`

```nim
proc newChan[T](elements: Positive = 30): Chan[T]
```

Creates and initializes a new channel with capacity for `elements` messages.

* `elements` defines the maximum number of pending messages.
* Allocation and synchronization primitives are initialized eagerly.

---

## Sending Messages

### `send`

```nim
proc send[T](c: Chan[T], src: sink Isolated[T])
```

Blocking send operation.

* Blocks until space is available in the channel.
* Transfers ownership of `src` (move semantics).
* If the channel is full, the calling thread is suspended until space becomes available.

#### Convenience template

```nim
template send[T](c: Chan[T], src: T)
```

Isolates `src` automatically before sending.

---

### `trySend`

```nim
proc trySend[T](c: Chan[T], src: sink Isolated[T]): bool
```

Non-blocking send operation.

* Attempts to enqueue a message without blocking.
* Returns `false` if the channel is full.
* On success, ownership of `src` is transferred.

#### Convenience template

```nim
template trySend[T](c: Chan[T], src: T): bool
```

Automatically isolates `src` before attempting to send.

---

### `tryTake`

```nim
proc tryTake[T](c: Chan[T], src: var Isolated[T]): bool
```

Non-blocking send that directly moves an already-isolated value.

* Suitable for non-copyable types.
* `src` must not be reused after a successful call.
* Returns `false` if the channel is full.

---

## Receiving Messages

### `recv`

```nim
proc recv[T](c: Chan[T], dst: var T)
proc recv[T](c: Chan[T]): T
```

Blocking receive operations.

* Blocks until a message becomes available.
* Removes one message from the channel.
* Either fills `dst` or returns the received value directly.

---

### `recvIso`

```nim
proc recvIso[T](c: Chan[T]): Isolated[T]
```

Blocking receive that returns the message as an isolated value.

* Useful when the received value must be forwarded to another thread.

---

### `tryRecv`

```nim
proc tryRecv[T](c: Chan[T], dst: var T): bool
```

Non-blocking receive operation.

* Attempts to receive a message without blocking.
* Returns `false` if the channel is empty.
* `dst` is unchanged on failure.

---

## Introspection

### `peek`

```nim
proc peek[T](c: Chan[T]): int
```

Returns an **approximation** of the number of messages currently buffered in the channel.

* Intended for diagnostics and heuristics.
* Not a synchronization primitive.

---

## Memory and Lifetime Semantics

* Channels use an internal atomic reference counter.
* Copying or assigning a `Chan[T]` increments the counter.
* Destruction decrements the counter; resources are freed when it reaches zero.
* Moving a channel invalidates the source reference.

---

## Representative Example

The following example demonstrates a small task system using channels:

* A main thread produces tasks.
* Multiple worker threads execute tasks.
* A single consumer thread collects results.

```nim
import std/[os, osproc]
import threading/channels

const
  NTasks = 256'i16          # int16 allows using this in a Set
  SleepDurationMS = 3
  sentmsg = "task sent"

type
  Payload = tuple[chan: Chan[int16], idx: int16]

var
  sentmessages = newSeqOfCap[string](NTasks)
  receivedmessages = newSeqOfCap[int16](NTasks)

# Worker thread executing tasks
proc runner(tasksCh: Chan[Payload]) {.thread.} =
  var p: Payload
  while true:
    tasksCh.recv(p)
    if p.idx == -1:
      break              # Stop signal
    else:
      sleep(SleepDurationMS)
      p.chan.send(p.idx) # Notify completion

# Consumer thread collecting results
proc consumer(args: tuple[resultsCh: Chan[int16], tasks: int16]) {.thread.} =
  var idx: int16
  for _ in 0..<args.tasks:
    args.resultsCh.recv(idx)
    {.gcsafe.}:
      receivedmessages.add(idx)

proc main(chanSize: Natural) =
  sentmessages.setLen(0)
  receivedmessages.setLen(0)

  var
    taskThreads = newSeq[Thread[Chan[Payload]]](countProcessors())
    tasksCh = newChan[Payload](chanSize)
    consumerTh: Thread[(Chan[int16], int16)]
    resultsCh = newChan[int16](chanSize)

  # Start consumer first to avoid blocking
  createThread(consumerTh, consumer, (resultsCh, NTasks))

  # Start worker threads
  for i in 0..high(taskThreads):
    createThread(taskThreads[i], runner, tasksCh)

  # Send tasks
  for idx in 0'i16..<NTasks:
    tasksCh.send((resultsCh, idx))
    sentmessages.add(sentmsg)

  # Send stop signals
  for _ in taskThreads:
    tasksCh.send((resultsCh, -1'i16))

  joinThreads(taskThreads)
  joinThread(consumerTh)
```

This pattern illustrates a common use case for channels: **work distribution and result aggregation** with clear ownership transfer and safe synchronization.
