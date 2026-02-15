import pdfocr/curl

proc writeSink(buffer: ptr char, size: csize_t, nitems: csize_t, outstream: pointer): csize_t {.cdecl.} =
  result = size * nitems

proc main() =
  initCurlGlobal()
  try:
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
    removeHandle(multi, easy)

    # Reconfigure the same easy handle after reset to ensure safe reuse.
    reset(easy)
    setUrl(easy, "https://example.com/reuse")
    setPostFields(easy, "{\"reuse\":true}")
    setWriteCallback(easy, writeSink, nil)
    setTimeoutMs(easy, 1000)
    setConnectTimeoutMs(easy, 1000)
    setSslVerify(easy, true, true)
    setAcceptEncoding(easy, "")
    setHeaders(easy, headers)
    addHandle(multi, easy)
    removeHandle(multi, easy)
  finally:
    cleanupCurlGlobal()

when isMainModule:
  main()
