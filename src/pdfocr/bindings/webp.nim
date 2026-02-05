# Minimal libwebp bindings for WebP encoding.

type
  WebPByte* = uint8

{.push importc, callconv: cdecl, header: "<webp/encode.h>".}

proc WebPEncodeBGR*(bgr: ptr WebPByte; width, height, stride: cint;
                    quality_factor: cfloat; output: ptr ptr WebPByte): csize_t

{.pop.}

{.push importc, callconv: cdecl, header: "<webp/types.h>".}

proc WebPFree*(ptrValue: pointer)

{.pop.}
