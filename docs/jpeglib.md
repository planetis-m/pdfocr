# Jpeglib Module API Documentation

**Module:** `pdfocr.jpeglib`

This module provides JPEG compression functionality using the libjpeg C library.

## Types

### JpegCompressor
```nim
JpegCompressor = object
```
Opaque handle representing a JPEG compressor instance.

## Procedures

### RGB Format

#### `initJpegCompressor()`
```nim
proc initJpegCompressor(path: string; width, height: Positive; quality: JpegQuality = 90): JpegCompressor {.raises: [IOError].}
```
Initializes a JPEG compressor for RGB format data.

- **Parameters:**
  - `path`: Output file path for the JPEG
  - `width`: Image width in pixels
  - `height`: Image height in pixels
  - `quality`: JPEG quality (1-100, default: 90)
- **Returns:** `JpegCompressor` handle (move-only; cleaned up at end of scope)
- **Raises:** `IOError` if file cannot be created

#### `writeRgb()`
```nim
proc writeRgb(comp: var JpegCompressor; buffer: openArray[byte]) {.raises: [ValueError].}
```
Writes RGB pixel data to the JPEG compressor.

- **Parameters:**
  - `comp`: The compressor instance
  - `buffer`: Array of bytes containing RGB data (3 bytes per pixel)
- **Raises:** `ValueError` if buffer size is incorrect

### BGRX Format

#### `initJpegCompressorBgrx()`
```nim
proc initJpegCompressorBgrx(path: string; width, height: Positive; quality: JpegQuality = 90): JpegCompressor {.raises: [IOError].}
```
Initializes a JPEG compressor for BGRX format data (4 bytes per pixel).

- **Parameters:**
  - `path`: Output file path for the JPEG
  - `width`: Image width in pixels
  - `height`: Image height in pixels
  - `quality`: JPEG quality (1-100, default: 90)
- **Returns:** `JpegCompressor` handle (move-only; cleaned up at end of scope)
- **Raises:** `IOError` if file cannot be created

#### `writeBgrx()`
```nim
proc writeBgrx(comp: var JpegCompressor; buffer: pointer; stride: int) {.raises: [].}
```
Writes BGRX pixel data to the JPEG compressor.

- **Parameters:**
  - `comp`: The compressor instance
  - `buffer`: Pointer to BGRX data (4 bytes per pixel)
  - `stride`: Number of bytes per row
- **Raises:** `ValueError` if parameters are invalid

## Usage Example

```nim
var comp = initJpegCompressorBgrx("output.jpg", width, height, quality = 95)
comp.writeBgrx(buffer, stride)
```
