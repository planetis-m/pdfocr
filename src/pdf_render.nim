import ./[pdfium_wrap, types, webp_wrap]

proc renderPageBitmap*(doc: PdfDocument; pageNumber: int; scale: float): PdfBitmap =
  let page = loadPage(doc, pageNumber - 1)
  result = renderPageAtScale(page, scale)

proc encodePageBitmap*(bitmap: PdfBitmap; quality: float32): seq[byte] =
  let width = bitmap.width()
  let height = bitmap.height()
  if width < 1 or height < 1:
    raise newException(ValueError, "invalid bitmap size")
  result = compressBgr(
    width = width.Positive,
    height = height.Positive,
    pixels = bitmap.buffer(),
    stride = bitmap.stride(),
    quality = quality
  )

proc renderPageToWebp*(doc: PdfDocument; pageNumber: int;
    cfg: RenderConfig): seq[byte] =
  let bitmap = renderPageBitmap(doc, pageNumber, cfg.renderScale)
  result = encodePageBitmap(bitmap, cfg.webpQuality)
