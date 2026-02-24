import std/[algorithm, parseutils]

proc allPagesSelection*(totalPages: int): seq[int] =
  result = newSeqOfCap[int](totalPages)
  for page in 1..totalPages:
    result.add(page)

proc parsePageAt(spec: string; idx: var int): int =
  let consumed = parseInt(spec, result, idx)
  if consumed <= 0 or result < 1:
    raise newException(ValueError, "invalid page token")
  inc(idx, consumed)

proc normalizePageSelection*(spec: string; totalPages: int): seq[int] =
  result = @[]
  if spec.len == 0:
    raise newException(ValueError, "invalid --pages selection")
  var idx = 0
  while idx < spec.len:
    let first = parsePageAt(spec, idx)
    var last = first
    if idx < spec.len and spec[idx] == '-':
      inc idx
      if idx < spec.len:
        last = parsePageAt(spec, idx)
      if first > last:
        raise newException(ValueError, "invalid --pages selection")
    for page in countup(first, last):
      # Insert while maintaining sorted order and uniqueness
      let pos = result.lowerBound(page)
      if pos >= result.len or result[pos] != page:
        result.insert(page, pos)
    if idx < spec.len and spec[idx] == ',':
      inc idx
      if idx >= spec.len:
        raise newException(ValueError, "invalid --pages selection")
    elif idx < spec.len:
      raise newException(ValueError, "invalid --pages selection")
