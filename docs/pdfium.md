# Pdfium Module API Documentation

**Module:** `pdfocr.pdfium`

This module provides a high-level wrapper around the PDFium C library for working with PDF documents.

## Types

### PdfDocument
```nim
PdfDocument = object
```
Represents a PDF document handle.

### PdfPage
```nim
PdfPage = object
```
Represents a single page in a PDF document.

### PdfBitmap
```nim
PdfBitmap = object
```
Represents a bitmap for rendering PDF pages.

### PdfTextPage
```nim
PdfTextPage = object
```
Represents the text content of a PDF page.

## Procedures

### Initialization / Cleanup

#### `initPdfium()`
```nim
proc initPdfium()
```
Initializes the PDFium library. Must be called before any other PDFium operations.

#### `destroyPdfium()`
```nim
proc destroyPdfium()
```
Cleans up the PDFium library. Should be called when done using PDFium.

### Document Operations

#### `loadDocument()`
```nim
proc loadDocument(path: string; password: string = ""): PdfDocument
```
Loads a PDF document from the given file path.

- **Parameters:**
  - `path`: Path to the PDF file
  - `password`: Optional password for encrypted PDFs
- **Returns:** `PdfDocument` handle (move-only; cleaned up at end of scope)
- **Raises:** `IOError` if the document cannot be loaded

#### `pageCount()`
```nim
proc pageCount(doc: PdfDocument): int
```
Returns the number of pages in the document.

### Page Operations

#### `loadPage()`
```nim
proc loadPage(doc: PdfDocument; index: int): PdfPage
```
Loads a page from the document by its index.

- **Parameters:**
  - `doc`: The PDF document
  - `index`: Zero-based page index
- **Returns:** `PdfPage` handle (move-only; cleaned up at end of scope)
- **Raises:** `IOError` if the page cannot be loaded

#### `loadTextPage()`
```nim
proc loadTextPage(page: PdfPage): PdfTextPage
```
Loads the text page for more granular text access.

- **Returns:** `PdfTextPage` handle (move-only; cleaned up at end of scope)
- **Raises:** `IOError` if the text page cannot be loaded

#### `pageSize()`
```nim
proc pageSize(page: PdfPage): tuple[width, height: float]
```
Returns the size of the page in points.

### Bitmap Operations

#### `createBitmap()`
```nim
proc createBitmap(width, height: int; alpha: bool = false): PdfBitmap
```
Creates a bitmap for rendering PDF pages.

- **Parameters:**
  - `width`: Bitmap width in pixels
  - `height`: Bitmap height in pixels
  - `alpha`: Whether to include an alpha channel
- **Returns:** `PdfBitmap` handle (move-only; cleaned up at end of scope)
- **Raises:** `IOError` if the bitmap cannot be created

#### `fillRect()`
```nim
proc fillRect(bitmap: PdfBitmap; left, top, width, height: int; color: uint32)
```
Fills a rectangle in the bitmap with the specified color.

#### `renderPage()`
```nim
proc renderPage(bitmap: PdfBitmap; page: PdfPage;
                startX, startY, sizeX, sizeY: int; rotate: int = 0;
                flags: int = 0)
```
Renders a PDF page onto the bitmap.

#### `renderPageAtScale()`
```nim
proc renderPageAtScale(page: PdfPage; scale: float; alpha: bool = false;
                       rotate: int = 0; flags: int = 0): PdfBitmap
```
Creates a bitmap sized to the page at the given scale, clears it, and renders the page.

#### `width()`
```nim
proc width(bitmap: PdfBitmap): int
```
Returns the bitmap width in pixels.

#### `height()`
```nim
proc height(bitmap: PdfBitmap): int
```
Returns the bitmap height in pixels.

#### `buffer()`
```nim
proc buffer(bitmap: PdfBitmap): pointer
```
Returns a pointer to the bitmap's pixel data buffer.

#### `stride()`
```nim
proc stride(bitmap: PdfBitmap): int
```
Returns the stride (bytes per row) of the bitmap.

### Text Operations

#### `extractText()`
```nim
proc extractText(page: PdfPage): string
```
Extracts all text from a PDF page.

#### `charCount()`
```nim
proc charCount(textPage: PdfTextPage): int
```
Returns the number of characters in the text page.

#### `getTextRange()`
```nim
proc getTextRange(textPage: PdfTextPage; startIndex, count: int): string
```
Extracts a range of text from the text page.

#### `getCharBox()`
```nim
proc getCharBox(textPage: PdfTextPage; index: int): tuple[left, right, bottom, top: float]
```
Returns the bounding box of a character at the given index.

### Error Handling

#### `lastErrorCode()`
```nim
proc lastErrorCode(): culong
```
Returns the last error code from PDFium.

#### `raisePdfiumError()`
```nim
proc raisePdfiumError(context: string)
```
Raises an IOError with PDFium error information.

## Usage Example

```nim
import pdfocr/pdfium

initPdfium()
try:
  var doc = loadDocument("input.pdf")
  var page = loadPage(doc, 0)
  var bitmap = renderPageAtScale(page, 2.0)
  discard bitmap
  echo extractText(page)
finally:
  destroyPdfium()
```
