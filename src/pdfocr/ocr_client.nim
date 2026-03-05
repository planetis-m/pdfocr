import std/base64
import openai
import ./[constants, types]

proc buildOcrParams*(network: NetworkConfig; webpBytes: seq[byte]): ChatCreateParams =
  let imageDataUrl = "data:image/webp;base64," & encode(webpBytes)
  var parts = newSeq[ChatCompletionContentPart]()
  if network.prompt.len > 0:
    parts.add(partText(network.prompt))
  parts.add(partImageUrl(imageDataUrl))
  result = chatCreate(
    model = network.model,
    messages = @[
      userMessageParts(parts)
    ],
    temperature = 0.0,
    maxTokens = MaxOutputTokens,
    toolChoice = ToolChoice.none,
    responseFormat = formatText
  )

proc parseOcrText*(body: string; text: var string): bool =
  var parsed: ChatCreateResult
  if chatParse(body, parsed):
    text = firstText(parsed)
    result = true
  else:
    result = false
