# PDFOCR API Documentation

This directory contains the complete API documentation for the pdfocr project modules.

## High-Level API Modules

These modules provide safe, idiomatic Nim wrappers around C libraries:

| Module | Description | File |
|--------|-------------|------|
| **pdfium** | PDF document manipulation, rendering, and text extraction | [pdfium.md](pdfium.md) |
| **jpeglib** | JPEG image compression | [jpeglib.md](jpeglib.md) |
| **curl** | HTTP client for making web requests | [curl.md](curl.md) |

## Low-Level Bindings

The following modules contain direct C bindings (for advanced users):

| Module | Description | File |
|--------|-------------|------|
| **bindings.pdfium** | Direct PDFium C library bindings | [bindings_pdfium.json](bindings_pdfium.json) |
| **bindings.jpeglib** | Direct libjpeg C library bindings | [bindings_jpeglib.json](bindings_jpeglib.json) |
| **bindings.curl** | Direct libcurl C library bindings | [bindings_curl.json](bindings_curl.json) |

## Quick Start

### Working with PDFs (pdfium module)

```nim
import pdfocr.pdfium

# Initialize PDFium
initPdfium()
defer: destroyPdfium()

# Load a document
var doc = loadDocument("document.pdf")
defer: close(doc)

# Get page count
echo "Pages: ", pageCount(doc)

# Load and render a page
var page = loadPage(doc, 0)
defer: close(page)

let (width, height) = pageSize(page)
echo "Page size: ", width, " x ", height

# Extract text
let text = extractText(page)
echo text
```

### JPEG Compression (jpeglib module)

```nim
import pdfocr.jpeglib

# Create a JPEG compressor
var comp = initJpegCompressorBgrx("output.jpg", width, height, quality = 95)
comp.writeBgrx(buffer, stride)
comp.finish(comp)
```

### HTTP Requests (curl module)

```nim
import pdfocr.curl

# Initialize libcurl
initCurlGlobal()
defer: cleanupCurlGlobal()

# Create and configure request
var easy = initEasy()
easy.setUrl("https://example.com")
easy.setTimeoutMs(5000)

# Perform request
easy.perform()
echo "Response code: ", easy.responseCode()

# Cleanup
easy.close()
```

## Module Organization

```
src/pdfocr/
├── bindings/          # Low-level C bindings
│   ├── pdfium.nim
│   ├── jpeglib.nim
│   └── curl.nim
├── pdfium.nim         # High-level PDF wrapper
├── jpeglib.nim        # High-level JPEG wrapper
└── curl.nim           # High-level HTTP wrapper
```

## Source Files

| File | Purpose | Documentation |
|------|---------|---------------|
| `src/pdfocr/pdfium.nim` | High-level PDF API | [pdfium.md](pdfium.md) |
| `src/pdfocr/jpeglib.nim` | High-level JPEG API | [jpeglib.md](jpeglib.md) |
| `src/pdfocr/curl.nim` | High-level HTTP API | [curl.md](curl.md) |
| `src/app.nim` | Main application entry point | (no exported API) |
| `src/pdfocr/bindings/pdfium.nim` | PDFium C bindings | [bindings_pdfium.json](bindings_pdfium.json) |
| `src/pdfocr/bindings/jpeglib.nim` | libjpeg C bindings | [bindings_jpeglib.json](bindings_jpeglib.json) |
| `src/pdfocr/bindings/curl.nim` | libcurl C bindings | [bindings_curl.json](bindings_curl.json) |
