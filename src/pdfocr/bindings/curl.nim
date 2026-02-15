# Minimal libcurl bindings for the PDF OCR pipeline.

type
  CURL* = distinct pointer
  CURLM* = distinct pointer
  CURLcode* = cint
  CURLMcode* = cint
  CURLoption* = cint
  CURLINFO* = cint

  curl_slist* {.importc: "struct curl_slist", header: "<curl/curl.h>", incompleteStruct.} = object

  CurlMsgType* = enum
    CurlmsgNone = 0,
    CurlmsgDone = 1,
    CurlmsgLast = 2

  CURLMsgData* {.union.} = object
    whatever*: pointer
    result*: CURLcode

  CURLMsg* {.importc: "CURLMsg", header: "<curl/multi.h>", bycopy.} = object
    msg*: CurlMsgType
    easy_handle*: CURL
    data*: CURLMsgData

  curl_write_callback* = proc(buffer: ptr char, size: csize_t, nitems: csize_t, outstream: pointer): csize_t {.cdecl.}

const
  CurlGlobalSsl* = 1
  CurlGlobalWin32* = 2
  CurlGlobalAll* = 3
  CurlGlobalNothing* = 0
  CurlGlobalDefault* = 3
  CurlGlobalAckEintr* = 4

  CurleOk* = CURLcode(0)
  CurleCouldntResolveProxy* = CURLcode(5)
  CurleCouldntResolveHost* = CURLcode(6)
  CurleCouldntConnect* = CURLcode(7)
  CurleHttpReturnedError* = CURLcode(22)
  CurleWriteError* = CURLcode(23)
  CurleOperationTimedout* = CURLcode(28)
  CurleSslConnectError* = CURLcode(35)
  CurleAbortedByCallback* = CURLcode(42)
  CurleSendError* = CURLcode(55)
  CurleRecvError* = CURLcode(56)
  CurlePeerFailedVerification* = CURLcode(60)
  CurleAgain* = CURLcode(81)

  CurlmCallMultiPerform* = CURLMcode(-1)
  CurlmOk* = CURLMcode(0)

  CurlopttypeLong* = 0
  CurlopttypeObjectpoint* = 10000
  CurlopttypeFunctionpoint* = 20000
  CurlopttypeOffT* = 30000

  CurloptWritedata* = CURLoption(CurlopttypeObjectpoint + 1)
  CurloptUrl* = CURLoption(CurlopttypeObjectpoint + 2)
  CurloptErrorbuffer* = CURLoption(CurlopttypeObjectpoint + 10)
  CurloptWritefunction* = CURLoption(CurlopttypeFunctionpoint + 11)
  CurloptPostfields* = CURLoption(CurlopttypeObjectpoint + 15)
  CurloptHttpheader* = CURLoption(CurlopttypeObjectpoint + 23)
  CurloptPost* = CURLoption(CurlopttypeLong + 47)
  CurloptPostfieldsize* = CURLoption(CurlopttypeLong + 60)
  CurloptSslVerifypeer* = CURLoption(CurlopttypeLong + 64)
  CurloptSslVerifyhost* = CURLoption(CurlopttypeLong + 81)
  CurloptNosignal* = CURLoption(CurlopttypeLong + 99)
  CurloptAcceptEncoding* = CURLoption(CurlopttypeObjectpoint + 102)
  CurloptPrivate* = CURLoption(CurlopttypeObjectpoint + 103)
  CurloptTimeoutMs* = CURLoption(CurlopttypeLong + 155)
  CurloptConnecttimeoutMs* = CURLoption(CurlopttypeLong + 156)

  CurlinfoLong* = 0x200000
  CurlinfoResponseCode* = CURLINFO(CurlinfoLong + 2)
  CurlinfoString* = 0x100000
  CurlinfoPrivate* = CURLINFO(CurlinfoString + 21)

{.push importc, callconv: cdecl, header: "<curl/curl.h>".}

proc curl_global_init*(flags: culong): CURLcode
proc curl_global_cleanup*()

proc curl_easy_init*(): CURL
proc curl_easy_perform*(curl: CURL): CURLcode
proc curl_easy_cleanup*(curl: CURL)
proc curl_easy_reset*(curl: CURL)
proc curl_easy_setopt*(curl: CURL, option: CURLoption): CURLcode {.varargs.}
proc curl_easy_getinfo*(curl: CURL, info: CURLINFO): CURLcode {.varargs.}
proc curl_easy_strerror*(code: CURLcode): cstring

proc curl_slist_append*(list: ptr curl_slist, data: cstring): ptr curl_slist
proc curl_slist_free_all*(list: ptr curl_slist)

{.pop.}

{.push importc, callconv: cdecl, header: "<curl/multi.h>".}

proc curl_multi_init*(): CURLM
proc curl_multi_add_handle*(multi_handle: CURLM, easy_handle: CURL): CURLMcode
proc curl_multi_remove_handle*(multi_handle: CURLM, easy_handle: CURL): CURLMcode
proc curl_multi_perform*(multi_handle: CURLM, running_handles: ptr cint): CURLMcode
proc curl_multi_poll*(multi_handle: CURLM, extra_fds: pointer, extra_nfds: cuint,
                      timeout_ms: cint, numfds: ptr cint): CURLMcode
proc curl_multi_info_read*(multi_handle: CURLM, msgs_in_queue: ptr cint): ptr CURLMsg
proc curl_multi_cleanup*(multi_handle: CURLM): CURLMcode
proc curl_multi_strerror*(code: CURLMcode): cstring

{.pop.}
