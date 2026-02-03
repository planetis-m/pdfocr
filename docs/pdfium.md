# Pdfium Module API Documentation

**Module:** `pdfocr.pdfium`

This module provides a high-level wrapper around the PDFium C library for working with PDF documents.

## Types

### PdfDocument
```nim
PdfDocument = object
  raw*: FPDF_DOCUMENT
```
Represents a PDF document handle.

### PdfPage
```nim
PdfPage = object
  raw*: FPDF_PAGE
```
Represents a single page in a PDF document.

### PdfBitmap
```nim
PdfBitmap = object
  raw*: FPDF_BITMAP
  width*: int
  height*: int
```
Represents a bitmap for rendering PDF pages.

### PdfTextPage
```nim
PdfTextPage = object
  raw*: FPDF_TEXTPAGE
```
Represents the text content of a PDF page.

## Procedures

### Initialization / Cleanup

#### `initPdfium()`
```nim
proc initPdfium() {.raises: [], tags: [], forbids: [].}
```
Initializes the PDFium library. Must be called before any other PDFium operations.

#### `destroyPdfium()`
```nim
proc destroyPdfium() {.raises: [], tags: [], forbids: [].}
```
Cleans up the PDFium library. Should be called when done using PDFium.

### Document Operations

#### `loadDocument()`
```nim
proc loadDocument(path: string; password: string = ""): PdfDocument {.raises: [IOError], tags: [], forbids: [].}
```
Loads a PDF document from the given file path.

- **Parameters:**
  - `path`: Path to the PDF file
  - `password`: Optional password for encrypted PDFs
- **Returns:** `PdfDocument` handle
- **Raises:** `IOError` if the document cannot be loaded

#### `close()`
```nim
proc close(doc: var PdfDocument) {.raises: [], tags: [], forbids: [].}
```
Closes a PDF document and releases its resources.

#### `pageCount()`
```nim
proc pageCount(doc: PdfDocument): int {.raises: [], tags: [], forbids: [].}
```
Returns the number of pages in the document.

### Page Operations

#### `loadPage()`
```nim
proc loadPage(doc: PdfDocument; index: int): PdfPage {.raises: [IOError], tags: [], forbids: [].}
```
Loads a page from the document by its index.

- **Parameters:**
  - `doc`: The PDF document
  - `index`: Zero-based page index
- **Returns:** `PdfPage` handle
- **Raises:** `IOError` if the page cannot be loaded

#### `close()` (page)
```nim
proc close(page: var PdfPage) {.raises: [], tags: [], forbids: [].}
```
Closes a PDF page and releases its resources.

#### `pageSize()`
```nim
proc pageSize(page: PdfPage): tuple[width, height: float] {.raises: [], tags: [], forbids: [].}
```
Returns the size of the page in points.

- **Returns:** A tuple with `width` and `height` in points

### Bitmap Operations

#### `createBitmap()`
```nim
proc createBitmap(width, height: int; alpha: bool = false): PdfBitmap {.raises: [IOError], tags: [], forbids: [].}
```
Creates a bitmap for rendering PDF pages.

- **Parameters:**
  - `width`: Bitmap width in pixels
  - `height`: Bitmap height in pixels
  - `alpha`: Whether to include an alpha channel
- **Returns:** `PdfBitmap` handle
- **Raises:** `IOError` if the bitmap cannot be created

#### `destroy()`
```nim
proc destroy(bitmap: var PdfBitmap) {.raises: [], tags: [], forbids: [].}
```
Destroys a bitmap and releases its resources.

#### `fillRect()`
```nim
proc fillRect(bitmap: PdfBitmap; left, top, width, height: int; color: uint32) {.raises: [], tags: [], forbids: [].}
```
Fills a rectangle in the bitmap with the specified color.

#### `renderPage()`
```nim
proc renderPage(bitmap: PdfBitmap; page: PdfPage;
                startX, startY, sizeX, sizeY: int; rotate: int = 0;
                flags: int = 0) {.raises: [], tags: [], forbids: [].}
```
Renders a PDF page onto the bitmap.

- **Parameters:**
  - `bitmap`: Target bitmap
  - `page`: PDF page to render
  - `startX`, `startY`: Starting position
  - `sizeX`, `sizeY`: Size of the rendering area
  - `rotate`: Rotation (default: 0)
  - `flags`: Rendering flags (default: 0)

#### `renderPageAtScale()`
```nim
proc renderPageAtScale(page: PdfPage; scale: float; alpha: bool = false;
                       rotate: int = 0; flags: int = 0): PdfBitmap {.raises: [IOError], tags: [], forbids: [].}
```
Creates a bitmap sized to the page at the given scale, clears it, and renders the page.

- **Parameters:**
  - `page`: PDF page to render
  - `scale`: Scale factor for width/height in points
  - `alpha`: Whether to include an alpha channel
  - `rotate`: Rotation (default: 0)
  - `flags`: Rendering flags (default: 0)
## Usage Example

```nim
import pdfocr/pdfium

initPdfium()
var doc = loadDocument("input.pdf")
var page = loadPage(doc, 0)
var bitmap = renderPageAtScale(page, 2.0)

echo extractText(page)

destroy(bitmap)
close(page)
close(doc)
destroyPdfium()
```
#### `buffer()`
```nim
proc buffer(bitmap: PdfBitmap): pointer {.raises: [], tags: [], forbids: [].}
```
Returns a pointer to the bitmap's pixel data buffer.

#### `stride()`
```nim
proc stride(bitmap: PdfBitmap): int {.raises: [], tags: [], forbids: [].}
```
Returns the stride (bytes per row) of the bitmap.

### Text Operations

#### `extractText()`
```nim
proc extractText(page: PdfPage): string {.raises: [IOError], tags: [], forbids: [].}
```
Extracts all text from a PDF page.

- **Returns:** The extracted text as a string

#### `loadTextPage()`
```nim
proc loadTextPage(page: PdfPage): PdfTextPage {.raises: [IOError], tags: [], forbids: [].}
```
Loads the text page for more granular text access.

- **Returns:** `PdfTextPage` handle
- **Raises:** `IOError` if the text page cannot be loaded

#### `close()` (text page)
```nim
proc close(textPage: var PdfTextPage) {.raises: [], tags: [], forbids: [].}
```
Closes a text page and releases its resources.

#### `charCount()`
```nim
proc charCount(textPage: PdfTextPage): int {.raises: [], tags: [], forbids: [].}
```
Returns the number of characters in the text page.

#### `getTextRange()`
```nim
proc getTextRange(textPage: PdfTextPage; startIndex, count: int): string {.raises: [], tags: [], forbids: [].}
```
Extracts a range of text from the text page.

- **Parameters:**
  - `textPage`: The text page
  - `startIndex`: Starting character index
  - `count`: Number of characters to extract
- **Returns:** The extracted text

#### `getCharBox()`
```nim
proc getCharBox(textPage: PdfTextPage; index: int): tuple[left, right, bottom, top: float] {.raises: [], tags: [], forbids: [].}
```
Returns the bounding box of a character at the given index.

- **Returns:** A tuple with `left`, `right`, `bottom`, `top` coordinates

## Error Handling

### `lastErrorCode()`
```nim
proc lastErrorCode(): culong {.raises: [], tags: [], forbids: [].}
```
Returns the last error code from PDFium.

### `raisePdfiumError()`
```nim
proc raisePdfiumError(context: string) {.noinline, raises: [IOError], tags: [], forbids: [].}
```
Raises an IOError with PDFium error information.
