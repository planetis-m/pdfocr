import pdfocr/curl

proc writeSink(buffer: ptr char, size: csize_t, nitems: csize_t, outstream: pointer): csize_t {.cdecl.} =
  result = size * nitems

proc main() =
  initCurlGlobal()
  block:
    var easy = initEasy()
    var headers: CurlSlist
    var multi = initMulti()

    setUrl(easy, "https://example.com")
    setPostFields(easy, "{\"ok\":true}")
    setWriteCallback(easy, writeSink, nil)
    setTimeoutMs(easy, 1000)
    setConnectTimeoutMs(easy, 1000)
    setSslVerify(easy, true, true)
    setAcceptEncoding(easy, "")
    setPrivate(easy, cast[pointer](1))

    addHeader(headers, "Content-Type: application/json")
    setHeaders(easy, headers)

    addHandle(multi, easy)
    discard poll(multi, 0)
    var msgsInQueue = 0
    var msg: CURLMsg
    discard tryInfoRead(multi, msg, msgsInQueue)
    discard getPrivate(easy)
    reset(easy)
    removeHandle(multi, easy)

  cleanupCurlGlobal()

when isMainModule:
  main()
