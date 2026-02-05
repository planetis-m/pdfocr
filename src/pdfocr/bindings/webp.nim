# Minimal libwebp bindings for WebP encoding.

type
  WebPByte* = uint8

{.push importc, callconv: cdecl.}

proc WebPEncodeBGR*(bgr: ptr WebPByte; width, height, stride: cint;
                    quality_factor: cfloat; output: ptr ptr WebPByte): csize_t

proc WebPFree*(ptrValue: pointer)

{.pop.}
