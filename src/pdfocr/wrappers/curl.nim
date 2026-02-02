# Minimal libcurl bindings for the PDF OCR pipeline.

type
  CURL* = distinct pointer
  CURLM* = distinct pointer
  CURLcode* = cint
  CURLMcode* = cint
  CURLoption* = cint
  CURLINFO* = cint

  curl_slist* {.importc: "struct curl_slist", header: "<curl/curl.h>", incompleteStruct, pure.} = object

  CurlMsgType* = enum
    CURLMSG_NONE = 0,
    CURLMSG_DONE = 1,
    CURLMSG_LAST = 2

  CURLMsgData* {.union.} = object
    whatever*: pointer
    result*: CURLcode

  CURLMsg* {.importc: "CURLMsg", header: "<curl/multi.h>", bycopy, pure.} = object
    msg*: CurlMsgType
    easy_handle*: CURL
    data*: CURLMsgData

  curl_write_callback* = proc(buffer: ptr char, size: csize_t, nitems: csize_t, outstream: pointer): csize_t {.cdecl.}

const
  CURL_GLOBAL_SSL* = 1
  CURL_GLOBAL_WIN32* = 2
  CURL_GLOBAL_ALL* = 3
  CURL_GLOBAL_NOTHING* = 0
  CURL_GLOBAL_DEFAULT* = 3
  CURL_GLOBAL_ACK_EINTR* = 4

  CURLE_OK* = CURLcode(0)
  CURLE_COULDNT_RESOLVE_PROXY* = CURLcode(5)
  CURLE_COULDNT_RESOLVE_HOST* = CURLcode(6)
  CURLE_COULDNT_CONNECT* = CURLcode(7)
  CURLE_HTTP_RETURNED_ERROR* = CURLcode(22)
  CURLE_WRITE_ERROR* = CURLcode(23)
  CURLE_OPERATION_TIMEDOUT* = CURLcode(28)
  CURLE_SSL_CONNECT_ERROR* = CURLcode(35)
  CURLE_ABORTED_BY_CALLBACK* = CURLcode(42)
  CURLE_SEND_ERROR* = CURLcode(55)
  CURLE_RECV_ERROR* = CURLcode(56)
  CURLE_PEER_FAILED_VERIFICATION* = CURLcode(60)
  CURLE_AGAIN* = CURLcode(81)

  CURLM_CALL_MULTI_PERFORM* = CURLMcode(-1)
  CURLM_OK* = CURLMcode(0)

  CURLOPTTYPE_LONG* = 0
  CURLOPTTYPE_OBJECTPOINT* = 10000
  CURLOPTTYPE_FUNCTIONPOINT* = 20000
  CURLOPTTYPE_OFF_T* = 30000

  CURLOPT_WRITEDATA* = CURLoption(CURLOPTTYPE_OBJECTPOINT + 1)
  CURLOPT_URL* = CURLoption(CURLOPTTYPE_OBJECTPOINT + 2)
  CURLOPT_ERRORBUFFER* = CURLoption(CURLOPTTYPE_OBJECTPOINT + 10)
  CURLOPT_WRITEFUNCTION* = CURLoption(CURLOPTTYPE_FUNCTIONPOINT + 11)
  CURLOPT_POSTFIELDS* = CURLoption(CURLOPTTYPE_OBJECTPOINT + 15)
  CURLOPT_HTTPHEADER* = CURLoption(CURLOPTTYPE_OBJECTPOINT + 23)
  CURLOPT_POST* = CURLoption(CURLOPTTYPE_LONG + 47)
  CURLOPT_POSTFIELDSIZE* = CURLoption(CURLOPTTYPE_LONG + 60)
  CURLOPT_SSL_VERIFYPEER* = CURLoption(CURLOPTTYPE_LONG + 64)
  CURLOPT_SSL_VERIFYHOST* = CURLoption(CURLOPTTYPE_LONG + 81)
  CURLOPT_NOSIGNAL* = CURLoption(CURLOPTTYPE_LONG + 99)
  CURLOPT_ACCEPT_ENCODING* = CURLoption(CURLOPTTYPE_OBJECTPOINT + 102)
  CURLOPT_PRIVATE* = CURLoption(CURLOPTTYPE_OBJECTPOINT + 103)
  CURLOPT_TIMEOUT_MS* = CURLoption(CURLOPTTYPE_LONG + 155)
  CURLOPT_CONNECTTIMEOUT_MS* = CURLoption(CURLOPTTYPE_LONG + 156)

  CURLINFO_LONG* = 0x200000
  CURLINFO_RESPONSE_CODE* = CURLINFO(CURLINFO_LONG + 2)

{.push importc, callconv: cdecl, header: "<curl/curl.h>".}

proc curl_global_init*(flags: culong): CURLcode
proc curl_global_cleanup*()

proc curl_easy_init*(): CURL
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
