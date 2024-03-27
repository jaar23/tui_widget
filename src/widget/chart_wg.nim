import illwill, os, base_wg, options, std/enumerate, strutils, std/math, asciigraph
import ../common/board


type
  Axis* = object
    lowerBound: float64
    upperBound: float64
    padding: int
    title: string
    header: seq[string]
    data: seq[float64]
    ratio: int

  Chart* = object of BaseWidget
    cursor: int = 0
    marker: char = '*'
    xAxis*: ref Axis
    yAxis*: ref Axis
    displayZero: bool = true
    board*: ref Board
    onEnter: Option[CallbackProcedure]


proc newAxis*(lb, ub: float64 = 0.0, title: string = "",
              header: seq[string] = newSeq[string](),
              data: seq[float64] = newSeq[float64]()): ref Axis =
  var padding = 0
  var lowerbound = if data.len() > 0: data[0] else: 0.0
  var upperbound = 0.0
  for d in data:
    if lowerbound > d:
      lowerbound = d
    if upperbound < d:
      upperbound = d
    if len($d) > padding:
      padding = len($d)
  result = (ref Axis)(
    lowerBound: floor(lowerbound),
    upperBound: ceil(upperbound),
    title: title,
    header: header,
    data: data,
    padding: padding
  )


proc newChart*(px, py, w, h: int,
              xAxis, yAxis: ref Axis = newAxis(),
              tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py),
              title: string = "", border: bool = true,
              fgColor: ForegroundColor = fgWhite,
              bgColor: BackgroundColor = bgNone,
              displayZero: bool = true,
              marker: char = '*'): ref Chart =
  let padding = if border: 1 else: 0
  let style = WidgetStyle(
    paddingX1: padding,
    paddingX2: padding,
    paddingY1: padding,
    paddingY2: padding,
    border: border,
    fgColor: fgColor,
    bgColor: bgColor
  )
  result = (ref Chart)(
    width: w,
    height: if h > yAxis.data.len() + 8: h else: yAxis.data.len() + 8,
    posX: px,
    posY: if py mod 2 >= 2: min(yAxis.data.len() * 2, consoleHeight()) else: min(py, consoleHeight()),
    tb: tb,
    style: style,
    marker: marker,
    xAxis: xAxis,
    yAxis: yAxis,
    title: title
  )
  var board = newBoard(
    xAxis.header.len(),
    result.y2,
    xAxis.header, yAxis.data
  )
  result.board = board


proc renderXAxis(c: ref Chart) =
  if c.xAxis.header.len == 0:
    return
  var start = c.x1 + c.yAxis.padding + 1
  let (gap, rem) = divmod(c.x2 - c.x1 - c.xAxis.padding, c.xAxis.header.len())
  let size = max(gap, 1)
  for i, x in enumerate(c.xAxis.header):
    c.tb.write(start + 1, c.y2, x)
    start += size


proc renderYAxis(c: ref Chart) =
  if c.yAxis.data.len == 0:
    return
  let yspaces = c.y2 - c.y1
  let between = c.yAxis.upperBound - c.yAxis.lowerBound
  var header = newSeq[string]()
  let (gap, rem) = divmod(ceil(between).toInt(), c.y2 - c.y1 - c.yAxis.padding)
  for i in c.yAxis.lowerBound.toInt() .. c.yAxis.upperBound.toInt():
    header.add($(i.toFloat() + gap.toFloat()))
  let size = max(gap, 1)
  # start drawing from bottom
  # minus 1 due to vertical line draw for chart
  var start = c.y2 - 1
  for i, y in enumerate(header):
    c.tb.write(c.x1, start - size, align(y, max(c.yAxis.padding, 0)))
    start -= size


proc renderData(c: ref Chart) =
  if c.xAxis.header.len != c.yAxis.data.len:
    c.tb.write(c.x1 + 2, c.y2 - 2, "x and y is not align, ensure the both have equaivalent length of data")
  let (gap, rem) = divmod(c.x2 - c.x1 - c.xAxis.padding, c.xAxis.header.len())
  let size = max(gap - 1, 1)
  # minus 1 due to chart's vertical line
  var xstart = c.x1 + 1 + c.yAxis.padding
  # start drawing from bottom
  # minus 2 due to chart's horizontal line and x axis
  var ystart = c.y2 - 2
  for i, x in enumerate(c.xAxis.header):
    let pos = c.board[x, c.yAxis.data[i]]
    c.tb.write(xstart + pos.x + 1, ystart - pos.y, $c.marker)
    xstart += size


proc renderAsciiGraph(c: ref Chart) =
  try:
    let plots = plot(c.yAxis.data,
                    width = (c.x2 - c.x1 - (c.yAxis.padding * 2)),
                    height = (c.y2 - c.y1),
                    offset = c.yAxis.padding).split("\n")
    for i, g in plots:
      c.tb.write(c.x1, c.y1 + i, g)
  except CatchableError, Defect:
    c.tb.write("cannot render graph")


method render*(c: ref Chart) =
  # let rightPadd = c.x2 - len(c.xAxis.title)
  c.renderBorder()
  c.renderTitle()
  # 横
  # c.tb.drawHorizLine(c.x1, c.x2, c.y2 - 1)
  # c.renderXAxis()
  # 竖
  # c.tb.drawVertLine(c.x1 + c.yAxis.padding, c.y1, c.y2)
  # c.renderYAxis()
  # c.tb.write(rightPadd, c.y2 - 1, c.xAxis.title)
  # c.tb.write(c.x1, c.y1, c.yAxis.title)
  if c.displayZero: c.tb.write(c.x1, c.y2, align("0", c.xAxis.padding))
  #c.renderData()
  c.renderAsciiGraph()
  c.tb.display()


method wg*(c: ref Chart): ref BaseWidget = c


method onControl*(c: ref Chart) =
  c.focus = true
  c.render()
  sleep(20)


method onControl*(c: ref Chart, cb: Option[CallbackProcedure]) =
  c.onEnter = cb
