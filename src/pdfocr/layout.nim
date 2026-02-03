import std/[math, tables, sets, algorithm, heapqueue, options]
import ./pdfium

const
  INF = 2147483647.0

type
  Rect* = tuple[x0, y0, x1, y1: float]

  LAParams* = object
    lineOverlap*: float
    charMargin*: float
    lineMargin*: float
    wordMargin*: float
    boxesFlow*: Option[float]  # None disables hierarchical grouping
    detectVertical*: bool
    allTexts*: bool

  LTTextBox* = object
    bbox*: Rect
    text*: string
    index*: int

  LTPage* = object
    pageid*: int
    bbox*: Rect
    textboxes*: seq[LTTextBox]

  ItemKind = enum
    ikChar
    ikAnno
    ikTextLineHorizontal
    ikTextLineVertical
    ikTextBoxHorizontal
    ikTextBoxVertical
    ikTextGroupLRTB       # Horizontal group (left-right, top-bottom)
    ikTextGroupTBRL       # Vertical group (top-bottom, right-left)

  Item = object
    kind: ItemKind
    bbox: Rect
    text: string
    wordMargin: float
    items: seq[int]
    lastX1: float
    lastY0: float
    index: int

  # Priority queue element for hierarchical grouping
  DistElement = object
    skipIsany: bool
    dist: float
    id1: int
    id2: int
    idx1: int
    idx2: int

proc `<`(a, b: DistElement): bool =
  if a.dist != b.dist: return a.dist < b.dist
  if a.id1 != b.id1: return a.id1 < b.id1
  return a.id2 < b.id2

proc newLAParams*(
  lineOverlap: float = 0.5,
  charMargin: float = 2.0,
  lineMargin: float = 0.5,
  wordMargin: float = 0.1,
  boxesFlow: Option[float] = some(0.5),
  detectVertical: bool = false,
  allTexts: bool = false
): LAParams =
  LAParams(
    lineOverlap: lineOverlap,
    charMargin: charMargin,
    lineMargin: lineMargin,
    wordMargin: wordMargin,
    boxesFlow: boxesFlow,
    detectVertical: detectVertical,
    allTexts: allTexts
  )

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
  Item(kind: ikChar, bbox: bbox, text: ch, wordMargin: 0.0, items: @[], 
       lastX1: 0, lastY0: 0, index: -1)

proc newAnno(text: string): Item =
  Item(kind: ikAnno, bbox: (0.0, 0.0, 0.0, 0.0), text: text, items: @[], 
       wordMargin: 0.0, index: -1)

proc newTextLineHorizontal(wordMargin: float): Item =
  Item(kind: ikTextLineHorizontal, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: wordMargin, lastX1: INF, lastY0: -INF, index: -1)

proc newTextLineVertical(wordMargin: float): Item =
  Item(kind: ikTextLineVertical, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: wordMargin, lastX1: INF, lastY0: -INF, index: -1)

proc newTextBoxHorizontal(): Item =
  Item(kind: ikTextBoxHorizontal, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: 0.0, index: -1)

proc newTextBoxVertical(): Item =
  Item(kind: ikTextBoxVertical, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: 0.0, index: -1)

proc newTextGroupLRTB(): Item =
  Item(kind: ikTextGroupLRTB, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: 0.0, index: -1)

proc newTextGroupTBRL(): Item =
  Item(kind: ikTextGroupTBRL, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: 0.0, index: -1)

proc isVerticalItem(items: seq[Item]; idx: int): bool =
  ## Check if an item is vertical (vertical box or TBRL group)
  items[idx].kind in {ikTextBoxVertical, ikTextGroupTBRL}

proc textOf(items: seq[Item]; idx: int): string =
  let it = items[idx]
  case it.kind
  of ikChar, ikAnno:
    it.text
  of ikTextLineHorizontal, ikTextLineVertical, ikTextBoxHorizontal, 
     ikTextBoxVertical, ikTextGroupLRTB, ikTextGroupTBRL:
    var textOut = ""
    for child in it.items:
      textOut.add(textOf(items, child))
    textOut

proc addToTextLineHorizontal(items: var seq[Item]; lineIdx, charIdx: int) =
  let charBox = items[charIdx].bbox
  if items[charIdx].kind == ikChar and items[lineIdx].wordMargin != 0:
    let margin = items[lineIdx].wordMargin * max(width(charBox), height(charBox))
    if items[lineIdx].lastX1 < charBox.x0 - margin:
      items.add(newAnno(" "))
      addItem(items, lineIdx, items.len - 1)
  items[lineIdx].lastX1 = charBox.x1
  addItem(items, lineIdx, charIdx)

proc addToTextLineVertical(items: var seq[Item]; lineIdx, charIdx: int) =
  let charBox = items[charIdx].bbox
  if items[charIdx].kind == ikChar and items[lineIdx].wordMargin != 0:
    let margin = items[lineIdx].wordMargin * max(width(charBox), height(charBox))
    if charBox.y1 + margin < items[lineIdx].lastY0:
      items.add(newAnno(" "))
      addItem(items, lineIdx, items.len - 1)
  items[lineIdx].lastY0 = charBox.y0
  addItem(items, lineIdx, charIdx)

proc groupObjects(chars: seq[int]; items: var seq[Item]; p: LAParams): seq[int] =
  result = @[]
  
  # Handle empty input
  if chars.len == 0:
    return result
  
  var prevIdx = -1
  var lineIdx = -1
  
  for idx in chars:
    if prevIdx != -1:
      let a = items[prevIdx].bbox
      let b = items[idx].bbox
      
      # Check horizontal alignment
      let halign = isVoverlap(a, b) and 
                   min(height(a), height(b)) * p.lineOverlap < vOverlap(a, b) and
                   hDistance(a, b) < max(width(a), width(b)) * p.charMargin
      
      # Check vertical alignment
      let valign = p.detectVertical and isHoverlap(a, b) and 
                   min(width(a), width(b)) * p.lineOverlap < hOverlap(a, b) and
                   vDistance(a, b) < max(height(a), height(b)) * p.charMargin

      # Continue existing line or start new one
      if (halign and lineIdx != -1 and items[lineIdx].kind == ikTextLineHorizontal):
        addToTextLineHorizontal(items, lineIdx, idx)
      elif (valign and lineIdx != -1 and items[lineIdx].kind == ikTextLineVertical):
        addToTextLineVertical(items, lineIdx, idx)
      elif lineIdx != -1:
        # End current line
        result.add(lineIdx)
        lineIdx = -1
      elif valign and not halign:
        # Start vertical line
        items.add(newTextLineVertical(p.wordMargin))
        lineIdx = items.len - 1
        addToTextLineVertical(items, lineIdx, prevIdx)
        addToTextLineVertical(items, lineIdx, idx)
      elif halign and not valign:
        # Start horizontal line
        items.add(newTextLineHorizontal(p.wordMargin))
        lineIdx = items.len - 1
        addToTextLineHorizontal(items, lineIdx, prevIdx)
        addToTextLineHorizontal(items, lineIdx, idx)
      else:
        # Neither aligned - create single-char horizontal line
        items.add(newTextLineHorizontal(p.wordMargin))
        let oneLine = items.len - 1
        addToTextLineHorizontal(items, oneLine, prevIdx)
        result.add(oneLine)
        lineIdx = -1
    prevIdx = idx
  
  # Handle last character
  if lineIdx == -1:
    items.add(newTextLineHorizontal(p.wordMargin))
    lineIdx = items.len - 1
    addToTextLineHorizontal(items, lineIdx, prevIdx)
  result.add(lineIdx)

proc findNeighborsHorizontal(lines: seq[int]; items: seq[Item]; 
                             lineIdx: int; ratio: float): seq[int] =
  let selfBox = items[lineIdx].bbox
  let d = ratio * height(selfBox)
  let query: Rect = (x0: selfBox.x0, y0: selfBox.y0 - d, 
                     x1: selfBox.x1, y1: selfBox.y1 + d)
  result = @[]
  
  for idx in lines:
    if idx == lineIdx: continue
    let b = items[idx].bbox
    
    # Must be in query range
    if b.x1 < query.x0 or b.x0 > query.x1 or b.y1 < query.y0 or b.y0 > query.y1:
      continue
    
    # Must be horizontal and same height
    if items[idx].kind != ikTextLineHorizontal:
      continue
    if abs(height(b) - height(selfBox)) > d:
      continue
    
    # Check alignment
    let leftAligned = abs(b.x0 - selfBox.x0) <= d
    let rightAligned = abs(b.x1 - selfBox.x1) <= d
    let centerAligned = abs(((b.x0 + b.x1)/2) - ((selfBox.x0 + selfBox.x1)/2)) <= d
    
    if leftAligned or rightAligned or centerAligned:
      result.add(idx)

proc findNeighborsVertical(lines: seq[int]; items: seq[Item]; 
                           lineIdx: int; ratio: float): seq[int] =
  let selfBox = items[lineIdx].bbox
  let d = ratio * width(selfBox)
  let query: Rect = (x0: selfBox.x0 - d, y0: selfBox.y0, 
                     x1: selfBox.x1 + d, y1: selfBox.y1)
  result = @[]
  
  for idx in lines:
    if idx == lineIdx: continue
    let b = items[idx].bbox
    
    # Must be in query range
    if b.x1 < query.x0 or b.x0 > query.x1 or b.y1 < query.y0 or b.y0 > query.y1:
      continue
    
    # Must be vertical and same width
    if items[idx].kind != ikTextLineVertical:
      continue
    if abs(width(b) - width(selfBox)) > d:
      continue
    
    # Check alignment
    let lowerAligned = abs(b.y0 - selfBox.y0) <= d
    let upperAligned = abs(b.y1 - selfBox.y1) <= d
    let centerAligned = abs(((b.y0 + b.y1)/2) - ((selfBox.y0 + selfBox.y1)/2)) <= d
    
    if lowerAligned or upperAligned or centerAligned:
      result.add(idx)

proc groupTextlines(lines: seq[int]; items: var seq[Item]; p: LAParams): seq[int] =
  result = @[]
  var lineToBox = initTable[int, int]()
  var boxToLines = initTable[int, seq[int]]()

  for lineIdx in lines:
    # Find neighbors based on line type
    let neighbors = 
      if items[lineIdx].kind == ikTextLineHorizontal:
        findNeighborsHorizontal(lines, items, lineIdx, p.lineMargin)
      else:
        findNeighborsVertical(lines, items, lineIdx, p.lineMargin)
    
    var members = @[lineIdx]
    for n in neighbors:
      members.add(n)
      if lineToBox.hasKey(n):
        let existingBox = lineToBox[n]
        if boxToLines.hasKey(existingBox):
          for m in boxToLines[existingBox]:
            members.add(m)
          boxToLines.del(existingBox)

    # Create appropriate box type
    let isVertical = items[lineIdx].kind == ikTextLineVertical
    if isVertical:
      items.add(newTextBoxVertical())
    else:
      items.add(newTextBoxHorizontal())
    let boxIdx = items.len - 1

    # Add unique members
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

  # Collect unique boxes
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

proc analyzeBox(items: var seq[Item]; boxIdx: int) =
  ## Sort lines within a box by reading order
  if items[boxIdx].kind == ikTextBoxHorizontal:
    # Sort top to bottom
    items[boxIdx].items.sort(proc(a, b: int): int =
      let ay1 = items[a].bbox.y1
      let by1 = items[b].bbox.y1
      if ay1 > by1: return -1
      if ay1 < by1: return 1
      return 0
    )
  elif items[boxIdx].kind == ikTextBoxVertical:
    # Sort right to left
    items[boxIdx].items.sort(proc(a, b: int): int =
      let ax1 = items[a].bbox.x1
      let bx1 = items[b].bbox.x1
      if ax1 > bx1: return -1
      if ax1 < bx1: return 1
      return 0
    )

proc boxDistance(items: seq[Item]; idx1, idx2: int): float =
  ## Distance function for hierarchical grouping
  let b1 = items[idx1].bbox
  let b2 = items[idx2].bbox
  let x0 = min(b1.x0, b2.x0)
  let y0 = min(b1.y0, b2.y0)
  let x1 = max(b1.x1, b2.x1)
  let y1 = max(b1.y1, b2.y1)
  return (x1 - x0) * (y1 - y0) - width(b1) * height(b1) - width(b2) * height(b2)

proc hasObjectBetween(items: seq[Item]; activeBoxes: HashSet[int]; 
                      idx1, idx2: int): bool =
  ## Check if any box exists between idx1 and idx2
  let b1 = items[idx1].bbox
  let b2 = items[idx2].bbox
  let x0 = min(b1.x0, b2.x0)
  let y0 = min(b1.y0, b2.y0)
  let x1 = max(b1.x1, b2.x1)
  let y1 = max(b1.y1, b2.y1)
  
  for boxIdx in activeBoxes:
    if boxIdx == idx1 or boxIdx == idx2:
      continue
    let b = items[boxIdx].bbox
    # Check if box overlaps the bounding rectangle
    if not (b.x1 < x0 or b.x0 > x1 or b.y1 < y0 or b.y0 > y1):
      return true
  return false

proc groupTextboxes(boxes: seq[int]; items: var seq[Item]; 
                    p: LAParams): seq[int] =
  ## Hierarchically group textboxes
  if boxes.len <= 1:
    return boxes
  
  var heap = initHeapQueue[DistElement]()
  var activeBoxes = initHashSet[int]()
  
  # Initialize with all pairwise distances
  for i in 0 ..< boxes.len:
    activeBoxes.incl(boxes[i])
    for j in i+1 ..< boxes.len:
      let dist = boxDistance(items, boxes[i], boxes[j])
      heap.push(DistElement(
        skipIsany: false,
        dist: dist,
        id1: boxes[i],
        id2: boxes[j],
        idx1: boxes[i],
        idx2: boxes[j]
      ))
  
  # Merge closest pairs
  while heap.len > 0:
    let elem = heap.pop()
    
    # Skip objects that were already merged
    if elem.idx1 notin activeBoxes or elem.idx2 notin activeBoxes:
      continue
    
    # Check if objects between (unless we already checked)
    if not elem.skipIsany:
      if hasObjectBetween(items, activeBoxes, elem.idx1, elem.idx2):
        # Re-add with skip flag
        heap.push(DistElement(
          skipIsany: true,
          dist: elem.dist,
          id1: elem.id1,
          id2: elem.id2,
          idx1: elem.idx1,
          idx2: elem.idx2
        ))
        continue
    
    # Determine group type based on box types
    # Use TBRL if either is vertical box or TBRL group
    let isVertical = isVerticalItem(items, elem.idx1) or 
                     isVerticalItem(items, elem.idx2)
    
    # Create appropriate group type
    if isVertical:
      items.add(newTextGroupTBRL())
    else:
      items.add(newTextGroupLRTB())
    let groupIdx = items.len - 1
    addItem(items, groupIdx, elem.idx1)
    addItem(items, groupIdx, elem.idx2)
    
    # Remove merged boxes from active set
    activeBoxes.excl(elem.idx1)
    activeBoxes.excl(elem.idx2)
    activeBoxes.incl(groupIdx)
    
    # Add distances from new group to all other active boxes
    for otherIdx in activeBoxes:
      if otherIdx != groupIdx:
        let dist = boxDistance(items, groupIdx, otherIdx)
        heap.push(DistElement(
          skipIsany: false,
          dist: dist,
          id1: min(groupIdx, otherIdx),
          id2: max(groupIdx, otherIdx),
          idx1: groupIdx,
          idx2: otherIdx
        ))
  
  # Return remaining active boxes/groups
  result = toSeq(activeBoxes)

proc assignIndices(items: var seq[Item]; idx: int; counter: var int) =
  ## Recursively assign indices for sorting
  if items[idx].kind in {ikTextBoxHorizontal, ikTextBoxVertical}:
    items[idx].index = counter
    counter += 1
  elif items[idx].kind in {ikTextGroupLRTB, ikTextGroupTBRL}:
    for child in items[idx].items:
      assignIndices(items, child, counter)

proc analyzeGroup(items: var seq[Item]; groupIdx: int; boxesFlow: float) =
  ## Recursively analyze groups and sort contents
  if items[groupIdx].kind in {ikTextGroupLRTB, ikTextGroupTBRL}:
    # First analyze children
    for child in items[groupIdx].items:
      analyzeGroup(items, child, boxesFlow)
    
    # Then sort based on group type and boxes_flow
    if items[groupIdx].kind == ikTextGroupTBRL:
      # TBRL ordering: top-right to bottom-left
      items[groupIdx].items.sort(proc(a, b: int): int =
        let ba = items[a].bbox
        let bb = items[b].bbox
        let ka = -(1.0 + boxesFlow) * (ba.x0 + ba.x1) - 
                 (1.0 - boxesFlow) * ba.y1
        let kb = -(1.0 + boxesFlow) * (bb.x0 + bb.x1) - 
                 (1.0 - boxesFlow) * bb.y1
        if ka < kb: return -1
        if ka > kb: return 1
        return 0
      )
    else:
      # LRTB ordering: top-left to bottom-right
      items[groupIdx].items.sort(proc(a, b: int): int =
        let ba = items[a].bbox
        let bb = items[b].bbox
        let ka = (1.0 - boxesFlow) * ba.x0 - 
                 (1.0 + boxesFlow) * (ba.y0 + ba.y1)
        let kb = (1.0 - boxesFlow) * bb.x0 - 
                 (1.0 + boxesFlow) * (bb.y0 + bb.y1)
        if ka < kb: return -1
        if ka > kb: return 1
        return 0
      )

proc isEmptyText(items: seq[Item]; idx: int): bool =
  ## Check if text line is empty (empty bbox or whitespace-only text)
  if isEmpty(items[idx].bbox):
    return true
  let text = textOf(items, idx)
  # Match Python's isspace() behavior: empty string returns false
  if text.len == 0:
    return false
  for c in text:
    if c notin {' ', '\t', '\n', '\r', '\f', '\v'}:
      return false
  return true

proc buildLayout(page: PdfPage; p: LAParams): LTPage =
  var textPage = loadTextPage(page)
  defer: close(textPage)

  let count = charCount(textPage)
  let (w, h) = pageSize(page)

  var items: seq[Item] = @[]
  
  # Extract characters
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

  # Handle empty input
  if charIdxs.len == 0:
    return LTPage(pageid: 0, bbox: (0.0, 0.0, w, h), textboxes: @[])

  # Group characters into lines
  let lines = groupObjects(charIdxs, items, p)
  
  # Add newlines to each line
  for lineIdx in lines:
    items.add(newAnno("\n"))
    addItem(items, lineIdx, items.len - 1)

  # Filter empty lines
  var nonEmpty: seq[int] = @[]
  for lineIdx in lines:
    if not isEmptyText(items, lineIdx):
      nonEmpty.add(lineIdx)

  # Group lines into boxes
  var boxes = groupTextlines(nonEmpty, items, p)
  
  # Analyze boxes (sort their contents)
  for boxIdx in boxes:
    analyzeBox(items, boxIdx)
  
  # Sort or group boxes based on boxes_flow
  var sortedBoxes: seq[int]
  
  if p.boxesFlow.isNone:
    # Simple geometric sorting (no hierarchical grouping)
    sortedBoxes = boxes
    sortedBoxes.sort(proc(a, b: int): int =
      let isVertA = items[a].kind == ikTextBoxVertical
      let isVertB = items[b].kind == ikTextBoxVertical
      
      if isVertA and not isVertB:
        return -1
      elif not isVertA and isVertB:
        return 1
      elif isVertA:
        # Both vertical: sort by -x1, then -y0
        if items[a].bbox.x1 > items[b].bbox.x1: return -1
        if items[a].bbox.x1 < items[b].bbox.x1: return 1
        if items[a].bbox.y0 > items[b].bbox.y0: return -1
        if items[a].bbox.y0 < items[b].bbox.y0: return 1
        return 0
      else:
        # Both horizontal: sort by -y0, then x0
        if items[a].bbox.y0 > items[b].bbox.y0: return -1
        if items[a].bbox.y0 < items[b].bbox.y0: return 1
        if items[a].bbox.x0 < items[b].bbox.x0: return -1
        if items[a].bbox.x0 > items[b].bbox.x0: return 1
        return 0
    )
  elif boxes.len > 1:
    # Hierarchical grouping
    let groups = groupTextboxes(boxes, items, p)
    let boxesFlow = p.boxesFlow.get()
    
    # Analyze groups
    for groupIdx in groups:
      analyzeGroup(items, groupIdx, boxesFlow)
    
    # Assign indices
    var counter = 0
    for groupIdx in groups:
      assignIndices(items, groupIdx, counter)
    
    # Collect all boxes sorted by index
    sortedBoxes = boxes
    sortedBoxes.sort(proc(a, b: int): int =
      if items[a].index < items[b].index: return -1
      if items[a].index > items[b].index: return 1
      return 0
    )
  else:
    # Single box or empty - no grouping needed
    sortedBoxes = boxes

  # Build output
  var outBoxes: seq[LTTextBox] = @[]
  for b in sortedBoxes:
    outBoxes.add(LTTextBox(
      bbox: items[b].bbox, 
      text: textOf(items, b),
      index: items[b].index
    ))

  LTPage(pageid: 0, bbox: (0.0, 0.0, w, h), textboxes: outBoxes)

proc buildTextPageLayout*(page: PdfPage; laparams: LAParams = newLAParams()): LTPage =
  buildLayout(page, laparams)
