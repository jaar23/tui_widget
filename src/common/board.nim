type
  Coordinate* = tuple[x, y: int]
  Columns = seq[Coordinate]
  Rows = seq[Columns]
  Board = object 
    rows: Rows


proc newBoard*(c, r: int, reverse: bool = false): ref Board =
  var rows = newSeq[Columns]()
  if not reverse:
    for y in 0..<r:
      var col = newSeq[Coordinate]()
      for x in 0..<c:
        var coord = (x: y, y: x)
        col.add(coord)
      rows.add(col)
  else:
    for y in countdown(r - 1, 0):
      var col = newSeq[Coordinate]()
      #for x in countdown(c - 1, 0):
      for x in 0..<c:
        var coord = (x: x, y: y)
        col.add(coord)
      rows.add(col)
  result = (ref Board)(
    rows: rows
  )


proc `[]`*(b: ref Board, r, c: int, reverse: bool = false): Coordinate =
  if reverse:
    let row = max(-1 * (r - (b.rows.len - 1)), 0)
    b.rows[row][c]
  else:
    b.rows[r][c]


proc print*(b: ref Board): string = 
  for row in b.rows:
    for c in row:
      result &= "(" & $c.x & "," & $c.y & ") "
    result &= "\n"


proc size*(b: ref Board): (int, int) =
  result = (b.rows[0].len, b.rows.len)
