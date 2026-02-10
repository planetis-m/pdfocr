import jsonx
import jsonx/streams
import ./constants
import ./errors
import ./types

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

  ChatCompletionContentPart = object
    `type`: string
    text: string

  ChatCompletionMessageText = object
    content: string

  ChatCompletionMessageParts = object
    content: seq[ChatCompletionContentPart]

  ChatCompletionChoiceText = object
    message: ChatCompletionMessageText

  ChatCompletionChoiceParts = object
    message: ChatCompletionMessageParts

  ChatCompletionResponseText = object
    choices: seq[ChatCompletionChoiceText]

  ChatCompletionResponseParts = object
    choices: seq[ChatCompletionChoiceParts]

  ChatCompletionParseContract* = object
    ok*: bool
    text*: string
    error_kind*: ErrorKind
    error_message*: string

proc encodeResultLine*(pageResult: PageResult): string =
  if pageResult.status == psOk:
    return toJson(OkResultLine(
      page: pageResult.page,
      status: "ok",
      attempts: pageResult.attempts,
      text: pageResult.text
    ))

  let bounded = boundedErrorMessage(pageResult.errorMessage)
  if pageResult.hasHttpStatus:
    return toJson(ErrorResultLineWithHttp(
      page: pageResult.page,
      status: "error",
      attempts: pageResult.attempts,
      error_kind: $pageResult.errorKind,
      error_message: bounded,
      http_status: pageResult.httpStatus
    ))

  toJson(ErrorResultLineNoHttp(
    page: pageResult.page,
    status: "error",
    attempts: pageResult.attempts,
    error_kind: $pageResult.errorKind,
    error_message: bounded
  ))

proc buildChatCompletionRequest*(instruction: string; imageDataUrl: string): string =
  let s = streams.open("")
  streams.write(s, "{\"model\":")
  writeJson(s, MODEL)
  streams.write(s, ",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":")
  writeJson(s, instruction)
  streams.write(s, "},{\"type\":\"image_url\",\"image_url\":{\"url\":")
  writeJson(s, imageDataUrl)
  streams.write(s, "}}]}]}")
  s.s

proc parseChatCompletionResponse*(payload: string): ChatCompletionParseContract =
  try:
    let parsedText = fromJson(payload, ChatCompletionResponseText)
    if parsedText.choices.len > 0 and parsedText.choices[0].message.content.len > 0:
      return ChatCompletionParseContract(
        ok: true,
        text: parsedText.choices[0].message.content,
        error_kind: PARSE_ERROR,
        error_message: ""
      )
  except CatchableError:
    discard

  try:
    let parsedParts = fromJson(payload, ChatCompletionResponseParts)
    if parsedParts.choices.len == 0:
      return ChatCompletionParseContract(
        ok: false,
        text: "",
        error_kind: PARSE_ERROR,
        error_message: boundedErrorMessage("missing choices[0].message.content")
      )
    for part in parsedParts.choices[0].message.content:
      if part.text.len > 0:
        return ChatCompletionParseContract(
          ok: true,
          text: part.text,
          error_kind: PARSE_ERROR,
          error_message: ""
        )
    ChatCompletionParseContract(
      ok: false,
      text: "",
      error_kind: PARSE_ERROR,
      error_message: boundedErrorMessage("missing text in choices[0].message.content")
    )
  except CatchableError as exc:
    ChatCompletionParseContract(
      ok: false,
      text: "",
      error_kind: PARSE_ERROR,
      error_message: boundedErrorMessage(exc.msg)
    )
