import illwill, os, base_wg, options, std/enumerate, strutils

type
  Axis* = object
    lowerBound: float64
    upperBound: float64
    padding: int
    title: string
    header: seq[string]
    data: seq[string]
    ratio: int

  Chart* = object of BaseWidget
    cursor: int = 0
    marker: char = '*'
    xAxis*: ref Axis
    yAxis*: ref Axis
    displayZero: bool = true
    onEnter: Option[CallbackProcedure]


proc newAxis*(lb, ub: float64 = 0.0, title: string = "", 
              header, data: seq[string] = newSeq[string]()): ref Axis =
  var padding = 0
  for i in header:
    if len($i) > padding: 
      padding = len($i)
  result = (ref Axis)(
    lowerBound: lb,
    upperBound: ub,
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
    height: h,
    posX: px,
    posY: py,
    tb: tb,
    style: style,
    marker: marker,
    xAxis: xAxis,
    yAxis: yAxis
  )


proc renderXAxis(c: ref Chart) =
  if c.xAxis.header.len == 0:
    return
  let xspaces = c.x2 - c.x1
  let header = if c.xAxis.header.len > xspaces: newSeq[string]() else: c.xAxis.header
  var start = c.x1 + c.yAxis.padding + 1
  for i, x in enumerate(header):
    c.tb.write(start + i, c.y2, x)
    start += len($x)
  

proc renderYAxis(c: ref Chart) =
  if c.yAxis.header.len == 0:
    return
  let yspaces = c.y2 - c.y1
  let header = if c.yAxis.header.len > yspaces: newSeq[string]() else: c.yAxis.header
  var start = c.y2 - 1
  for i, y in enumerate(header):
    c.tb.write(c.x1, start - 1, align(y, c.xAxis.padding))
    dec start
  return


proc calcXPosition(c: ref Chart) =
  let displayX = c.x2 - c.xAxis.padding - 1
  let displayY = c.y2 - c.yAxis.padding - 1
  #echo $displayX, ":", displayY


proc renderData(c: ref Chart) =
  if c.xAxis.data.len != c.yAxis.data.len:
    c.tb.write(c.x1 + 2, c.y2 - 2, "x and y is not align, ensure the both have equaivalent length of data")
  #for i, x in enumerate(c.xAxis.data):
    #c.tb.write()


method render*(c: ref Chart) =
  let rightPadd = c.x2 - len(c.xAxis.title)
  inc c.cursor
  c.renderBorder()
  c.renderTitle()
  # 横
  c.tb.drawHorizLine(c.x1, c.x2, c.y2 - 1)
  c.renderXAxis()
  # 竖
  c.tb.drawVertLine(c.x1 + c.xAxis.padding, c.y1, c.y2)
  c.renderYAxis()
  c.tb.write(rightPadd, c.y2, c.xAxis.title)
  c.tb.write(c.x1, c.y1, c.yAxis.title)
  if c.displayZero: c.tb.write(c.x1, c.y2, align("0", c.xAxis.padding))
  c.tb.display()
  c.calcXPosition()


method wg*(c: ref Chart): ref BaseWidget = c


method onControl*(c: ref Chart) =
  c.focus = true
  c.render()
  sleep(20)


method onControl*(c: ref Chart, cb: Option[CallbackProcedure]) =
  c.onEnter = cb
