import illwill, base_wg, strformat
import tables, threading/channels

type
  GaugePercent* = range[0.0..1000.0]

  PercentileColor* = enum
    Tweenty, Fourthy, Sixty, Eighty, Hundred

  GaugeObj* = object of BaseWidget
    percent: GaugePercent
    loadedBlock*: char = ' '
    loadingBlock*: char = '|'
    percentileColor*: array[PercentileColor, ForegroundColor]
    events*: Table[string, EventFn[Gauge]]

  Gauge* = ref GaugeObj

proc newGauge*(px, py, w, h: int, id = "",
               border = true, percent: GaugePercent = 0.0,
               loadingBlock: char = ' ',
               loadedBlock: char = '|',
               bgColor: BackgroundColor = bgNone,
               fgColor: ForegroundColor = fgWhite, 
               percentileColor: array[PercentileColor, ForegroundColor] = [
                fgGreen, fgBlue, fgYellow, fgMagenta, fgRed],
               tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): Gauge =
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

  result = Gauge(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    percent: percent,
    tb: tb,
    style: style,
    loadedBlock: loadedBlock,
    loadingBlock: loadingBlock,
    percentileColor: percentileColor,
    events: initTable[string, EventFn[Gauge]]()
  )
  result.channel = newChan[WidgetBgEvent]()
  result.keepOriginalSize()


proc newGauge*(px, py: int, w, h: WidgetSize, id = "",
               border = true, percent: GaugePercent = 0.0,
               loadingBlock: char = ' ',
               loadedBlock: char = '|',
               bgColor = bgNone,
               fgColor = fgWhite, 
               percentileColor: array[PercentileColor, ForegroundColor] = [
                fgGreen, fgBlue, fgYellow, fgMagenta, fgRed],
               tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): Gauge =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newGauge(px, py, width, height, id, border,
                  percent, loadingBlock, loadedBlock, bgColor, fgColor,
                  percentileColor, tb) 


proc newGauge*(id: string): Gauge =
  var gauge = Gauge(
    id: id,
    percent: 0.0,
    percentileColor: [fgGreen, fgBlue, fgYellow, fgMagenta, fgRed],
    events: initTable[string, EventFn[Gauge]]()
  )
  gauge.channel = newChan[WidgetBgEvent]()
  return gauge


proc renderClearRow(g: Gauge): void =
  g.tb.fill(g.x1, g.posY, g.x2, g.height, " ")


method render*(g: Gauge) =
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


method wg*(g: Gauge): ref BaseWidget = g


proc set*(g: Gauge, point: float) =
  if point >= GaugePercent.high:
    g.percent = GaugePercent.high
  elif point <= 0.0:
    g.percent = 0.0
  else:
    g.percent = point
  g.render()


proc completed*(g: Gauge) =
  g.percent = 100.0
  g.render()


proc on*(g: Gauge, event: string, fn: EventFn[Gauge]) =
  g.events[event] = fn


method call*(g: Gauge, event: string, args: varargs[string]) =
  let fn = g.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(g, args)


method call*(g: GaugeObj, event: string, args: varargs[string]) =
  let fn = g.events.getOrDefault(event, nil)
  if not fn.isNil:
    # new reference will be created
    let gRef = g.asRef()
    fn(gRef, args)
    

method poll*(g: Gauge) =
  var widgetEv: WidgetBgEvent
  if g.channel.tryRecv(widgetEv):
    g.call(widgetEv.event, widgetEv.args)
    g.render()



