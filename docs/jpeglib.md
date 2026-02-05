# Jpeglib Module API Documentation

**Module:** `pdfocr.jpeglib`

This module provides JPEG compression functionality using the libjpeg C library.

## Types

### JpegCompressor
```nim
JpegCompressor = object
```
Opaque handle representing a JPEG compressor instance.

### JpegQuality
```nim
JpegQuality = range[1 .. 100]
```
JPEG quality range (1..100).

## Procedures

### RGB Format

#### `initJpegCompressor()`
```nim
proc initJpegCompressor(width, height: Positive; quality: JpegQuality = 90): JpegCompressor
```
Initializes a JPEG compressor for RGB format data.

- **Parameters:**
  - `width`: Image width in pixels
  - `height`: Image height in pixels
  - `quality`: JPEG quality (1-100, default: 90)
- **Returns:** `JpegCompressor` handle (move-only; cleaned up at end of scope)

#### `writeRgb()`
```nim
proc writeRgb(comp: var JpegCompressor; buffer: openArray[byte])
```
Writes RGB pixel data to the JPEG compressor.

- **Parameters:**
  - `comp`: The compressor instance
  - `buffer`: Array of bytes containing RGB data (3 bytes per pixel)
- **Raises:** `ValueError` if buffer size is incorrect

#### `finishJpeg()`
```nim
proc finishJpeg(comp: var JpegCompressor): seq[byte]
```
Finalizes compression and returns the JPEG bytes.

- **Returns:** JPEG bytes as `seq[byte]`

### BGRX Format

#### `initJpegCompressorBgrx()`
```nim
proc initJpegCompressorBgrx(width, height: Positive; quality: JpegQuality = 90): JpegCompressor
```
Initializes a JPEG compressor for BGRX format data (4 bytes per pixel).

- **Parameters:**
  - `width`: Image width in pixels
  - `height`: Image height in pixels
  - `quality`: JPEG quality (1-100, default: 90)
- **Returns:** `JpegCompressor` handle (move-only; cleaned up at end of scope)

#### `writeBgrx()`
```nim
proc writeBgrx(comp: var JpegCompressor; buffer: pointer; stride: Positive)
```
Writes BGRX pixel data to the JPEG compressor.

- **Parameters:**
  - `comp`: The compressor instance
  - `buffer`: Pointer to BGRX data (4 bytes per pixel)
  - `stride`: Number of bytes per row

## Usage Example

```nim
import pdfocr/jpeglib

var comp = initJpegCompressorBgrx(width, height, quality = 95)
writeBgrx(comp, buffer, stride)
let bytes = finishJpeg(comp)
```
