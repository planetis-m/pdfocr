import std/[base64, os, strutils]
import pdfocr/bindings/curl

type
  RequestState = object
    response: string

proc writeCb(buffer: ptr char; size: csize_t; nitems: csize_t; userdata: pointer): csize_t {.cdecl.} =
  let total = int(size * nitems)
  if total <= 0:
    return 0
  let state = cast[ptr RequestState](userdata)
  if state != nil:
    let start = state.response.len
    state.response.setLen(start + total)
    copyMem(addr state.response[start], buffer, total)
  csize_t(total)

proc bytesFromString(raw: string): seq[byte] =
  result = newSeq[byte](raw.len)
  if raw.len == 0:
    return
  let srcPtr = cast[ptr char](addr raw[0])
  let dstPtr = cast[ptr byte](addr result[0])
  copyMem(dstPtr, srcPtr, raw.len)

proc base64FromBytes(data: openArray[byte]): string =
  if data.len == 0:
    return ""
  encode(data)

proc buildRequestBody(jpegBytes: seq[byte]): string =
  let b64 = base64FromBytes(jpegBytes)
  result = """
{
  "model": "allenai/olmOCR-2-7B-1025",
  "max_tokens": 4092,
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "Extract the text exactly."
        },
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,""" & b64 & """"
          }
        }
      ]
    }
  ]
}
"""

proc responseExcerpt(body: string; limit: int = 200): string =
  if body.len <= limit:
    return body
  body[0 ..< limit] & "..."

proc main() =
  let apiKey = getEnv("DEEPINFRA_API_KEY")
  doAssert apiKey.len > 0, "DEEPINFRA_API_KEY is required for the live network test"

  let rawJpeg = readFile("test.jpg")
  let jpegBytes = bytesFromString(rawJpeg)
  doAssert jpegBytes.len > 0, "test.jpg must be present and non-empty"

  let body = buildRequestBody(jpegBytes)

  let statePtr = cast[ptr RequestState](alloc0(sizeof(RequestState)))
  doAssert statePtr != nil
  defer:
    dealloc(statePtr)

  var headers: ptr curl_slist = nil
  headers = curl_slist_append(headers, cstring("Authorization: Bearer " & apiKey))
  headers = curl_slist_append(headers, cstring"Content-Type: application/json")
  doAssert headers != nil

  discard curl_global_init(CURL_GLOBAL_DEFAULT)
  defer:
    curl_global_cleanup()

  var errorBuf: array[256, char]
  let easy = curl_easy_init()
  doAssert pointer(easy) != nil
  defer:
    curl_easy_cleanup(easy)

  discard curl_easy_setopt(easy, CURLOPT_URL, "https://api.deepinfra.com/v1/openai/chat/completions".cstring)
  discard curl_easy_setopt(easy, CURLOPT_POST, clong(1))
  discard curl_easy_setopt(easy, CURLOPT_POSTFIELDS, body.cstring)
  discard curl_easy_setopt(easy, CURLOPT_POSTFIELDSIZE, clong(body.len))
  discard curl_easy_setopt(easy, CURLOPT_HTTPHEADER, headers)
  discard curl_easy_setopt(easy, CURLOPT_TIMEOUT_MS, clong(120_000))
  discard curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT_MS, clong(10_000))
  discard curl_easy_setopt(easy, CURLOPT_SSL_VERIFYPEER, clong(1))
  discard curl_easy_setopt(easy, CURLOPT_SSL_VERIFYHOST, clong(2))
  discard curl_easy_setopt(easy, CURLOPT_ACCEPT_ENCODING, "gzip, deflate".cstring)
  discard curl_easy_setopt(easy, CURLOPT_ERRORBUFFER, addr errorBuf[0])
  discard curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, writeCb)
  discard curl_easy_setopt(easy, CURLOPT_WRITEDATA, statePtr)

  let code = curl_easy_perform(easy)
  if code != CURLE_OK:
    let errMsg = $cast[cstring](addr errorBuf[0])
    curl_slist_free_all(headers)
    doAssert false, "curl_easy_perform failed: " & errMsg

  var httpCode: clong = 0
  discard curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, addr httpCode)
  if httpCode < 200 or httpCode >= 300:
    let excerpt = responseExcerpt(statePtr.response)
    curl_slist_free_all(headers)
    doAssert false, "HTTP request failed: " & $httpCode & " body='" & excerpt & "'"

  let response = statePtr.response
  doAssert response.len > 0
  doAssert response.contains("\"choices\"")
  doAssert response.contains("\"content\"")

  curl_slist_free_all(headers)

when isMainModule:
  main()
