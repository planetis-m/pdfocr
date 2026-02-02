import pdfocr/bindings/curl

proc writeSink(buffer: ptr char, size: csize_t, nitems: csize_t, outstream: pointer): csize_t {.cdecl.} =
  result = size * nitems

proc main() =
  let globalCode = curl_global_init(CURL_GLOBAL_DEFAULT.culong)
  doAssert globalCode == CURLE_OK

  let easy = curl_easy_init()
  doAssert pointer(easy) != nil

  var errbuf: array[256, char]
  let url = cstring("https://example.com")
  let body = cstring("{\"ok\":true}")

  discard curl_easy_setopt(easy, CURLOPT_URL, url)
  discard curl_easy_setopt(easy, CURLOPT_POST, clong(1))
  discard curl_easy_setopt(easy, CURLOPT_POSTFIELDS, body)
  discard curl_easy_setopt(easy, CURLOPT_POSTFIELDSIZE, clong(len($body)))
  discard curl_easy_setopt(easy, CURLOPT_ERRORBUFFER, addr errbuf[0])
  discard curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, writeSink)
  discard curl_easy_setopt(easy, CURLOPT_WRITEDATA, nil)
  discard curl_easy_setopt(easy, CURLOPT_NOSIGNAL, clong(1))
  discard curl_easy_setopt(easy, CURLOPT_TIMEOUT_MS, clong(1000))
  discard curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT_MS, clong(1000))

  var headers: ptr curl_slist
  headers = curl_slist_append(headers, cstring("Content-Type: application/json"))
  discard curl_easy_setopt(easy, CURLOPT_HTTPHEADER, headers)

  let multi = curl_multi_init()
  doAssert pointer(multi) != nil
  discard curl_multi_add_handle(multi, easy)
  discard curl_multi_remove_handle(multi, easy)
  discard curl_multi_cleanup(multi)

  curl_slist_free_all(headers)
  curl_easy_cleanup(easy)
  curl_global_cleanup()

when isMainModule:
  main()
