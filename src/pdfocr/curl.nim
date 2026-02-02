# Ergonomic libcurl helpers built on top of the raw bindings.

import ./wrappers/curl

type
  CurlEasy* = object
    raw*: CURL
    postData*: string
    errorBuf*: array[256, char]

  CurlSlist* = object
    raw*: ptr curl_slist

proc checkCurl*(code: CURLcode; context: string) =
  if code != CURLE_OK:
    let msg = $curl_easy_strerror(code)
    raise newException(IOError, context & ": " & msg)

proc initCurlGlobal*(flags: culong = CURL_GLOBAL_DEFAULT) =
  checkCurl(curl_global_init(flags), "curl_global_init failed")

proc cleanupCurlGlobal*() =
  curl_global_cleanup()

proc initEasy*(): CurlEasy =
  result.raw = curl_easy_init()
  if pointer(result.raw) == nil:
    raise newException(IOError, "curl_easy_init failed")
  discard curl_easy_setopt(result.raw, CURLOPT_ERRORBUFFER, addr result.errorBuf[0])
  discard curl_easy_setopt(result.raw, CURLOPT_NOSIGNAL, clong(1))

proc close*(easy: var CurlEasy) =
  if pointer(easy.raw) != nil:
    curl_easy_cleanup(easy.raw)
    easy.raw = cast[CURL](nil)
    easy.postData.setLen(0)
    easy.errorBuf = default(array[256, char])

proc setUrl*(easy: var CurlEasy; url: string) =
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_URL, url.cstring), "CURLOPT_URL failed")

proc setWriteCallback*(easy: var CurlEasy; cb: curl_write_callback; userdata: pointer) =
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_WRITEFUNCTION, cb), "CURLOPT_WRITEFUNCTION failed")
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_WRITEDATA, userdata), "CURLOPT_WRITEDATA failed")

proc setPostFields*(easy: var CurlEasy; data: string) =
  easy.postData = data
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_POST, clong(1)), "CURLOPT_POST failed")
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_POSTFIELDS, easy.postData.cstring), "CURLOPT_POSTFIELDS failed")
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_POSTFIELDSIZE, clong(easy.postData.len)), "CURLOPT_POSTFIELDSIZE failed")

proc setHeaders*(easy: var CurlEasy; headers: CurlSlist) =
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_HTTPHEADER, headers.raw), "CURLOPT_HTTPHEADER failed")

proc setTimeoutMs*(easy: var CurlEasy; timeoutMs: int) =
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_TIMEOUT_MS, clong(timeoutMs)), "CURLOPT_TIMEOUT_MS failed")

proc setConnectTimeoutMs*(easy: var CurlEasy; timeoutMs: int) =
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_CONNECTTIMEOUT_MS, clong(timeoutMs)), "CURLOPT_CONNECTTIMEOUT_MS failed")

proc setSslVerify*(easy: var CurlEasy; verifyPeer: bool; verifyHost: bool) =
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_SSL_VERIFYPEER, clong(if verifyPeer: 1 else: 0)),
    "CURLOPT_SSL_VERIFYPEER failed")
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_SSL_VERIFYHOST, clong(if verifyHost: 2 else: 0)),
    "CURLOPT_SSL_VERIFYHOST failed")

proc setAcceptEncoding*(easy: var CurlEasy; encoding: string) =
  checkCurl(curl_easy_setopt(easy.raw, CURLOPT_ACCEPT_ENCODING, encoding.cstring), "CURLOPT_ACCEPT_ENCODING failed")

proc perform*(easy: var CurlEasy) =
  checkCurl(curl_easy_perform(easy.raw), "curl_easy_perform failed")

proc responseCode*(easy: CurlEasy): int =
  var code: clong
  checkCurl(curl_easy_getinfo(easy.raw, CURLINFO_RESPONSE_CODE, addr code),
    "CURLINFO_RESPONSE_CODE failed")
  int(code)

proc addHeader*(list: var CurlSlist; headerLine: string) =
  list.raw = curl_slist_append(list.raw, headerLine.cstring)
  if list.raw.isNil:
    raise newException(IOError, "curl_slist_append failed")

proc free*(list: var CurlSlist) =
  if not list.raw.isNil:
    curl_slist_free_all(list.raw)
    list.raw = nil
