import std/[sets, tables]
import ./layout_types

type
  Point = tuple[x, y: float]
  # Plane: A grid-based spatial index for efficient rectangular range queries
  Plane* = object
    seqOrder: seq[int]       # preserve object order (indices into items)
    objs: HashSet[int]       # active objects (indices into items)
    grid: Table[Point, seq[int]]  # grid cells mapping to object indices
    gridsize: int
    x0, y0, x1, y1: float

# ============================================================================
# Plane implementation (grid-based spatial index)
# ============================================================================

iterator gridRange(plane: Plane; bbox: Rect): Point {.inline.} =
  ## Yields grid cells that overlap with bbox
  let
    x0 = max(plane.x0, bbox.x0)
    y0 = max(plane.y0, bbox.y0)
    x1 = min(plane.x1, bbox.x1)
    y1 = min(plane.y1, bbox.y1)
  
  if x0 < x1 and y0 < y1:
    let step = plane.gridsize.float
    var gridY = y0
    while gridY < y1:
      var gridX = x0
      while gridX < x1:
        yield (gridX, gridY)
        gridX += step
      gridY += step

proc initPlane*(bbox: Rect; gridsize: int = 50): Plane {.inline.} =
  Plane(
    seqOrder: @[],
    objs: initHashSet[int](),
    grid: initTable[Point, seq[int]](),
    gridsize: gridsize,
    x0: bbox.x0,
    y0: bbox.y0,
    x1: bbox.x1,
    y1: bbox.y1
  )

proc add*(plane: var Plane; idx: int; items: openArray[Item]) {.inline.} =
  ## Add an object to the plane
  let bbox = items[idx].bbox
  for k in plane.gridRange(bbox):
    plane.grid.mgetOrPut(k, @[]).add(idx)
  plane.seqOrder.add(idx)
  plane.objs.incl(idx)

proc remove*(plane: var Plane; idx: int; items: openArray[Item]) =
  ## Remove an object from the plane
  let bbox = items[idx].bbox
  for k in plane.gridRange(bbox):
    if plane.grid.hasKey(k):
      var cell = plane.grid[k]
      let pos = cell.find(idx)
      if pos >= 0:
        cell.delete(pos)
        plane.grid[k] = cell
  plane.objs.excl(idx)

proc extend*(plane: var Plane; indices: openArray[int]; items: openArray[Item]) =
  ## Add multiple objects to the plane
  for idx in indices:
    plane.add(idx, items)

iterator findOverlaps*(plane: Plane; bbox: Rect; items: openArray[Item]): int =
  ## Find objects that overlap with the given bbox
  var done = initHashSet[int]()
  let (x0, y0, x1, y1) = (bbox.x0, bbox.y0, bbox.x1, bbox.y1)
  
  for k in plane.gridRange(bbox):
    if plane.grid.hasKey(k):
      let cell = plane.grid[k]
      for idx in cell:
        if idx notin done:
          done.incl(idx)
          if idx in plane.objs:
            let obj = items[idx].bbox
            if not (obj.x1 <= x0 or x1 <= obj.x0 or obj.y1 <= y0 or y1 <= obj.y0):
              yield idx

iterator items*(plane: Plane): int {.inline.} =
  ## Iterate over active objects in insertion order
  for idx in plane.seqOrder:
    if idx in plane.objs:
      yield idx

proc contains*(plane: Plane; idx: int): bool {.inline.} =
  idx in plane.objs

proc len*(plane: Plane): int {.inline.} =
  plane.objs.len
