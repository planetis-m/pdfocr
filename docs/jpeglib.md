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
proc initJpegCompressor(path: string; width, height: int; quality: int = 90): JpegCompressor {.raises: [ValueError, IOError], tags: [], forbids: [].}
```
Initializes a JPEG compressor for RGB format data.

- **Parameters:**
  - `path`: Output file path for the JPEG
  - `width`: Image width in pixels
  - `height`: Image height in pixels
  - `quality`: JPEG quality (1-100, default: 90)
- **Returns:** `JpegCompressor` handle
- **Raises:** `ValueError` if parameters are invalid, `IOError` if file cannot be created

#### `writeRgb()`
```nim
proc writeRgb(comp: var JpegCompressor; buffer: openArray[byte]) {.raises: [IOError, ValueError], tags: [], forbids: [].}
```
Writes RGB pixel data to the JPEG compressor.

- **Parameters:**
  - `comp`: The compressor instance
  - `buffer`: Array of bytes containing RGB data (3 bytes per pixel)
- **Raises:** `IOError` on write failure, `ValueError` if buffer size is incorrect

### BGRX Format

#### `initJpegCompressorBgrx()`
```nim
proc initJpegCompressorBgrx(path: string; width, height: int; quality: int = 90): JpegCompressor {.raises: [ValueError, IOError], tags: [], forbids: [].}
```
Initializes a JPEG compressor for BGRX format data (4 bytes per pixel).

- **Parameters:**
  - `path`: Output file path for the JPEG
  - `width`: Image width in pixels
  - `height`: Image height in pixels
  - `quality`: JPEG quality (1-100, default: 90)
- **Returns:** `JpegCompressor` handle
- **Raises:** `ValueError` if parameters are invalid, `IOError` if file cannot be created

#### `writeBgrx()`
```nim
proc writeBgrx(comp: var JpegCompressor; buffer: pointer; stride: int) {.raises: [IOError, ValueError], tags: [], forbids: [].}
```
Writes BGRX pixel data to the JPEG compressor.

- **Parameters:**
  - `comp`: The compressor instance
  - `buffer`: Pointer to BGRX data (4 bytes per pixel)
  - `stride`: Number of bytes per row
- **Raises:** `IOError` on write failure, `ValueError` if parameters are invalid

### Cleanup

#### `finish()`
```nim
proc finish(comp: var JpegCompressor) {.raises: [], tags: [], forbids: [].}
```
Finalizes the JPEG compression and closes the output file.

- **Parameters:**
  - `comp`: The compressor instance to finalize

## Usage Example

```nim
var comp = initJpegCompressorBgrx("output.jpg", width, height, quality = 95)
comp.writeBgrx(buffer, stride)
comp.finish(comp)
```
