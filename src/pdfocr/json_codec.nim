import jsonx
import jsonx/[streams, parsejson]
import ./[constants, errors, types, curl]

{.define: jsonxLenient.}

const
  RequestMaxTokens = 4096

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
    max_tokens: int
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

proc encodeResultLine*(p: PageResult): string =
  let bounded = boundedErrorMessage(p.errorMessage)
  if p.status == psOk:
    result = toJson(OkResultLine(
      page: p.page,
      status: "ok",
      attempts: p.attempts,
      text: p.text
    ))
  elif p.httpStatus != HttpNone:
    result = toJson(ErrorResultLineWithHttp(
      page: p.page,
      status: "error",
      attempts: p.attempts,
      error_kind: $p.errorKind,
      error_message: bounded,
      http_status: int(p.httpStatus)
    ))
  else:
    result = toJson(ErrorResultLineNoHttp(
      page: p.page,
      status: "error",
      attempts: p.attempts,
      error_kind: $p.errorKind,
      error_message: bounded
    ))

proc buildChatCompletionRequest*(instruction: string; imageDataUrl: string): string =
  toJson(Request(
    model: Model,
    max_tokens: RequestMaxTokens,
    messages: @[
      Message(
        role: "user",
        content: @[
          ContentPart(`type`: "text", text: instruction, image_url: ImageUrl()),
          ContentPart(`type`: "image_url", text: "", image_url: ImageUrl(url: imageDataUrl))
        ]
      )
    ]
  ))

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
