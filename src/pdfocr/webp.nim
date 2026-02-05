# Ergonomic libwebp helpers built on top of the raw bindings.

import ./bindings/webp

proc webpWrite(data: ptr WebPByte; dataSize: csize_t; picture: ptr WebPPicture): cint {.cdecl.} =
  let buffer = cast[ptr seq[byte]](picture.custom_ptr)
  let oldLen = buffer[].len
  buffer[].setLen(oldLen + int(dataSize))
  copyMem(addr buffer[][oldLen], data, dataSize)
  result = 1

proc encodeBgrWithConfig*(width, height: Positive; pixels: pointer; stride: Positive; quality: float32 = 80.0'f32): seq[byte] =
  ## Encodes a BGR buffer using the low-level WebPConfig/WebPPicture API.
  var config: WebPConfig
  if WebPConfigInitInternal(addr config, WEBP_PRESET_DEFAULT, quality.cfloat, WEBP_ENCODER_ABI_VERSION.cint) == 0:
    raise newException(ValueError, "WebPConfigInitInternal failed")
  if WebPValidateConfig(addr config) == 0:
    raise newException(ValueError, "WebPValidateConfig failed")

  var picture: WebPPicture
  if WebPPictureInitInternal(addr picture, WEBP_ENCODER_ABI_VERSION.cint) == 0:
    raise newException(ValueError, "WebPPictureInitInternal failed")

  var buffer: seq[byte] = @[]

  picture.width = width.cint
  picture.height = height.cint
  picture.writer = cast[pointer](webpWrite)
  picture.custom_ptr = cast[pointer](addr buffer)

  if WebPPictureImportBGR(addr picture, cast[ptr WebPByte](pixels), stride.cint) == 0:
    WebPPictureFree(addr picture)
    raise newException(ValueError, "WebPPictureImportBGR failed")

  if WebPEncode(addr config, addr picture) == 0:
    let err = picture.error_code
    WebPPictureFree(addr picture)
    raise newException(ValueError, "WebPEncode failed with code " & $ord(err))

  WebPPictureFree(addr picture)
  result = buffer
