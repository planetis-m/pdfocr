import jsonx
import jsonx/[streams, parser]
import ./[constants, errors, types]

type
  OkResultLine = object
    page: int
    status: string
    attempts: int
    text: string

  ErrorResultLineNoHttp = object
    page: int
    status: string
    attempts: int
    error_kind: string
    error_message: string

  ErrorResultLineWithHttp = object
    page: int
    status: string
    attempts: int
    error_kind: string
    error_message: string
    http_status: int

  ImageUrl = object
    url: string
  
  ContentPart = object
    `type`: string
    text: string
    image_url: ImageUrl
  
  Message = object
    role: string
    content: seq[ContentPart]
  
  Request = object
    model: string
    messages: seq[Message]

  ChatCompletionMessage = object
    content: string

  ChatCompletionChoice = object
    message: ChatCompletionMessage

  ChatCompletionResponse = object
    choices: seq[ChatCompletionChoice]

  ChatCompletionParseContract* = object
    ok*: bool
    text*: string
    error_kind*: ErrorKind
    error_message*: string

proc encodeResultLine*(pageResult: PageResult): string =
  let bounded = boundedErrorMessage(pageResult.errorMessage)
  
  if pageResult.status == psOk:
    result = toJson(OkResultLine(
      page: pageResult.page,
      status: "ok",
      attempts: pageResult.attempts,
      text: pageResult.text
    ))
  elif pageResult.hasHttpStatus:
    result = toJson(ErrorResultLineWithHttp(
      page: pageResult.page,
      status: "error",
      attempts: pageResult.attempts,
      error_kind: $pageResult.errorKind,
      error_message: bounded,
      http_status: pageResult.httpStatus
    ))
  else:
    result = toJson(ErrorResultLineNoHttp(
      page: pageResult.page,
      status: "error",
      attempts: pageResult.attempts,
      error_kind: $pageResult.errorKind,
      error_message: bounded
    ))

proc buildChatCompletionRequest*(instruction: string; imageDataUrl: string): string =
  let request = Request(
    model: Model,
    messages: @[
      Message(
        role: "user",
        content: @[
          ContentPart(`type`: "text", text: instruction, image_url: ImageUrl()),
          ContentPart(`type`: "image_url", text: "", image_url: ImageUrl(url: imageDataUrl))
        ]
      )
    ]
  )
  toJson(request)

proc readContentParts(p: var JsonParser; result: var string) =
  ## Reads an array of content parts and extracts the first non-empty text
  eat(p, tkBracketLe)
  while p.tok != tkBracketRi:
    eat(p, tkCurlyLe)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        raiseParseErr(p, "string literal as key")
      if p.a == "text":
        discard getTok(p)
        eat(p, tkColon)
        if result.len == 0:
          readJson(result, p)
        else:
          skipJson(p)
      else:
        discard getTok(p)
        eat(p, tkColon)
        skipJson(p)
      expectObjectSeparator(p)
    eat(p, tkCurlyRi)

    expectArraySeparator(p)
  eat(p, tkBracketRi)

proc readJson*(dst: var ChatCompletionMessage; p: var JsonParser) =
  eat(p, tkCurlyLe)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")
    if p.a == "content":
      discard getTok(p)
      eat(p, tkColon)
      if p.tok == tkString:
        readJson(dst.content, p)
      elif p.tok == tkBracketLe:
        dst.content = readContentParts(p)
      else:
        raiseParseErr(p, "string or array")
    else:
      discard getTok(p)
      eat(p, tkColon)
      skipJson(p)
    
    expectObjectSeparator(p)
  eat(p, tkCurlyRi)

proc parseChatCompletionResponse*(payload: string): ChatCompletionParseContract =
  try:
    let parsed = fromJson(payload, ChatCompletionResponse)
    
    result = ChatCompletionParseContract(
      ok: true,
      text: parsed.choices[0].message.content,
      error_kind: NoError,
      error_message: ""
    )
    
  except CatchableError:
    result = ChatCompletionParseContract(
      ok: false,
      text: "",
      error_kind: ParseError,
      error_message: boundedErrorMessage(getCurrentExceptionMsg())
    )
