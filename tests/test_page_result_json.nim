import jsonx
import pdfocr/types

proc main() =
  let okResult = PageResult(
    page: 12,
    attempts: 1,
    status: PageOk,
    text: "hello",
    errorKind: NoError,
    errorMessage: "",
    httpStatus: 0
  )
  doAssert toJson(okResult) ==
    """{"page":12,"status":"ok","attempts":1,"text":"hello"}"""

  let errorResult = PageResult(
    page: 12,
    attempts: 3,
    status: PageError,
    text: "",
    errorKind: Timeout,
    errorMessage: "request timed out (http 504)",
    httpStatus: 504
  )
  doAssert toJson(errorResult) ==
    """{"page":12,"status":"error","attempts":3,"error_kind":"Timeout","error_message":"request timed out (http 504)","http_status":504}"""

  let networkError = PageResult(
    page: 2,
    attempts: 6,
    status: PageError,
    text: "",
    errorKind: NetworkError,
    errorMessage: "curl transfer failed code=6",
    httpStatus: 0
  )
  doAssert toJson(networkError) ==
    """{"page":2,"status":"error","attempts":6,"error_kind":"NetworkError","error_message":"curl transfer failed code=6"}"""

when isMainModule:
  main()
