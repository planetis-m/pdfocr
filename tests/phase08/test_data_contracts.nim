import std/[json, strutils]
import pdfocr/[constants, curl, errors, json_codec, types]

proc main() =
  let okLine = encodeResultLine(PageResult(
    seqId: 0,
    page: 7,
    status: psOk,
    attempts: 1,
    text: "hello",
    errorKind: PARSE_ERROR,
    errorMessage: "",
    httpStatus: HttpNone
  ))
  let okJson = parseJson(okLine)
  doAssert okJson["page"].getInt() == 7
  doAssert okJson["status"].getStr() == "ok"
  doAssert okJson["attempts"].getInt() == 1
  doAssert okJson["text"].getStr() == "hello"
  doAssert not okJson.hasKey("error_kind")
  doAssert not okJson.hasKey("http_status")

  let longError = repeat("x", MAX_ERROR_MESSAGE_LEN + 200)
  let errLine = encodeResultLine(PageResult(
    seqId: 1,
    page: 9,
    status: psError,
    attempts: 2,
    text: "",
    errorKind: HTTP_ERROR,
    errorMessage: longError,
    httpStatus: Http503
  ))
  let errJson = parseJson(errLine)
  doAssert errJson["page"].getInt() == 9
  doAssert errJson["status"].getStr() == "error"
  doAssert errJson["attempts"].getInt() == 2
  doAssert errJson["error_kind"].getStr() == $HTTP_ERROR
  doAssert errJson["http_status"].getInt() == 503
  let bounded = errJson["error_message"].getStr()
  doAssert bounded.len <= MAX_ERROR_MESSAGE_LEN
  doAssert bounded.endsWith("...")

  doAssert boundedErrorMessage(longError).len <= MAX_ERROR_MESSAGE_LEN
  doAssert boundedErrorMessage("short") == "short"

  let maxAttempts = 1 + MAX_RETRIES
  doAssert maxAttempts >= 1
  for attempts in 1 .. maxAttempts:
    let line = encodeResultLine(PageResult(
      seqId: attempts,
      page: attempts,
      status: psOk,
      attempts: attempts,
      text: "",
      errorKind: PARSE_ERROR,
      errorMessage: "",
      httpStatus: HttpNone
    ))
    doAssert parseJson(line)["attempts"].getInt() == attempts

when isMainModule:
  main()
