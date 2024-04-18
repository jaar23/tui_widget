import illwill, base_wg, strformat


type
  GaugePercent* = range[0.0..1000.0]

  PercentileColor* = enum
    Tweenty, Fourthy, Sixty, Eighty, Hundred

  Gauge* = object of BaseWidget
    percent: GaugePercent
    loadedBlock: char
    loadingBlock: char
    percentileColor: array[PercentileColor, ForegroundColor]


proc newGauge*(px, py, w, h: int,
               tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py),
               border = true, percent: GaugePercent = 0.0,
               fgColor: ForegroundColor = fgWhite, 
               bgColor: BackgroundColor = bgNone,
               loadingBlock: char = ' ',
               loadedBlock: char = '|',
               percentileColor: array[PercentileColor, ForegroundColor] = [
                fgGreen, fgBlue, fgYellow, fgMagenta, fgRed
               ]): ref Gauge =
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

  result = (ref Gauge)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    percent: percent,
    tb: tb,
    style: style,
    loadedBlock: loadedBlock,
    loadingBlock: loadingBlock,
    percentileColor: percentileColor
  )


proc renderClearRow(g: ref Gauge): void =
  g.tb.fill(g.x1, g.posY, g.x2, g.height, " ")


method render*(g: ref Gauge) =
  if not g.illwillInit: return
  g.renderClearRow()
  var fullGauge = g.x2 - 8
  var gaugeBarWidth = g.width

  if fullGauge <= 10:
    fullGauge = 10
    gaugeBarWidth = 10 + 8 + g.paddingX1
  if g.border:
    g.tb.drawRect(gaugeBarWidth, g.height, g.posX, g.posY)

  let pc = (g.percent/100) * fullGauge.toFloat()
  for i in 0 ..< fullGauge:
    var fg = g.percentileColor[Tweenty]
    if g.percent >= 21.0 and g.percent <= 40.0:
      fg = g.percentileColor[Fourthy]
    elif g.percent >= 41.0 and g.percent <= 60.0:
      fg = g.percentileColor[Sixty]
    elif g.percent >= 61.0 and g.percent <= 80.0:
      fg = g.percentileColor[Eighty]
    elif g.percent >= 81.0:
      fg = g.percentileColor[Hundred]

    if pc.toInt() >= i:
      g.tb.write(g.x1 + i, g.height - 1, g.bg(), fg, $g.loadedBlock, resetStyle)
    else:
      g.tb.write(g.x1 + i, g.height - 1, g.bg(), $g.loadingBlock, resetStyle)
  let percentage = fmt"{(pc / fullGauge.toFloat()) * 100.0:>3.2f}"
  g.tb.write(g.width - len(percentage), g.height - 1, g.bg(), percentage, resetStyle)
  g.tb.display()


method wg*(g: ref Gauge): ref BaseWidget = g


proc set*(g: ref Gauge, point: float) =
  if point >= GaugePercent.high:
    g.percent = GaugePercent.high
  elif point <= 0.0:
    g.percent = 0.0
  else:
    g.percent = point
  g.render()


proc completed*(g: ref Gauge) =
  g.percent = 100.0
  g.render()


