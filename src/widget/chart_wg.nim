import illwill, base_wg, os, strutils, asciigraph, std/math
import tables, threading/channels

type
  AxisObj* = object
    lowerBound: float64
    upperBound: float64
    padding: int
    title: string
    data: seq[float64]

  Axis* = ref AxisObj

  ChartObj* = object of BaseWidget
    marker: char = '*'
    axis: Axis
    events*: Table[string, EventFn[ref ChartObj]]
    keyEvents*: Table[Key, EventFn[ref ChartObj]]

  Chart* = ref ChartObj


proc newAxis*(lb: float64 = 0.0, ub: float64 = 0.0, title: string = "",
              data: seq[float64] = newSeq[float64]()): Axis =
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
  result = Axis(
    lowerBound: floor(lowerbound),
    upperBound: ceil(upperbound),
    title: title,
    data: data,
    padding: padding
  )


proc newChart*(px, py, w, h: int, id = "",
              axis: Axis = newAxis(),
              title = "", border = true,
              bgColor = bgNone,
              fgColor = fgWhite,
              tb = newTerminalBuffer(w + 2, h + py)): Chart =
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
  result = Chart(
    width: w,
    height: if h > axis.data.len() + 8: h else: axis.data.len() + 8,
    posX: px,
    posY: if py mod 2 >= 2: min(axis.data.len() * 2, consoleHeight()) else: min(py, consoleHeight()),
    id: id,
    tb: tb,
    style: style,
    axis: axis,
    title: title,
    events: initTable[string, EventFn[Chart]](),
    keyEvents: initTable[Key, EventFn[Chart]]()
  )
  result.channel = newChan[WidgetBgEvent]()
  result.keepOriginalSize()


proc newChart*(px, py: int, w, h: WidgetSize, id = "",
              axis: Axis = newAxis(),
              title = "", border = true,
              bgColor = bgNone,
              fgColor = fgWhite,
              tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): Chart =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newChart(px, py, width, height, id, axis, title, border,
                  bgColor, fgColor, tb)
 

proc renderAsciiGraph(c: Chart) =
  try:
    let plots = plot(c.axis.data,
                    width = (c.x2 - c.x1 - (c.axis.padding * 2)),
                    height = (c.y2 - c.y1),
                    offset = c.axis.padding).split("\n")
    for i, g in plots:
      c.tb.write(c.x1, c.y1 + i, g)
  except CatchableError, Defect:
    c.tb.write("cannot render graph")


method render*(c: Chart) =
  if not c.illwillInit: return
  c.clear()
  c.renderBorder()
  c.renderTitle()
  c.renderAsciiGraph()
  c.tb.display()


method wg*(c: Chart): ref BaseWidget = c


proc on*(c: Chart, event: string, fn: EventFn[Chart]) =
  c.events[event] = fn


proc on*(c: Chart, key: Key, fn: EventFn[Chart]) =
  c.keyEvents[key] = fn
    

method call*(c: Chart, event: string, args: varargs[string]) =
  let fn = c.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(c, args)


method call*(c: ChartObj, event: string, args: varargs[string]) =
  let fn = c.events.getOrDefault(event, nil)
  if not fn.isNil:
    let cRef = c.asRef()
    fn(cRef, args)
    

proc call(c: Chart, key: Key) =
  let fn = c.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(c)


method poll*(c: Chart) =
  var widgetEv: WidgetBgEvent
  if c.channel.tryRecv(widgetEv):
    c.call(widgetEv.event, widgetEv.args)
    c.render()

method onUpdate*(c: Chart, key: Key) =
  if key == Key.Tab:
    c.focus = false
    return
  elif c.keyEvents.hasKey(key):
    c.call(key)

  c.render()
  sleep(c.refreshWaitTime)


method onControl*(c: Chart) =
  c.focus = true
  while c.focus:
    var key = getKeyWithTimeout(c.refreshWaitTime)
    c.onUpdate(key)


proc val(c: Chart, axis: Axis) =
  c.axis = axis
  c.render()


proc `axis=`*(c: Chart, axis: Axis) =
  c.val(axis)


proc axis*(c: Chart, axis: Axis) =
  c.val(axis)




