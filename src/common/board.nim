import std/math

# Board will produce the coordinate of the chart
# for a 10 x 10 chart board
# (0,0) (1,0) (2,0) (3,0) (4,0) (5,0) (6,0) (7,0) (8,0) (9,0)
# (0,1) (1,1) (2,1) (3,1) (4,1) (5,1) (6,1) (7,1) (8,1) (9,1)
# (0,2) (1,2) (2,2) (3,2) (4,2) (5,2) (6,2) (7,2) (8,2) (9,2)
# (0,3) (1,3) (2,3) (3,3) (4,3) (5,3) (6,3) (7,3) (8,3) (9,3)
# (0,4) (1,4) (2,4) (3,4) (4,4) (5,4) (6,4) (7,4) (8,4) (9,4)
# (0,5) (1,5) (2,5) (3,5) (4,5) (5,5) (6,5) (7,5) (8,5) (9,5)
# (0,6) (1,6) (2,6) (3,6) (4,6) (5,6) (6,6) (7,6) (8,6) (9,6)
# (0,7) (1,7) (2,7) (3,7) (4,7) (5,7) (6,7) (7,7) (8,7) (9,7)
# (0,8) (1,8) (2,8) (3,8) (4,8) (5,8) (6,8) (7,8) (8,8) (9,8)
# (0,9) (1,9) (2,9) (3,9) (4,9) (5,9) (6,9) (7,9) (8,9) (9,9)
# when requestiong to plot at position (0, 1), it should return (1, 9)
# then, chart only need to add the x and y coordinate
# c.x1 + 1, c.y1 + 9, then it will be plot at (1, 9)

type
  Coordinate* = tuple[x, y: int]
  Column = object
    coordinate: Coordinate
    min: float64
    max: float64
    header: string
  Columns = seq[Column]
  Rows = seq[Columns]
  Board* = object 
    rows: Rows


proc newBoard*(c, r: int, xaxis: seq[string], yaxis: seq[float64], reverse: bool = false): ref Board =
  if c != xaxis.len():
    raise newException(ValueError, "column size should be equal to x-axis")
  var rows = newSeq[Columns]()
  # expecting yaxis data is always align from highest to lowest numer
  # let maxY = yaxis[yaxis.len() - 1]
  # find out the size in between each level
  # let size = maxY / r.toFloat()
  # -------------------------------
  # default to 1 as of now, for allowing y axis to have more data tick.
  let size = 1.toFloat()
  if not reverse:
    var min = if yaxis.len() > 0: yaxis[0] else: 0.0
    var max = 0.0
    for y in yaxis:
      if min > y:
        min = y
      if max < y:
        max = y
    for y in 0..<r:
      var col = newSeq[Column]()
      #min = max
      max = min + size
      for x in 0..<c:
        var column = Column(
          coordinate: (x: x, y: y),
          min: min,
          max: max,
          header: xaxis[x]
        )
        col.add(column)
      min = max
      rows.add(col)
  else:
    # reverse is not using, remove soon..
    var min = 0.0
    var max = 0.0
    for y in countdown(r - 1, 0):
      var col = newSeq[Column]()
      #let (gap, rem) = divmod(r, yaxis.len())
      min = y.toFloat()
      max = min + size
      #for x in countdown(c - 1, 0):
      for x in 0..<c:
        var column = Column(
          coordinate: (x: x, y: y),
          min: min,
          max: max,
          header: xaxis[x]
        )
        col.add(column)
      rows.add(col)
  result = (ref Board)(
    rows: rows
  )


proc `[]`*(b: ref Board, r: string, c: float64, reverse: bool = true): Coordinate =
  for row in b.rows:
    for col in row:
      if (col.min >= c and c <= col.max) and r == col.header:
        return col.coordinate
      

proc print*(b: ref Board): string = 
  for row in b.rows:
    for c in row:
      result &= "(" & $c.coordinate.x & "," & $c.coordinate.y & "|" & $c.min & ":" & $c.max & ")"
    result &= "\n"


proc size*(b: ref Board): (int, int) =
  result = (b.rows[0].len, b.rows.len)
