import std/base64
import openai
import ./[constants, types]

proc buildOcrParams*(network: NetworkConfig; webpBytes: seq[byte]): ChatCreateParams =
  result = chatCreate(
    model = network.model,
    messages = @[
      userMessageParts(@[
        partText(network.prompt),
        partImageUrl("data:image/webp;base64," & encode(webpBytes))
      ])
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
