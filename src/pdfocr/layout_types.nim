type
  Rect* = tuple[x0, y0, x1, y1: float]

  ItemKind* = enum
    ikChar
    ikAnno
    ikTextLineHorizontal
    ikTextLineVertical
    ikTextBoxHorizontal
    ikTextBoxVertical
    ikTextGroupLRTB       # Horizontal group (left-right, top-bottom)
    ikTextGroupTBRL       # Vertical group (top-bottom, right-left)

  Item* = object
    kind*: ItemKind
    bbox*: Rect
    text*: string
    wordMargin*: float
    items*: seq[int]
    lastX1*: float
    lastY0*: float
    index*: int
    uniqueId*: int  # Unique identifier for heap ordering
