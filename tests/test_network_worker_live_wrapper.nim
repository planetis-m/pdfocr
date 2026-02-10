import std/[base64, os, strutils]
import pdfocr/curl

type
  RequestState = object
    response: string

proc writeCb(buffer: ptr char; size: csize_t; nitems: csize_t; userdata: pointer): csize_t {.cdecl.} =
  let total = int(size * nitems)
  if total <= 0: return 0
  let state = cast[ptr RequestState](userdata)
  if state != nil:
    let start = state.response.len
    state.response.setLen(start + total)
    copyMem(addr state.response[start], buffer, total)
  csize_t(total)

proc readJpegFile(filename: string): seq[byte] =
  let file = open(filename, fmRead)
  try:
    let len = getFileSize(file)
    result = newSeq[byte](len)
    discard readBuffer(file, addr(result[0]), len)
  finally:
    close(file)

proc buildRequestBody(jpegBytes: seq[byte]): string =
  let b64 = base64.encode(jpegBytes)
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

  let jpegBytes = readJpegFile("test.jpg")
  doAssert jpegBytes.len > 0, "test.jpg must be present and non-empty"

  let body = buildRequestBody(jpegBytes)

  let state = RequestState(response: "")

  initCurlGlobal()
  try:
    var easy = initEasy()
    var headers: CurlSlist

    easy.setUrl("https://api.deepinfra.com/v1/openai/chat/completions")
    easy.setPostFields(body)
    easy.setWriteCallback(writeCb, addr state)
    easy.setTimeoutMs(120_000)
    easy.setConnectTimeoutMs(10_000)
    easy.setSslVerify(true, true)
    easy.setAcceptEncoding("gzip, deflate")

    headers.addHeader("Authorization: Bearer " & apiKey)
    headers.addHeader("Content-Type: application/json")
    easy.setHeaders(headers)

    easy.perform()

    let httpCode = easy.responseCode()
    if httpCode < Http200 or Http300 <= httpCode:
      let excerpt = responseExcerpt(state.response)
      doAssert false, "HTTP request failed: " & $httpCode & " body='" & excerpt & "'"

    let response = state.response
    doAssert response.len > 0
    doAssert response.contains("\"choices\"")
    doAssert response.contains("\"content\"")
  finally:
    cleanupCurlGlobal()

when isMainModule:
  main()
