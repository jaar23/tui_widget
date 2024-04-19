import illwill, base_wg, os, strutils, asciigraph, std/math
import tables, threading/channels

type
  Axis* = object
    lowerBound: float64
    upperBound: float64
    padding: int
    title: string
    data: seq[float64]

  Chart* = object of BaseWidget
    marker: char = '*'
    axis: ref Axis
    events*: Table[string, EventFn[ref Chart]]
    keyEvents*: Table[Key, EventFn[ref Chart]]


proc newAxis*(lb: float64 = 0.0, ub: float64 = 0.0, title: string = "",
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
    data: data,
    padding: padding
  )


proc newChart*(px, py, w, h: int,
              axis: ref Axis = newAxis(),
              tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py),
              title: string = "", border: bool = true,
              fgColor: ForegroundColor = fgWhite,
              bgColor: BackgroundColor = bgNone,
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
    height: if h > axis.data.len() + 8: h else: axis.data.len() + 8,
    posX: px,
    posY: if py mod 2 >= 2: min(axis.data.len() * 2, consoleHeight()) else: min(py, consoleHeight()),
    tb: tb,
    style: style,
    marker: marker,
    axis: axis,
    title: title,
    events: initTable[string, EventFn[ref Chart]](),
    keyEvents: initTable[Key, EventFn[ref Chart]]()
  )
  result.channel = newChan[WidgetBgEvent]()


proc renderAsciiGraph(c: ref Chart) =
  try:
    let plots = plot(c.axis.data,
                    width = (c.x2 - c.x1 - (c.axis.padding * 2)),
                    height = (c.y2 - c.y1),
                    offset = c.axis.padding).split("\n")
    for i, g in plots:
      c.tb.write(c.x1, c.y1 + i, g)
  except CatchableError, Defect:
    c.tb.write("cannot render graph")


method render*(c: ref Chart) =
  if not c.illwillInit: return
  c.renderBorder()
  c.renderTitle()
  c.renderAsciiGraph()
  c.tb.display()


method wg*(c: ref Chart): ref BaseWidget = c


proc on*(dp: ref Chart, event: string, fn: EventFn[ref Chart]) =
  dp.events[event] = fn


proc on*(dp: ref Chart, key: Key, fn: EventFn[ref Chart]) =
  dp.keyEvents[key] = fn
    

method call*(dp: ref Chart, event: string, args: varargs[string]) =
  let fn = dp.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(dp, args)


method call*(dp: Chart, event: string, args: varargs[string]) =
  let fn = dp.events.getOrDefault(event, nil)
  if not fn.isNil:
    let dpRef = dp.asRef()
    fn(dpRef, args)
    

proc call(dp: ref Chart, key: Key) =
  let fn = dp.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(dp)


method poll*(c: ref Chart) =
  var widgetEv: WidgetBgEvent
  if c.channel.tryRecv(widgetEv):
    c.call(widgetEv.event, widgetEv.args)
    c.render()

method onUpdate*(c: ref Chart, key: Key) =
  if c.keyEvents.hasKey(key):
    c.call(key)

  c.render()
  sleep(c.refreshWaitTime)


method onControl*(c: ref Chart) =
  #c.focus = true     
  c.render()
  sleep(c.refreshWaitTime)


proc val(c: ref Chart, axis: ref Axis) =
  c.axis = axis
  c.render()


proc `axis=`*(c: ref Chart, axis: ref Axis) =
  c.val(axis)


proc axis*(c: ref Chart, axis: ref Axis) =
  c.val(axis)




