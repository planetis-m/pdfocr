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

- `src/pdfocr/bindings/pdfium.nim`
- `src/pdfocr/bindings/jpeglib.nim`
- `src/pdfocr/bindings/curl.nim`

## Quick Start

### Working with PDFs (pdfium module)

```nim
import pdfocr/pdfium

# Initialize PDFium
initPdfium()
try:
  # Load a document
  var doc = loadDocument("document.pdf")

  # Get page count
  echo "Pages: ", pageCount(doc)

  # Load and render a page
  var page = loadPage(doc, 0)
  let (width, height) = pageSize(page)
  echo "Page size: ", width, " x ", height

  # Extract text
  let text = extractText(page)
  echo text
finally:
  destroyPdfium()
```

### JPEG Compression (jpeglib module)

```nim
import pdfocr/jpeglib

var comp = initJpegCompressorBgrx(width, height, quality = 95)
writeBgrx(comp, buffer, stride)
let bytes = finishJpeg(comp)
```

### HTTP Requests (curl module)

```nim
import pdfocr/curl

# Initialize libcurl
initCurlGlobal()
try:
  # Create and configure request
  var easy = initEasy()
  easy.setUrl("https://example.com")
  easy.setTimeoutMs(5000)

  # Perform request
  easy.perform()
  echo "Response code: ", easy.responseCode()
finally:
  cleanupCurlGlobal()
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
| `src/pdfocr/bindings/pdfium.nim` | PDFium C bindings | (advanced users) |
| `src/pdfocr/bindings/jpeglib.nim` | libjpeg C bindings | (advanced users) |
| `src/pdfocr/bindings/curl.nim` | libcurl C bindings | (advanced users) |
