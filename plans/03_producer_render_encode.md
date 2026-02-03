# Phase 3: Producer Stage (Render + JPEG Encode)

## Goals
- Render PDF pages to bitmaps and encode to JPEG.
- Emit `TaskBatch` messages with bounded memory and backpressure.

## Steps
1. Implement producer module `src/pdfocr/producer.nim`:
   - Accepts `PdfDocument`, page range, render params, JPEG quality, and input channel handle.
   - Runs in its own thread; owns PDFium page and bitmap objects.

2. For each page index in range:
   - `loadPage(doc, index)` (docs/pdfium.md).
   - Render at configured scale/DPI using `renderPageAtScale` (docs/pdfium.md).
   - Get pixel buffer with `buffer(bitmap)` and `stride(bitmap)` (docs/pdfium.md).
   - Encode using `pdfocr.jpeglib.initJpegCompressorBgrx`, `writeBgrx`, `finish` (docs/jpeglib.md).
   - Read JPEG bytes into memory (temporary file or in-memory buffer depending on available utilities).
     - If the jpeglib wrapper only writes to files, write to a temp file and read bytes, then delete the temp file.

3. Build `Task` objects containing:
   - `page_id` (0-based within selected range), `page_number_user` (1-based), `jpeg_bytes`, `attempt = 0`, timestamps.

4. Batching and backpressure:
   - Aggregate `Task` into vectors up to `PRODUCER_BATCH`.
   - Send `TaskBatch(Vec[Task])` on the input channel.
   - Block when the channel is full to enforce memory bounds.

5. After the last page:
   - Send `InputDone` and exit the producer thread.

6. Error handling:
   - Convert PDF/render errors to `PDF_ERROR`.
   - Convert JPEG errors to `ENCODE_ERROR`.
   - On fatal initialization errors (e.g., cannot open PDF), signal main to exit non-zero.

## API References
- Page render: `pdfocr.pdfium.loadPage`, `renderPageAtScale`, `buffer`, `stride`, `close` (docs/pdfium.md)
- JPEG encode: `pdfocr.jpeglib.initJpegCompressorBgrx`, `writeBgrx`, `finish` (docs/jpeglib.md)
