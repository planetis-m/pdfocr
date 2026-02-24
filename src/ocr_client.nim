import std/base64
import relay
import openai
import ./[constants, types]

proc buildOcrRequest*(network: NetworkConfig; apiKey: string;
    webpBytes: seq[byte]; requestId: int64): RequestSpec =
  let imageDataUrl = "data:image/webp;base64," & encode(webpBytes)
  let params = chatCreate(
    model = network.model,
    messages = @[
      userMessageParts(@[
        partText(network.prompt),
        partImageUrl(imageDataUrl)
      ])
    ],
    temperature = 0.0,
    maxTokens = MaxOutputTokens,
    toolChoice = ToolChoice.none,
    responseFormat = formatText
  )

  let cfg = OpenAIConfig(url: network.apiUrl, apiKey: apiKey)
  result = chatRequest(
    cfg = cfg,
    params = params,
    requestId = requestId,
    timeoutMs = network.totalTimeoutMs
  )

proc parseOcrText*(body: string; text: var string): bool =
  var parsed: ChatCreateResult
  if chatParse(body, parsed):
    text = firstText(parsed)
    result = true
  else:
    result = false
