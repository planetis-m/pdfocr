import jsonx
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

  ChatCompletionRequestContract* = object
    model*: string
    instruction*: string
    image_data_url*: string

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
  toJson(ChatCompletionRequestContract(
    model: MODEL,
    instruction: instruction,
    image_data_url: imageDataUrl
  ))

proc parseChatCompletionResponse*(payload: string): ChatCompletionParseContract =
  try:
    let parsed = fromJson(payload, ChatCompletionResponse)
    if parsed.choices.len == 0:
      return ChatCompletionParseContract(
        ok: false,
        text: "",
        error_kind: PARSE_ERROR,
        error_message: boundedErrorMessage("missing choices[0].message.content")
      )

    ChatCompletionParseContract(
      ok: true,
      text: parsed.choices[0].message.content,
      error_kind: PARSE_ERROR,
      error_message: ""
    )
  except CatchableError as exc:
    ChatCompletionParseContract(
      ok: false,
      text: "",
      error_kind: PARSE_ERROR,
      error_message: boundedErrorMessage(exc.msg)
    )
