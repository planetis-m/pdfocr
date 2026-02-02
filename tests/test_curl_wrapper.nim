import pdfocr/curl

proc writeSink(buffer: ptr char, size: csize_t, nitems: csize_t, outstream: pointer): csize_t {.cdecl.} =
  result = size * nitems

proc main() =
  initCurlGlobal()

  var easy = initEasy()
  var headers: CurlSlist

  setUrl(easy, "https://example.com")
  setPostFields(easy, "{\"ok\":true}")
  setWriteCallback(easy, writeSink, nil)
  setTimeoutMs(easy, 1000)
  setConnectTimeoutMs(easy, 1000)
  setSslVerify(easy, true, true)
  setAcceptEncoding(easy, "")

  addHeader(headers, "Content-Type: application/json")
  setHeaders(easy, headers)

  free(headers)
  close(easy)
  cleanupCurlGlobal()

when isMainModule:
  main()
