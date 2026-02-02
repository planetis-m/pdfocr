import std/[math, tables, sets, algorithm]
import ./pdfium

# Case-object based layout implementation (static dispatch).

type
  Rect* = tuple[x0, y0, x1, y1: float]

  LAParams* = object
    lineOverlap*: float
    charMargin*: float
    lineMargin*: float
    wordMargin*: float
    detectVertical*: bool

  LTTextBox* = object
    bbox*: Rect
    text*: string

  LTPage* = object
    pageid*: int
    bbox*: Rect
    textboxes*: seq[LTTextBox]

  ItemKind = enum
    ikChar, ikAnno, ikTextLine, ikTextBox

  Item = object
    kind: ItemKind
    bbox: Rect
    text: string
    wordMargin: float
    items: seq[int]
    lastX1: float
    lastY0: float

proc newLAParams*(
  lineOverlap: float = 0.5,
  charMargin: float = 2.0,
  lineMargin: float = 0.5,
  wordMargin: float = 0.1,
  detectVertical: bool = false,
  boxesFlowEnabled: bool = false
): LAParams =
  # boxesFlowEnabled exists for API compatibility; case layout always uses simple ordering.
  LAParams(lineOverlap: lineOverlap, charMargin: charMargin, lineMargin: lineMargin,
           wordMargin: wordMargin, detectVertical: detectVertical)

proc isEmpty(bbox: Rect): bool =
  (bbox.x1 - bbox.x0) <= 0 or (bbox.y1 - bbox.y0) <= 0

proc mergeBBox(a, b: Rect): Rect =
  (min(a.x0, b.x0), min(a.y0, b.y0), max(a.x1, b.x1), max(a.y1, b.y1))

proc width(b: Rect): float = b.x1 - b.x0
proc height(b: Rect): float = b.y1 - b.y0

proc isHoverlap(a, b: Rect): bool = b.x0 <= a.x1 and a.x0 <= b.x1
proc isVoverlap(a, b: Rect): bool = b.y0 <= a.y1 and a.y0 <= b.y1

proc hDistance(a, b: Rect): float =
  if isHoverlap(a, b): 0.0
  else: min(abs(a.x0 - b.x1), abs(a.x1 - b.x0))

proc vDistance(a, b: Rect): float =
  if isVoverlap(a, b): 0.0
  else: min(abs(a.y0 - b.y1), abs(a.y1 - b.y0))

proc hOverlap(a, b: Rect): float =
  if isHoverlap(a, b): min(abs(a.x0 - b.x1), abs(a.x1 - b.x0)) else: 0.0

proc vOverlap(a, b: Rect): float =
  if isVoverlap(a, b): min(abs(a.y0 - b.y1), abs(a.y1 - b.y0)) else: 0.0

proc addItem(items: var seq[Item]; parentIdx, childIdx: int) =
  items[parentIdx].items.add(childIdx)
  if items[childIdx].kind != ikAnno:
    items[parentIdx].bbox = mergeBBox(items[parentIdx].bbox, items[childIdx].bbox)

proc newChar(bbox: Rect; ch: string): Item =
  Item(kind: ikChar, bbox: bbox, text: ch, wordMargin: 0.0, items: @[], lastX1: 0, lastY0: 0)

proc newAnno(text: string): Item =
  Item(kind: ikAnno, bbox: (0.0, 0.0, 0.0, 0.0), text: text, items: @[], wordMargin: 0.0)

proc newTextLine(wordMargin: float): Item =
  Item(kind: ikTextLine, bbox: (1e30, 1e30, -1e30, -1e30), text: "", items: @[],
       wordMargin: wordMargin, lastX1: 1e30, lastY0: -1e30)

proc newTextBox(): Item =
  Item(kind: ikTextBox, bbox: (1e30, 1e30, -1e30, -1e30), text: "", items: @[],
       wordMargin: 0.0)

proc textOf(items: seq[Item]; idx: int): string =
  let it = items[idx]
  case it.kind
  of ikChar, ikAnno:
    it.text
  of ikTextLine, ikTextBox:
    var textOut = ""
    for child in it.items:
      textOut.add(textOf(items, child))
    textOut

proc addToTextLine(items: var seq[Item]; lineIdx, charIdx: int) =
  let charBox = items[charIdx].bbox
  if items[charIdx].kind == ikChar and items[lineIdx].wordMargin != 0:
    let margin = items[lineIdx].wordMargin * max(width(charBox), height(charBox))
    if items[lineIdx].lastX1 < charBox.x0 - margin:
      items.add(newAnno(" "))
      addItem(items, lineIdx, items.len - 1)
  items[lineIdx].lastX1 = charBox.x1
  addItem(items, lineIdx, charIdx)

proc groupObjects(chars: seq[int]; items: var seq[Item]; p: LAParams): seq[int] =
  result = @[]
  var prevIdx = -1
  var lineIdx = -1
  for idx in chars:
    if prevIdx != -1:
      let a = items[prevIdx].bbox
      let b = items[idx].bbox
      let halign = isVoverlap(a, b) and min(height(a), height(b)) * p.lineOverlap < vOverlap(a, b) and
                   hDistance(a, b) < max(width(a), width(b)) * p.charMargin
      let valign = p.detectVertical and isHoverlap(a, b) and min(width(a), width(b)) * p.lineOverlap < hOverlap(a, b) and
                   vDistance(a, b) < max(height(a), height(b)) * p.charMargin

      if lineIdx != -1 and (halign or valign):
        addToTextLine(items, lineIdx, idx)
      elif lineIdx != -1:
        result.add(lineIdx)
        lineIdx = -1
      elif halign or valign:
        items.add(newTextLine(p.wordMargin))
        lineIdx = items.len - 1
        addToTextLine(items, lineIdx, prevIdx)
        addToTextLine(items, lineIdx, idx)
      else:
        items.add(newTextLine(p.wordMargin))
        let oneLine = items.len - 1
        addToTextLine(items, oneLine, prevIdx)
        result.add(oneLine)
        lineIdx = -1
    prevIdx = idx
  if lineIdx == -1:
    items.add(newTextLine(p.wordMargin))
    lineIdx = items.len - 1
    if prevIdx != -1:
      addToTextLine(items, lineIdx, prevIdx)
  result.add(lineIdx)

proc findNeighbors(lines: seq[int]; items: seq[Item]; lineIdx: int; ratio: float): seq[int] =
  let selfBox = items[lineIdx].bbox
  let d = ratio * height(selfBox)
  let query: Rect = (x0: selfBox.x0, y0: selfBox.y0 - d, x1: selfBox.x1, y1: selfBox.y1 + d)
  result = @[]
  for idx in lines:
    if idx == lineIdx: continue
    let b = items[idx].bbox
    if b.x1 < query.x0 or b.x0 > query.x1 or b.y1 < query.y0 or b.y0 > query.y1:
      continue
    if abs(height(b) - height(selfBox)) <= d:
      let leftAligned = abs(b.x0 - selfBox.x0) <= d
      let rightAligned = abs(b.x1 - selfBox.x1) <= d
      let centerAligned = abs(((b.x0 + b.x1)/2) - ((selfBox.x0 + selfBox.x1)/2)) <= d
      if leftAligned or rightAligned or centerAligned:
        result.add(idx)

proc groupTextlines(lines: seq[int]; items: var seq[Item]; p: LAParams): seq[int] =
  result = @[]
  var lineToBox = initTable[int, int]()
  var boxToLines = initTable[int, seq[int]]()

  for lineIdx in lines:
    let neighbors = findNeighbors(lines, items, lineIdx, p.lineMargin)
    var members = @[lineIdx]
    for n in neighbors:
      members.add(n)
      if lineToBox.hasKey(n):
        let existingBox = lineToBox[n]
        if boxToLines.hasKey(existingBox):
          for m in boxToLines[existingBox]:
            members.add(m)
          boxToLines.del(existingBox)

    items.add(newTextBox())
    let boxIdx = items.len - 1

    var seen = initHashSet[int]()
    var uniqMembers: seq[int] = @[]
    for m in members:
      if m notin seen:
        seen.incl(m)
        uniqMembers.add(m)

    for m in uniqMembers:
      addItem(items, boxIdx, m)
      lineToBox[m] = boxIdx
    boxToLines[boxIdx] = uniqMembers

  var done = initHashSet[int]()
  for lineIdx in lines:
    if not lineToBox.hasKey(lineIdx):
      continue
    let boxIdx = lineToBox[lineIdx]
    if boxIdx in done:
      continue
    done.incl(boxIdx)
    if not isEmpty(items[boxIdx].bbox):
      result.add(boxIdx)

proc buildLayout(page: PdfPage; p: LAParams): LTPage =
  var textPage = loadTextPage(page)
  defer: close(textPage)

  let count = charCount(textPage)
  let (w, h) = pageSize(page)

  var items: seq[Item] = @[]
  for i in 0 ..< count:
    let (left, right, bottom, top) = getCharBox(textPage, i)
    if right <= left or top <= bottom:
      continue
    let ch = getTextRange(textPage, i, 1)
    if ch.len == 0:
      continue
    items.add(newChar((left, bottom, right, top), ch))

  var charIdxs: seq[int] = @[]
  for i in 0 ..< items.len:
    if items[i].kind == ikChar:
      charIdxs.add(i)

  let lines = groupObjects(charIdxs, items, p)
  for lineIdx in lines:
    items.add(newAnno("\n"))
    addItem(items, lineIdx, items.len - 1)

  var nonEmpty: seq[int] = @[]
  for lineIdx in lines:
    if not isEmpty(items[lineIdx].bbox):
      nonEmpty.add(lineIdx)

  let boxes = groupTextlines(nonEmpty, items, p)
  var sortedBoxes = boxes
  sortedBoxes.sort(proc(a, b: int): int =
    let ka = (1, -items[a].bbox.y0, items[a].bbox.x0)
    let kb = (1, -items[b].bbox.y0, items[b].bbox.x0)
    if ka < kb: return -1
    if ka > kb: return 1
    0
  )

  var outBoxes: seq[LTTextBox] = @[]
  for b in sortedBoxes:
    outBoxes.add(LTTextBox(bbox: items[b].bbox, text: textOf(items, b)))

  LTPage(pageid: 0, bbox: (0.0, 0.0, w, h), textboxes: outBoxes)

proc buildTextPageLayout*(page: PdfPage; laparams: LAParams = newLAParams()): LTPage =
  buildLayout(page, laparams)
