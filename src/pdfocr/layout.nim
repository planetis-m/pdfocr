import std/[math, strformat, strutils, tables, sets, sequtils, algorithm, heapqueue]

# Lightweight port of pdfminer.layout, adapted for Pdfium text extraction.

const
  INF* = 1.0e30

type
  Point* = tuple[x, y: float]
  Rect* = tuple[x0, y0, x1, y1: float]
  Matrix* = array[6, float]

proc bbox2str*(bbox: Rect): string =
  &"({bbox.x0:.3f}, {bbox.y0:.3f}, {bbox.x1:.3f}, {bbox.y1:.3f})"

proc matrix2str*(m: Matrix): string =
  &"[{m[0]:.3f}, {m[1]:.3f}, {m[2]:.3f}, {m[3]:.3f}, {m[4]:.3f}, {m[5]:.3f}]"

proc applyMatrixPoint*(m: Matrix; p: Point): Point =
  (x: m[0] * p.x + m[2] * p.y + m[4], y: m[1] * p.x + m[3] * p.y + m[5])

proc applyMatrixRect*(m: Matrix; r: Rect): Rect =
  let p0 = applyMatrixPoint(m, (r.x0, r.y0))
  let p1 = applyMatrixPoint(m, (r.x1, r.y0))
  let p2 = applyMatrixPoint(m, (r.x0, r.y1))
  let p3 = applyMatrixPoint(m, (r.x1, r.y1))
  let xs = @[p0.x, p1.x, p2.x, p3.x]
  let ys = @[p0.y, p1.y, p2.y, p3.y]
  (x0: xs.min, y0: ys.min, x1: xs.max, y1: ys.max)

proc getBound*(rects: seq[Rect]): Rect =
  if rects.len == 0:
    return (0.0, 0.0, 0.0, 0.0)
  var x0 = rects[0].x0
  var y0 = rects[0].y0
  var x1 = rects[0].x1
  var y1 = rects[0].y1
  for r in rects[1..^1]:
    x0 = min(x0, r.x0)
    y0 = min(y0, r.y0)
    x1 = max(x1, r.x1)
    y1 = max(y1, r.y1)
  (x0, y0, x1, y1)

proc fsplit*[T](items: seq[T]; pred: proc(x: T): bool {.closure.}): tuple[match, rest: seq[T]] =
  var a: seq[T] = @[]
  var b: seq[T] = @[]
  for it in items:
    if pred(it):
      a.add(it)
    else:
      b.add(it)
  (a, b)

proc uniq*[T](items: seq[T]): seq[T] =
  var seen = initHashSet[uint]()
  result = @[]
  for it in items:
    let key = cast[uint](it)
    if key notin seen:
      seen.incl(key)
      result.add(it)

# --- Layout params ---

type
  LAParams* = ref object
    lineOverlap*: float
    charMargin*: float
    lineMargin*: float
    wordMargin*: float
    boxesFlow*: float
    boxesFlowEnabled*: bool
    detectVertical*: bool
    allTexts*: bool

proc newLAParams*(
  lineOverlap: float = 0.5,
  charMargin: float = 2.0,
  lineMargin: float = 0.5,
  wordMargin: float = 0.1,
  boxesFlow: float = 0.5,
  boxesFlowEnabled: bool = true,
  detectVertical: bool = false,
  allTexts: bool = false
): LAParams =
  if boxesFlowEnabled and (boxesFlow < -1.0 or boxesFlow > 1.0):
    raise newException(ValueError, "LAParams boxesFlow must be between -1 and 1")
  LAParams(
    lineOverlap: lineOverlap,
    charMargin: charMargin,
    lineMargin: lineMargin,
    wordMargin: wordMargin,
    boxesFlow: boxesFlow,
    boxesFlowEnabled: boxesFlowEnabled,
    detectVertical: detectVertical,
    allTexts: allTexts
  )

# --- Base layout types ---

type
  LTItem* = ref object of RootObj
  LTComponent* = ref object of LTItem
    x0*, y0*, x1*, y1*: float
    width*, height*: float
    bbox*: Rect

method analyze*(self: LTItem; laparams: LAParams) {.base.} =
  discard

method getText*(self: LTItem): string {.base.} =
  ""

proc setBBox*(self: LTComponent; bbox: Rect) =
  self.x0 = bbox.x0
  self.y0 = bbox.y0
  self.x1 = bbox.x1
  self.y1 = bbox.y1
  self.width = self.x1 - self.x0
  self.height = self.y1 - self.y0
  self.bbox = bbox

proc newLTComponent*(bbox: Rect): LTComponent =
  LTComponent(bbox: bbox, x0: bbox.x0, y0: bbox.y0, x1: bbox.x1, y1: bbox.y1,
              width: bbox.x1 - bbox.x0, height: bbox.y1 - bbox.y0)

proc isEmpty*(self: LTComponent): bool =
  self.width <= 0 or self.height <= 0

proc isHoverlap*(self, obj: LTComponent): bool =
  obj.x0 <= self.x1 and self.x0 <= obj.x1

proc hDistance*(self, obj: LTComponent): float =
  if isHoverlap(self, obj):
    0.0
  else:
    min(abs(self.x0 - obj.x1), abs(self.x1 - obj.x0))

proc hOverlap*(self, obj: LTComponent): float =
  if isHoverlap(self, obj):
    min(abs(self.x0 - obj.x1), abs(self.x1 - obj.x0))
  else:
    0.0

proc isVoverlap*(self, obj: LTComponent): bool =
  obj.y0 <= self.y1 and self.y0 <= obj.y1

proc vDistance*(self, obj: LTComponent): float =
  if isVoverlap(self, obj):
    0.0
  else:
    min(abs(self.y0 - obj.y1), abs(self.y1 - obj.y0))

proc vOverlap*(self, obj: LTComponent): float =
  if isVoverlap(self, obj):
    min(abs(self.y0 - obj.y1), abs(self.y1 - obj.y0))
  else:
    0.0

# --- Simple spatial index ---

type
  Plane*[T] = ref object
    bbox: Rect
    items: seq[T]

proc newPlane*[T](bbox: Rect): Plane[T] =
  Plane[T](bbox: bbox, items: @[])

proc add*[T](plane: Plane[T]; obj: T) =
  plane.items.add(obj)

proc remove*[T](plane: Plane[T]; obj: T) =
  for i in 0 ..< plane.items.len:
    if plane.items[i] == obj:
      plane.items.delete(i)
      break

proc extend*[T](plane: Plane[T]; objs: seq[T]) =
  for obj in objs:
    plane.items.add(obj)

iterator items*[T](plane: Plane[T]): T =
  for obj in plane.items:
    yield obj

proc find*[T](plane: Plane[T]; bbox: Rect): seq[T] =
  result = @[]
  for obj in plane.items:
    if obj of LTComponent:
      let c = LTComponent(obj)
      if not (c.x1 < bbox.x0 or c.x0 > bbox.x1 or c.y1 < bbox.y0 or c.y0 > bbox.y1):
        result.add(obj)
    else:
      result.add(obj)

# --- Text ---

type
  LTAnno* = ref object of LTItem
    text*: string

method getText*(self: LTAnno): string =
  self.text

method analyze*(self: LTAnno; laparams: LAParams) =
  discard

proc newLTAnno*(text: string): LTAnno =
  LTAnno(text: text)

# --- Characters ---

type
  LTChar* = ref object of LTComponent
    text*: string
    size*: float

proc newLTChar*(bbox: Rect; text: string): LTChar =
  let width = bbox.x1 - bbox.x0
  let height = bbox.y1 - bbox.y0
  LTChar(
    bbox: bbox,
    x0: bbox.x0, y0: bbox.y0, x1: bbox.x1, y1: bbox.y1,
    width: width, height: height,
    text: text,
    size: max(width, height)
  )

method getText*(self: LTChar): string =
  self.text

# --- Containers ---

type
  LTContainer* = ref object of LTComponent
    items*: seq[LTItem]

proc newLTContainer*(bbox: Rect = (0.0, 0.0, 0.0, 0.0)): LTContainer =
  LTContainer(
    bbox: bbox,
    x0: bbox.x0, y0: bbox.y0, x1: bbox.x1, y1: bbox.y1,
    width: bbox.x1 - bbox.x0, height: bbox.y1 - bbox.y0,
    items: @[]
  )

proc add*(self: LTContainer; obj: LTItem) =
  self.items.add(obj)

iterator items*(self: LTContainer): LTItem =
  for obj in self.items:
    yield obj

# Container that grows bbox as items are added

type
  LTExpandableContainer* = ref object of LTContainer

proc newLTExpandableContainer*(): LTExpandableContainer =
  LTExpandableContainer(items: @[], bbox: (INF, INF, -INF, -INF), x0: INF, y0: INF, x1: -INF, y1: -INF,
                        width: -INF, height: -INF)

proc add*(self: LTExpandableContainer; obj: LTItem) =
  if obj of LTComponent:
    let c = LTComponent(obj)
    self.x0 = min(self.x0, c.x0)
    self.y0 = min(self.y0, c.y0)
    self.x1 = max(self.x1, c.x1)
    self.y1 = max(self.y1, c.y1)
    self.width = self.x1 - self.x0
    self.height = self.y1 - self.y0
    self.bbox = (self.x0, self.y0, self.x1, self.y1)
  self.items.add(obj)

# Text containers

type
  LTTextContainer* = ref object of LTExpandableContainer

method getText*(self: LTTextContainer): string =
  var textOut = ""
  for obj in self.items:
    textOut.add(obj.getText())
  textOut

# --- Text line ---

type
  LTTextLine* = ref object of LTTextContainer
    wordMargin*: float

method analyze*(self: LTTextLine; laparams: LAParams) =
  for obj in self.items:
    obj.analyze(laparams)
  LTExpandableContainer(self).add(newLTAnno("\n"))

proc isTextLineEmpty*(self: LTTextLine): bool =
  self.isEmpty() or self.getText().strip.len == 0

# Horizontal text line

type
  LTTextLineHorizontal* = ref object of LTTextLine
    lastX1: float

proc newLTTextLineHorizontal*(wordMargin: float): LTTextLineHorizontal =
  result = LTTextLineHorizontal(wordMargin: wordMargin, lastX1: INF, items: @[],
                                bbox: (INF, INF, -INF, -INF), x0: INF, y0: INF, x1: -INF, y1: -INF,
                                width: -INF, height: -INF)

proc add*(self: LTTextLineHorizontal; obj: LTComponent) =
  if obj of LTChar and self.wordMargin != 0:
    let margin = self.wordMargin * max(obj.width, obj.height)
    if self.lastX1 < obj.x0 - margin:
      LTExpandableContainer(self).add(newLTAnno(" "))
  self.lastX1 = obj.x1
  LTExpandableContainer(self).add(obj)

proc findNeighbors*(self: LTTextLineHorizontal; plane: Plane[LTTextLine]; ratio: float): seq[LTTextLine] =
  let d = ratio * self.height
  let candidates = plane.find((self.x0, self.y0 - d, self.x1, self.y1 + d))
  result = @[]
  for obj in candidates:
    if obj of LTTextLineHorizontal:
      let line = LTTextLineHorizontal(obj)
      if abs(line.height - self.height) <= d:
        let leftAligned = abs(line.x0 - self.x0) <= d
        let rightAligned = abs(line.x1 - self.x1) <= d
        let centerAligned = abs(((line.x0 + line.x1) / 2) - ((self.x0 + self.x1) / 2)) <= d
        if leftAligned or rightAligned or centerAligned:
          result.add(line)

# Vertical text line

type
  LTTextLineVertical* = ref object of LTTextLine
    lastY0: float

proc newLTTextLineVertical*(wordMargin: float): LTTextLineVertical =
  result = LTTextLineVertical(wordMargin: wordMargin, lastY0: -INF, items: @[],
                              bbox: (INF, INF, -INF, -INF), x0: INF, y0: INF, x1: -INF, y1: -INF,
                              width: -INF, height: -INF)

proc add*(self: LTTextLineVertical; obj: LTComponent) =
  if obj of LTChar and self.wordMargin != 0:
    let margin = self.wordMargin * max(obj.width, obj.height)
    if obj.y1 + margin < self.lastY0:
      LTExpandableContainer(self).add(newLTAnno(" "))
  self.lastY0 = obj.y0
  LTExpandableContainer(self).add(obj)

proc findNeighbors*(self: LTTextLineVertical; plane: Plane[LTTextLine]; ratio: float): seq[LTTextLine] =
  let d = ratio * self.width
  let candidates = plane.find((self.x0 - d, self.y0, self.x1 + d, self.y1))
  result = @[]
  for obj in candidates:
    if obj of LTTextLineVertical:
      let line = LTTextLineVertical(obj)
      if abs(line.width - self.width) <= d:
        let upperAligned = abs(line.y1 - self.y1) <= d
        let lowerAligned = abs(line.y0 - self.y0) <= d
        let centerAligned = abs(((line.y0 + line.y1) / 2) - ((self.y0 + self.y1) / 2)) <= d
        if upperAligned or lowerAligned or centerAligned:
          result.add(line)

# --- Text boxes ---

type
  LTTextBox* = ref object of LTTextContainer
    index*: int

proc newLTTextBox*(): LTTextBox =
  LTTextBox(items: @[], bbox: (INF, INF, -INF, -INF), x0: INF, y0: INF, x1: -INF, y1: -INF,
            width: -INF, height: -INF, index: -1)

method analyze*(self: LTTextBox; laparams: LAParams) =
  for obj in self.items:
    obj.analyze(laparams)

proc getWritingMode*(self: LTTextBox): string =
  "lr-tb"

# Horizontal/Vertical text boxes

type
  LTTextBoxHorizontal* = ref object of LTTextBox
  LTTextBoxVertical* = ref object of LTTextBox

proc newLTTextBoxHorizontal*(): LTTextBoxHorizontal =
  LTTextBoxHorizontal(items: @[], bbox: (INF, INF, -INF, -INF), x0: INF, y0: INF, x1: -INF, y1: -INF,
                      width: -INF, height: -INF, index: -1)

proc newLTTextBoxVertical*(): LTTextBoxVertical =
  LTTextBoxVertical(items: @[], bbox: (INF, INF, -INF, -INF), x0: INF, y0: INF, x1: -INF, y1: -INF,
                    width: -INF, height: -INF, index: -1)

proc getWritingMode*(self: LTTextBoxHorizontal): string = "lr-tb"
proc getWritingMode*(self: LTTextBoxVertical): string = "tb-rl"

# --- Text groups ---

type
  LTTextGroup* = ref object of LTTextContainer
  LTTextGroupLRTB* = ref object of LTTextGroup
  LTTextGroupTBRL* = ref object of LTTextGroup

type
  IndexAssigner* = ref object
    index*: int

proc newIndexAssigner*(startIndex: int = 0): IndexAssigner =
  IndexAssigner(index: startIndex)

proc run*(assigner: IndexAssigner; obj: LTItem) =
  if obj of LTTextBox:
    let box = LTTextBox(obj)
    box.index = assigner.index
    inc(assigner.index)
  elif obj of LTTextGroup:
    for child in LTTextGroup(obj).items:
      assigner.run(child)

proc newLTTextGroup*(items: seq[LTItem]): LTTextGroup =
  let group = LTTextGroup(items: @[], bbox: (INF, INF, -INF, -INF), x0: INF, y0: INF, x1: -INF, y1: -INF,
                          width: -INF, height: -INF)
  for obj in items:
    LTExpandableContainer(group).add(obj)
  group

proc newLTTextGroupLRTB*(items: seq[LTItem]): LTTextGroupLRTB =
  let group = LTTextGroupLRTB(items: @[], bbox: (INF, INF, -INF, -INF), x0: INF, y0: INF, x1: -INF, y1: -INF,
                              width: -INF, height: -INF)
  for obj in items:
    LTExpandableContainer(group).add(obj)
  group

proc newLTTextGroupTBRL*(items: seq[LTItem]): LTTextGroupTBRL =
  let group = LTTextGroupTBRL(items: @[], bbox: (INF, INF, -INF, -INF), x0: INF, y0: INF, x1: -INF, y1: -INF,
                              width: -INF, height: -INF)
  for obj in items:
    LTExpandableContainer(group).add(obj)
  group

method analyze*(self: LTTextGroup; laparams: LAParams) =
  for obj in self.items:
    obj.analyze(laparams)

# --- Layout container ---

type
  LTLayoutContainer* = ref object of LTContainer
    groups*: seq[LTTextGroup]

proc newLTLayoutContainer*(bbox: Rect): LTLayoutContainer =
  LTLayoutContainer(bbox: bbox, x0: bbox.x0, y0: bbox.y0, x1: bbox.x1, y1: bbox.y1,
                    width: bbox.x1 - bbox.x0, height: bbox.y1 - bbox.y0, items: @[], groups: @[])

proc groupObjects*(self: LTLayoutContainer; laparams: LAParams; objs: seq[LTComponent]): seq[LTTextLine] =
  result = @[]
  var obj0: LTComponent = nil
  var line: LTTextLine = nil
  for obj1 in objs:
    if obj0 != nil:
      let halign = obj0.isVoverlap(obj1) and
        min(obj0.height, obj1.height) * laparams.lineOverlap < obj0.vOverlap(obj1) and
        obj0.hDistance(obj1) < max(obj0.width, obj1.width) * laparams.charMargin

      let valign = laparams.detectVertical and obj0.isHoverlap(obj1) and
        min(obj0.width, obj1.width) * laparams.lineOverlap < obj0.hOverlap(obj1) and
        obj0.vDistance(obj1) < max(obj0.height, obj1.height) * laparams.charMargin

      if (halign and (line of LTTextLineHorizontal)) or (valign and (line of LTTextLineVertical)):
        if line of LTTextLineHorizontal:
          LTTextLineHorizontal(line).add(obj1)
        else:
          LTTextLineVertical(line).add(obj1)
      elif line != nil:
        result.add(line)
        line = nil
      elif valign and not halign:
        let newLine = newLTTextLineVertical(laparams.wordMargin)
        newLine.add(obj0)
        newLine.add(obj1)
        line = newLine
      elif halign and not valign:
        let newLine = newLTTextLineHorizontal(laparams.wordMargin)
        newLine.add(obj0)
        newLine.add(obj1)
        line = newLine
      else:
        let newLine = newLTTextLineHorizontal(laparams.wordMargin)
        newLine.add(obj0)
        result.add(newLine)
        line = nil
    obj0 = obj1
  if line == nil:
    let newLine = newLTTextLineHorizontal(laparams.wordMargin)
    if obj0 != nil:
      newLine.add(obj0)
    line = newLine
  result.add(line)

proc groupTextlines*(self: LTLayoutContainer; laparams: LAParams; lines: seq[LTTextLine]): seq[LTTextBox] =
  let plane = newPlane[LTTextLine](self.bbox)
  plane.extend(lines)
  var boxes = initTable[uint, LTTextBox]()

  for line in lines:
    var neighbors: seq[LTTextLine] = @[]
    if line of LTTextLineHorizontal:
      neighbors = LTTextLineHorizontal(line).findNeighbors(plane, laparams.lineMargin)
    else:
      neighbors = LTTextLineVertical(line).findNeighbors(plane, laparams.lineMargin)

    var members: seq[LTTextLine] = @[line]
    for obj1 in neighbors:
      members.add(obj1)
      let objKey = cast[uint](obj1)
      if boxes.hasKey(objKey):
        for m in boxes[objKey].items:
          if m of LTTextLine:
            members.add(LTTextLine(m))
        boxes.del(objKey)

    var box: LTTextBox
    if line of LTTextLineHorizontal:
      box = newLTTextBoxHorizontal()
    else:
      box = newLTTextBoxVertical()

    for obj in uniq(members):
      LTExpandableContainer(box).add(obj)
      boxes[cast[uint](obj)] = box

  var done = initHashSet[uint]()
  for line in lines:
    let key = cast[uint](line)
    if not boxes.hasKey(key):
      continue
    let box = boxes[key]
    let boxKey = cast[uint](box)
    if boxKey in done:
      continue
    done.incl(boxKey)
    if not box.isEmpty():
      result.add(box)

proc groupTextboxes*(self: LTLayoutContainer; laparams: LAParams; boxes: seq[LTTextBox]): seq[LTTextGroup] =
  type Element = LTItem
  let plane = newPlane[LTItem](self.bbox)

  proc dist(obj1, obj2: LTComponent): float =
    let x0 = min(obj1.x0, obj2.x0)
    let y0 = min(obj1.y0, obj2.y0)
    let x1 = max(obj1.x1, obj2.x1)
    let y1 = max(obj1.y1, obj2.y1)
    (x1 - x0) * (y1 - y0) - obj1.width * obj1.height - obj2.width * obj2.height

  proc isAny(obj1, obj2: LTComponent): bool =
    let x0 = min(obj1.x0, obj2.x0)
    let y0 = min(obj1.y0, obj2.y0)
    let x1 = max(obj1.x1, obj2.x1)
    let y1 = max(obj1.y1, obj2.y1)
    let objs = plane.find((x0, y0, x1, y1))
    for obj in objs:
      if obj != obj1 and obj != obj2:
        return true
    false

  type DistEntry = tuple[skipIsAny: bool, d: float, id1: uint, id2: uint, obj1: LTItem, obj2: LTItem]
  var dists = initHeapQueue[DistEntry]()
  for i in 0 ..< boxes.len:
    for j in i + 1 ..< boxes.len:
      let b1 = boxes[i]
      let b2 = boxes[j]
      dists.push((false, dist(b1, b2), cast[uint](b1), cast[uint](b2), LTItem(b1), LTItem(b2)))
  let boxItems = boxes.mapIt(LTItem(it))
  plane.extend(boxItems)

  var done = initHashSet[uint]()
  while dists.len > 0:
    let current = dists.pop()
    if (current.id1 notin done) and (current.id2 notin done):
      if not current.skipIsAny and isAny(LTComponent(current.obj1), LTComponent(current.obj2)):
        dists.push((true, current.d, current.id1, current.id2, current.obj1, current.obj2))
        continue
      var group: LTTextGroup
      if (current.obj1 of LTTextBoxVertical) or (current.obj1 of LTTextGroupTBRL) or
         (current.obj2 of LTTextBoxVertical) or (current.obj2 of LTTextGroupTBRL):
        group = newLTTextGroupTBRL(@[current.obj1, current.obj2])
      else:
        group = newLTTextGroupLRTB(@[current.obj1, current.obj2])
      plane.remove(current.obj1)
      plane.remove(current.obj2)
      done.incl(current.id1)
      done.incl(current.id2)
      for other in plane.items:
        if other of LTComponent:
          dists.push((false, dist(LTComponent(group), LTComponent(other)), cast[uint](group), cast[uint](other), LTItem(group), LTItem(other)))
      plane.add(group)

  result = @[]
  for obj in plane.items:
    if obj of LTTextGroup:
      result.add(LTTextGroup(obj))

method analyze*(self: LTLayoutContainer; laparams: LAParams) =
  var textobjs: seq[LTComponent] = @[]
  var otherobjs: seq[LTItem] = @[]
  for obj in self.items:
    if obj of LTChar:
      textobjs.add(LTComponent(obj))
    else:
      otherobjs.add(obj)

  for obj in otherobjs:
    obj.analyze(laparams)

  if textobjs.len == 0:
    return

  let textlines = self.groupObjects(laparams, textobjs)
  let split = fsplit(textlines, proc(x: LTTextLine): bool = x.isTextLineEmpty())

  for obj in split.match:
    obj.analyze(laparams)

  let textboxes = self.groupTextlines(laparams, split.rest)

  if not laparams.boxesFlowEnabled:
    for box in textboxes:
      box.analyze(laparams)
    proc getKey(box: LTTextBox): tuple[a: int, b: float, c: float] =
      if box of LTTextBoxVertical:
        (0, -box.x1, -box.y0)
      else:
        (1, -box.y0, box.x0)
    var sortedBoxes = textboxes
    sortedBoxes.sort(proc(a, b: LTTextBox): int = cmp(getKey(a), getKey(b)))
    self.groups = @[]
    for box in sortedBoxes:
      self.groups.add(LTTextGroup(newLTTextGroup(@[LTItem(box)])))
    self.items = @[]
    for box in sortedBoxes:
      self.items.add(box)
  else:
    self.groups = self.groupTextboxes(laparams, textboxes)
    let assigner = newIndexAssigner()
    for group in self.groups:
      group.analyze(laparams)
      assigner.run(group)
    var sortedBoxes = textboxes
    sortedBoxes.sort(proc(a, b: LTTextBox): int = cmp(a.index, b.index))
    self.items = @[]
    for box in sortedBoxes:
      self.items.add(box)

  for obj in otherobjs:
    self.items.add(obj)
  for obj in split.match:
    self.items.add(obj)

# --- Page ---

type
  LTPage* = ref object of LTLayoutContainer
    pageid*: int
    rotate*: int

proc newLTPage*(pageid: int; bbox: Rect; rotate: int = 0): LTPage =
  LTPage(pageid: pageid, rotate: rotate,
         bbox: bbox, x0: bbox.x0, y0: bbox.y0, x1: bbox.x1, y1: bbox.y1,
         width: bbox.x1 - bbox.x0, height: bbox.y1 - bbox.y0, items: @[], groups: @[])

# --- Pdfium adapter ---

import ./pdfium

proc buildTextPageLayout*(page: PdfPage; laparams: LAParams = newLAParams()): LTPage =
  var textPage = loadTextPage(page)
  defer: close(textPage)

  let count = charCount(textPage)
  let (w, h) = pageSize(page)
  let layout = newLTPage(0, (0.0, 0.0, w, h))

  for i in 0 ..< count:
    let (left, right, bottom, top) = getCharBox(textPage, i)
    let ch = getTextRange(textPage, i, 1)
    if ch.len == 0 or right <= left or top <= bottom:
      continue
    let bbox: Rect = (left.float, bottom.float, right.float, top.float)
    layout.add(newLTChar(bbox, ch))

  layout.analyze(laparams)
  layout
