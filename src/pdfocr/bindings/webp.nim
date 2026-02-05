# Minimal libwebp bindings for WebP encoding.

type
  WebPByte* = uint8

  WebPPicture* {.importc: "WebPPicture", header: "<webp/encode.h>", incompleteStruct.} = object
    use_argb*: cint
    width*: cint
    height*: cint
    writer*: pointer
    custom_ptr*: pointer
    error_code*: cint

  WebPConfig* {.importc: "WebPConfig", header: "<webp/encode.h>", incompleteStruct.} = object
    lossless*: cint
    quality*: cfloat
    methodField*: cint

const
  WEBP_PRESET_DEFAULT* = 0
  WEBP_ENCODER_ABI_VERSION* = 0x0210

{.push importc, callconv: cdecl, header: "<webp/encode.h>".}

proc WebPConfigInitInternal*(config: ptr WebPConfig; preset: cint; quality: cfloat; version: cint): cint
proc WebPValidateConfig*(config: ptr WebPConfig): cint

proc WebPPictureInitInternal*(picture: ptr WebPPicture; version: cint): cint
proc WebPPictureImportBGR*(picture: ptr WebPPicture; bgr: ptr WebPByte; bgr_stride: cint): cint
proc WebPPictureFree*(picture: ptr WebPPicture)

proc WebPEncode*(config: ptr WebPConfig; picture: ptr WebPPicture): cint

{.pop.}
