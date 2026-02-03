proc normalizePageRange*(totalPages: int; startPage: int = 1; endPage: int = 0): Slice[int] =
  if totalPages <= 0:
    return 0 .. -1

  var start = startPage
  var finish = endPage
  if finish == 0:
    finish = startPage
  elif finish == -1:
    finish = totalPages

  if start > finish:
    swap(start, finish)

  start = max(1, start)
  finish = min(totalPages, finish)

  start .. finish
