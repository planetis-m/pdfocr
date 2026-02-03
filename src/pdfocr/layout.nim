import std/[math, tables, sets, algorithm, heapqueue, options, unicode]
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
    uniqueId: int  # Unique identifier for heap ordering

  # Priority queue element for hierarchical grouping
  DistElement = object
    skipIsany: bool
    dist: float
    id1: int  # Unique ID of first object (for stable ordering)
    id2: int  # Unique ID of second object (for stable ordering)
    idx1: int  # Index in items array
    idx2: int  # Index in items array

# Global unique ID counter for stable heap ordering
var globalIdCounter = 0

proc nextUniqueId(): int =
  result = globalIdCounter
  inc globalIdCounter

proc `<`(a, b: DistElement): bool =
  # Compare skipIsany first (False < True in Python)
  if a.skipIsany != b.skipIsany: return a.skipIsany < b.skipIsany
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

# ============================================================================
# Item constructors and helpers
# ============================================================================

proc addItem(items: var seq[Item]; parentIdx, childIdx: int) =
  items[parentIdx].items.add(childIdx)
  if items[childIdx].kind != ikAnno:
    items[parentIdx].bbox = mergeBBox(items[parentIdx].bbox, items[childIdx].bbox)

proc newChar(bbox: Rect; ch: string): Item =
  Item(kind: ikChar, bbox: bbox, text: ch, wordMargin: 0.0, items: @[], 
       lastX1: 0, lastY0: 0, index: -1, uniqueId: nextUniqueId())

proc newAnno(text: string): Item =
  Item(kind: ikAnno, bbox: (0.0, 0.0, 0.0, 0.0), text: text, items: @[], 
       wordMargin: 0.0, index: -1, uniqueId: nextUniqueId())

proc newTextLineHorizontal(wordMargin: float): Item =
  Item(kind: ikTextLineHorizontal, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: wordMargin, lastX1: INF, lastY0: -INF, 
       index: -1, uniqueId: nextUniqueId())

proc newTextLineVertical(wordMargin: float): Item =
  Item(kind: ikTextLineVertical, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: wordMargin, lastX1: INF, lastY0: -INF, 
       index: -1, uniqueId: nextUniqueId())

proc newTextBoxHorizontal(): Item =
  Item(kind: ikTextBoxHorizontal, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: 0.0, index: -1, uniqueId: nextUniqueId())

proc newTextBoxVertical(): Item =
  Item(kind: ikTextBoxVertical, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: 0.0, index: -1, uniqueId: nextUniqueId())

proc newTextGroupLRTB(): Item =
  Item(kind: ikTextGroupLRTB, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: 0.0, index: -1, uniqueId: nextUniqueId())

proc newTextGroupTBRL(): Item =
  Item(kind: ikTextGroupTBRL, bbox: (INF, INF, -INF, -INF), text: "", 
       items: @[], wordMargin: 0.0, index: -1, uniqueId: nextUniqueId())

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

proc findNeighborsHorizontal(plane: Plane; items: seq[Item]; 
                             lineIdx: int; ratio: float): seq[int] =
  ## Find neighboring horizontal text lines using the Plane spatial index
  let selfBox = items[lineIdx].bbox
  let d = ratio * height(selfBox)
  let query: Rect = (x0: selfBox.x0, y0: selfBox.y0 - d, 
                     x1: selfBox.x1, y1: selfBox.y1 + d)
  
  result = @[]
  for idx in plane.find(query, items):
    # Must be horizontal
    if items[idx].kind != ikTextLineHorizontal:
      continue
    
    let b = items[idx].bbox
    
    # Must be same height
    if abs(height(b) - height(selfBox)) > d:
      continue
    
    # Check alignment (left, right, or center)
    let leftAligned = abs(b.x0 - selfBox.x0) <= d
    let rightAligned = abs(b.x1 - selfBox.x1) <= d
    let centerAligned = abs(((b.x0 + b.x1)/2) - ((selfBox.x0 + selfBox.x1)/2)) <= d
    
    if leftAligned or rightAligned or centerAligned:
      result.add(idx)

proc findNeighborsVertical(plane: Plane; items: seq[Item]; 
                           lineIdx: int; ratio: float): seq[int] =
  ## Find neighboring vertical text lines using the Plane spatial index
  let selfBox = items[lineIdx].bbox
  let d = ratio * width(selfBox)
  let query: Rect = (x0: selfBox.x0 - d, y0: selfBox.y0, 
                     x1: selfBox.x1 + d, y1: selfBox.y1)
  
  result = @[]
  for idx in plane.find(query, items):
    # Must be vertical
    if items[idx].kind != ikTextLineVertical:
      continue
    
    let b = items[idx].bbox
    
    # Must be same width
    if abs(width(b) - width(selfBox)) > d:
      continue
    
    # Check alignment (lower, upper, or center)
    let lowerAligned = abs(b.y0 - selfBox.y0) <= d
    let upperAligned = abs(b.y1 - selfBox.y1) <= d
    let centerAligned = abs(((b.y0 + b.y1)/2) - ((selfBox.y0 + selfBox.y1)/2)) <= d
    
    if lowerAligned or upperAligned or centerAligned:
      result.add(idx)

proc groupTextlines(lines: seq[int]; items: var seq[Item]; p: LAParams;
                    containerBBox: Rect): seq[int] =
  ## Group neighboring lines into textboxes using Plane for spatial queries
  result = @[]
  
  # Create plane with container bbox and add all lines
  var plane = newPlane(containerBBox)
  plane.extend(lines, items)
  
  var lineToBox = initTable[int, int]()
  var boxToLines = initTable[int, seq[int]]()

  for lineIdx in lines:
    # Find neighbors based on line type
    let neighbors = 
      if items[lineIdx].kind == ikTextLineHorizontal:
        findNeighborsHorizontal(plane, items, lineIdx, p.lineMargin)
      else:
        findNeighborsVertical(plane, items, lineIdx, p.lineMargin)
    
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

    # Add unique members (preserving order like Python's uniq)
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
    # Sort top to bottom (by -y1)
    items[boxIdx].items.sort(proc(a, b: int): int =
      let ay1 = items[a].bbox.y1
      let by1 = items[b].bbox.y1
      if ay1 > by1: return -1
      if ay1 < by1: return 1
      return 0
    )
  elif items[boxIdx].kind == ikTextBoxVertical:
    # Sort right to left (by -x1)
    items[boxIdx].items.sort(proc(a, b: int): int =
      let ax1 = items[a].bbox.x1
      let bx1 = items[b].bbox.x1
      if ax1 > bx1: return -1
      if ax1 < bx1: return 1
      return 0
    )

proc boxDistance(items: seq[Item]; idx1, idx2: int): float =
  ## Distance function for hierarchical grouping
  ## Returns the area of bounding box minus the areas of both objects
  let b1 = items[idx1].bbox
  let b2 = items[idx2].bbox
  let x0 = min(b1.x0, b2.x0)
  let y0 = min(b1.y0, b2.y0)
  let x1 = max(b1.x1, b2.x1)
  let y1 = max(b1.y1, b2.y1)
  return (x1 - x0) * (y1 - y0) - width(b1) * height(b1) - width(b2) * height(b2)

proc isanyBetween(plane: Plane; items: seq[Item]; idx1, idx2: int): bool =
  ## Check if there's any other object between idx1 and idx2 using Plane.find
  let b1 = items[idx1].bbox
  let b2 = items[idx2].bbox
  let x0 = min(b1.x0, b2.x0)
  let y0 = min(b1.y0, b2.y0)
  let x1 = max(b1.x1, b2.x1)
  let y1 = max(b1.y1, b2.y1)
  
  let found = plane.find((x0, y0, x1, y1), items)
  for idx in found:
    if idx != idx1 and idx != idx2:
      return true
  return false

proc groupTextboxes(boxes: seq[int]; items: var seq[Item]; 
                    containerBBox: Rect): seq[int] =
  ## Hierarchically group textboxes using Plane for spatial queries
  if boxes.len <= 1:
    return boxes
  
  var plane = newPlane(containerBBox)
  var heap = initHeapQueue[DistElement]()
  var idToIdx = initTable[int, int]()  # Map unique ID to current index
  
  # Initialize plane with all boxes and build initial distance pairs
  for i in 0 ..< boxes.len:
    let idx = boxes[i]
    plane.add(idx, items)
    idToIdx[items[idx].uniqueId] = idx
    for j in i+1 ..< boxes.len:
      let idx2 = boxes[j]
      let dist = boxDistance(items, idx, idx2)
      heap.push(DistElement(
        skipIsany: false,
        dist: dist,
        id1: items[idx].uniqueId,
        id2: items[idx2].uniqueId,
        idx1: idx,
        idx2: idx2
      ))
  
  # Merge closest pairs
  while heap.len > 0:
    let elem = heap.pop()
    
    # Skip objects that were already merged (check if still in plane)
    if not plane.contains(elem.idx1) or not plane.contains(elem.idx2):
      continue
    
    let idx1 = elem.idx1
    let idx2 = elem.idx2
    
    # Check if objects between (unless we already checked)
    if not elem.skipIsany:
      if isanyBetween(plane, items, idx1, idx2):
        # Re-add with skip flag
        heap.push(DistElement(
          skipIsany: true,
          dist: elem.dist,
          id1: elem.id1,
          id2: elem.id2,
          idx1: idx1,
          idx2: idx2
        ))
        continue
    
    # Determine group type based on box types
    # Use TBRL if either is vertical box or TBRL group
    let isVertical = isVerticalItem(items, idx1) or isVerticalItem(items, idx2)
    
    # Create appropriate group type
    if isVertical:
      items.add(newTextGroupTBRL())
    else:
      items.add(newTextGroupLRTB())
    let groupIdx = items.len - 1
    addItem(items, groupIdx, idx1)
    addItem(items, groupIdx, idx2)
    
    # Remove merged objects from plane and add new group
    plane.remove(idx1, items)
    plane.remove(idx2, items)
    plane.add(groupIdx, items)
    idToIdx[items[groupIdx].uniqueId] = groupIdx
    
    # Add distances from new group to all other active items in the plane
    for otherIdx in plane.items:
      if otherIdx != groupIdx:
        let dist = boxDistance(items, groupIdx, otherIdx)
        heap.push(DistElement(
          skipIsany: false,
          dist: dist,
          id1: items[groupIdx].uniqueId,
          id2: items[otherIdx].uniqueId,
          idx1: groupIdx,
          idx2: otherIdx
        ))
  
  # Return remaining active objects in the plane
  result = @[]
  for idx in plane.items:
    result.add(idx)

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
  ## Matches Python's behavior: empty bbox OR text.isspace()
  ## Note: This has been verified! Do NOT edit this function!
  if isEmpty(items[idx].bbox):
    return true
  let text = textOf(items, idx)
  return isSpace(text)

proc buildLayout(page: PdfPage; p: LAParams): LTPage =
  # Reset the global ID counter for each page to avoid overflow on large documents
  globalIdCounter = 0
  
  var textPage = loadTextPage(page)
  defer: close(textPage)

  let count = charCount(textPage)
  let (w, h) = pageSize(page)
  let containerBBox: Rect = (0.0, 0.0, w, h)

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
    return LTPage(pageid: 0, bbox: containerBBox, textboxes: @[])

  # Group characters into lines
  let lines = groupObjects(charIdxs, items, p)
  
  # Add newlines to each line (matching Python's analyze behavior)
  for lineIdx in lines:
    items.add(newAnno("\n"))
    addItem(items, lineIdx, items.len - 1)

  # Filter empty lines
  var nonEmpty: seq[int] = @[]
  for lineIdx in lines:
    if not isEmptyText(items, lineIdx):
      nonEmpty.add(lineIdx)

  # Group lines into boxes
  var boxes = groupTextlines(nonEmpty, items, p, containerBBox)
  
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
      
      # Vertical boxes come first (key 0 vs 1)
      if isVertA and not isVertB:
        return -1
      elif not isVertA and isVertB:
        return 1
      elif isVertA:
        # Both vertical: sort by (-x1, -y0)
        if items[a].bbox.x1 > items[b].bbox.x1: return -1
        if items[a].bbox.x1 < items[b].bbox.x1: return 1
        if items[a].bbox.y0 > items[b].bbox.y0: return -1
        if items[a].bbox.y0 < items[b].bbox.y0: return 1
        return 0
      else:
        # Both horizontal: sort by (-y0, x0)
        if items[a].bbox.y0 > items[b].bbox.y0: return -1
        if items[a].bbox.y0 < items[b].bbox.y0: return 1
        if items[a].bbox.x0 < items[b].bbox.x0: return -1
        if items[a].bbox.x0 > items[b].bbox.x0: return 1
        return 0
    )
  elif boxes.len > 1:
    # Hierarchical grouping
    let groups = groupTextboxes(boxes, items, containerBBox)
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

  LTPage(pageid: 0, bbox: containerBBox, textboxes: outBoxes)

proc buildTextPageLayout*(page: PdfPage; laparams: LAParams = newLAParams()): LTPage =
  buildLayout(page, laparams)
