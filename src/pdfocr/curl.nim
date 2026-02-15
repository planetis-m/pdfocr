# Ergonomic libcurl helpers built on top of the raw bindings.

import ./bindings/curl
export CurlMsgType, CURLMsg

type
  HttpCode* = distinct int

  CurlEasy* = object
    raw: CURL
    postData: string
    errorBuf: array[256, char]

  CurlMulti* = object
    raw: CURLM

  CurlSlist* = object
    raw: ptr curl_slist

const
  HttpNone* = HttpCode(0)
  Http100* = HttpCode(100)
  Http101* = HttpCode(101)
  Http102* = HttpCode(102)
  Http103* = HttpCode(103)
  Http200* = HttpCode(200)
  Http201* = HttpCode(201)
  Http202* = HttpCode(202)
  Http204* = HttpCode(204)
  Http300* = HttpCode(300)
  Http400* = HttpCode(400)
  Http401* = HttpCode(401)
  Http403* = HttpCode(403)
  Http404* = HttpCode(404)
  Http408* = HttpCode(408)
  Http409* = HttpCode(409)
  Http422* = HttpCode(422)
  Http429* = HttpCode(429)
  Http500* = HttpCode(500)
  Http502* = HttpCode(502)
  Http503* = HttpCode(503)
  Http504* = HttpCode(504)
  Http600* = HttpCode(600)

func `==`*(a, b: HttpCode): bool {.borrow.}
func `<`*(a, b: HttpCode): bool {.borrow.}
func `<=`*(a, b: HttpCode): bool {.borrow.}
proc `$`*(code: HttpCode): string =
  $int(code)

proc `=destroy`*(easy: CurlEasy) =
  if pointer(easy.raw) != nil:
    curl_easy_cleanup(easy.raw)

proc `=destroy`*(multi: CurlMulti) =
  if pointer(multi.raw) != nil:
    discard curl_multi_cleanup(multi.raw)

proc `=destroy`*(list: CurlSlist) =
  if pointer(list.raw) != nil:
    curl_slist_free_all(list.raw)

proc `=copy`*(dest: var CurlEasy; src: CurlEasy) {.error.}
proc `=copy`*(dest: var CurlMulti; src: CurlMulti) {.error.}
proc `=copy`*(dest: var CurlSlist; src: CurlSlist) {.error.}

proc `=dup`*(src: CurlEasy): CurlEasy {.error.}
proc `=dup`*(src: CurlMulti): CurlMulti {.error.}
proc `=dup`*(src: CurlSlist): CurlSlist {.error.}

proc `=sink`*(dest: var CurlEasy; src: CurlEasy) =
  `=destroy`(dest)
  dest.raw = src.raw
  dest.postData = src.postData
  dest.errorBuf = src.errorBuf

proc `=sink`*(dest: var CurlMulti; src: CurlMulti) =
  `=destroy`(dest)
  dest.raw = src.raw

proc `=sink`*(dest: var CurlSlist; src: CurlSlist) =
  `=destroy`(dest)
  dest.raw = src.raw

proc `=wasMoved`*(easy: var CurlEasy) =
  easy.raw = CURL(nil)
  easy.postData.setLen(0)
  easy.errorBuf = default(array[256, char])

proc `=wasMoved`*(multi: var CurlMulti) =
  multi.raw = CURLM(nil)

proc `=wasMoved`*(list: var CurlSlist) =
  list.raw = nil

proc checkCurl*(code: CURLcode; context: string) {.noinline.} =
  if code != CurleOk:
    let msg = $curl_easy_strerror(code)
    raise newException(IOError, context & ": " & msg)

proc checkCurlMulti*(code: CURLMcode; context: string) {.noinline.} =
  if code != CurlmOk:
    let msg = $curl_multi_strerror(code)
    raise newException(IOError, context & ": " & msg)

proc initCurlGlobal*(flags: culong = CurlGlobalDefault) =
  checkCurl(curl_global_init(flags), "curl_global_init failed")

proc cleanupCurlGlobal*() =
  curl_global_cleanup()

proc initEasy*(): CurlEasy =
  result.raw = curl_easy_init()
  if pointer(result.raw) == nil:
    raise newException(IOError, "curl_easy_init failed")
  discard curl_easy_setopt(result.raw, CurloptErrorbuffer, addr result.errorBuf[0])
  discard curl_easy_setopt(result.raw, CurloptNosignal, clong(1))

proc initMulti*(): CurlMulti =
  result.raw = curl_multi_init()
  if pointer(result.raw) == nil:
    raise newException(IOError, "curl_multi_init failed")

proc addHandle*(multi: var CurlMulti; easy: CurlEasy) =
  checkCurlMulti(curl_multi_add_handle(multi.raw, easy.raw), "curl_multi_add_handle failed")

proc removeHandle*(multi: var CurlMulti; easy: CurlEasy) =
  checkCurlMulti(curl_multi_remove_handle(multi.raw, easy.raw), "curl_multi_remove_handle failed")

proc removeHandle*(multi: var CurlMulti; msg: CURLMsg) =
  checkCurlMulti(curl_multi_remove_handle(multi.raw, msg.easy_handle), "curl_multi_remove_handle failed")

proc perform*(multi: var CurlMulti): int =
  var running: cint
  checkCurlMulti(curl_multi_perform(multi.raw, addr running), "curl_multi_perform failed")
  int(running)

proc poll*(multi: var CurlMulti; timeoutMs: int): int =
  var numfds: cint
  checkCurlMulti(
    curl_multi_poll(multi.raw, nil, 0.cuint, timeoutMs.cint, addr numfds),
    "curl_multi_poll failed"
  )
  int(numfds)

proc tryInfoRead*(multi: var CurlMulti; msg: var CURLMsg; msgsInQueue: var int): bool =
  var queue: cint
  let msgPtr = curl_multi_info_read(multi.raw, addr queue)
  msgsInQueue = int(queue)
  if msgPtr.isNil:
    return false
  msg = msgPtr[]
  true

proc setUrl*(easy: var CurlEasy; url: string) =
  checkCurl(curl_easy_setopt(easy.raw, CurloptUrl, url.cstring), "CurloptUrl failed")

proc setWriteCallback*(easy: var CurlEasy; cb: curl_write_callback; userdata: pointer) =
  checkCurl(curl_easy_setopt(easy.raw, CurloptWritefunction, cb), "CurloptWritefunction failed")
  checkCurl(curl_easy_setopt(easy.raw, CurloptWritedata, userdata), "CurloptWritedata failed")

proc setPostFields*(easy: var CurlEasy; data: string) =
  easy.postData = data
  checkCurl(curl_easy_setopt(easy.raw, CurloptPost, clong(1)), "CurloptPost failed")
  checkCurl(curl_easy_setopt(easy.raw, CurloptPostfields, easy.postData.cstring), "CurloptPostfields failed")
  checkCurl(curl_easy_setopt(easy.raw, CurloptPostfieldsize, clong(easy.postData.len)), "CurloptPostfieldsize failed")

proc setHeaders*(easy: var CurlEasy; headers: CurlSlist) =
  checkCurl(curl_easy_setopt(easy.raw, CurloptHttpheader, headers.raw), "CurloptHttpheader failed")

proc setTimeoutMs*(easy: var CurlEasy; timeoutMs: int) =
  checkCurl(curl_easy_setopt(easy.raw, CurloptTimeoutMs, clong(timeoutMs)), "CurloptTimeoutMs failed")

proc setConnectTimeoutMs*(easy: var CurlEasy; timeoutMs: int) =
  checkCurl(curl_easy_setopt(easy.raw, CurloptConnecttimeoutMs, clong(timeoutMs)), "CurloptConnecttimeoutMs failed")

proc setSslVerify*(easy: var CurlEasy; verifyPeer: bool; verifyHost: bool) =
  checkCurl(curl_easy_setopt(easy.raw, CurloptSslVerifypeer, clong(if verifyPeer: 1 else: 0)),
    "CurloptSslVerifypeer failed")
  checkCurl(curl_easy_setopt(easy.raw, CurloptSslVerifyhost, clong(if verifyHost: 2 else: 0)),
    "CurloptSslVerifyhost failed")

proc setAcceptEncoding*(easy: var CurlEasy; encoding: string) =
  checkCurl(curl_easy_setopt(easy.raw, CurloptAcceptEncoding, encoding.cstring), "CurloptAcceptEncoding failed")

proc reset*(easy: var CurlEasy) =
  curl_easy_reset(easy.raw)
  easy.postData.setLen(0)
  checkCurl(curl_easy_setopt(easy.raw, CurloptErrorbuffer, addr easy.errorBuf[0]),
    "CurloptErrorbuffer failed")
  checkCurl(curl_easy_setopt(easy.raw, CurloptNosignal, clong(1)),
    "CurloptNosignal failed")

proc setPrivate*(easy: var CurlEasy; data: pointer) =
  checkCurl(curl_easy_setopt(easy.raw, CurloptPrivate, data), "CurloptPrivate failed")

proc getPrivate*(easy: CurlEasy): pointer =
  var data: pointer
  checkCurl(curl_easy_getinfo(easy.raw, CurlinfoPrivate, addr data), "CurlinfoPrivate failed")
  data

proc perform*(easy: var CurlEasy) =
  checkCurl(curl_easy_perform(easy.raw), "curl_easy_perform failed")

proc responseCode*(easy: CurlEasy): HttpCode =
  var code: clong
  checkCurl(curl_easy_getinfo(easy.raw, CurlinfoResponseCode, addr code),
    "CurlinfoResponseCode failed")
  HttpCode(code)

proc addHeader*(list: var CurlSlist; headerLine: string) =
  list.raw = curl_slist_append(list.raw, headerLine.cstring)
  if list.raw.isNil:
    raise newException(IOError, "curl_slist_append failed")

proc handleKey*(easy: CurlEasy): uint =
  cast[uint](cast[pointer](easy.raw))

proc handleKey*(msg: CURLMsg): uint =
  cast[uint](cast[pointer](msg.easy_handle))
