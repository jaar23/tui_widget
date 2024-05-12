import base_wg, illwill, strutils
import tables, threading/channels, os

type
  LabelObj* = object of BaseWidget
    text: string = ""
    align*: Alignment = Left
    events: Table[string, EventFn[Label]]

  Label* = ref LabelObj

proc newLabel*(px, py, w, h: int, id = "", text = "",
               border = false, align = Left,
               bgColor = bgNone, fgColor = fgWhite,
               tb = newTerminalBuffer(w + 2, h + py)): Label =
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
  result = Label(
    width: w,
    height: if border and ((h - py) < 2): py + 2 else: h,
    posX: px,
    posY: py,
    id: id,
    text: text,
    tb: tb,
    style: style,
    align: align,
    events: initTable[string, EventFn[Label]]()
  )
  result.channel = newChan[WidgetBgEvent]()
  result.keepOriginalSize()


proc newLabel*(px, py: int, w, h: WidgetSize, id = "", 
               text = "", border = false, align = Left,
               bgColor = bgNone, fgColor = fgWhite,
               tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): Label =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newLabel(px, py, width, height, id, text, border, align,
                  bgColor, fgColor, tb) 


proc newLabel*(id: string): Label =
  var label = Label(
    width: 0,
    height: 0,
    posX: 0,
    posY: 0,
    id: id,
    style: WidgetStyle(
      paddingX1: 0,
      paddingX2: 0,
      paddingY1: 0,
      paddingY2: 0,
      border: false,
      bgColor: bgNone,
      fgColor: fgWhite
    ),
    events: initTable[string, EventFn[Label]]()
  )
  label.channel = newChan[WidgetBgEvent]()
  return label


method call*(lb: Label, event: string, args: varargs[string]) =
  let fn = lb.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(lb, args)


method call*(lb: LabelObj, event: string, args: varargs[string]) =
  let fn = lb.events.getOrDefault(event, nil)
  if not fn.isNil:
    # new reference will be created
    let lbRef = lb.asRef()
    fn(lbRef, args)

 
method render*(lb: Label) =
  if not lb.illwillInit: return
  lb.call("prerender")
  lb.clear()
  lb.renderBorder()
  if lb.border and (lb.y2 - lb.y1) < 2:
    lb.height = lb.posY + 2
  var text: string = ""

  lb.size = max(3, lb.x2 - lb.x1)
  if lb.text.len > lb.size:
    text = lb.text[0..lb.size - 2] & ".."
  else:
    text = lb.text

  if lb.align == Right:
    text = align(text, lb.x2 - lb.x1)
  elif lb.align == Center:
    text = center(text, lb.x2 - lb.x1)
  else:
    text = alignLeft(text, lb.x2 - lb.x1)

  lb.tb.write(lb.x1, lb.y1, lb.bg, lb.fg, text, resetStyle)
  lb.tb.display()
  lb.call("postrender")


method wg*(lb: Label): ref BaseWidget = lb


proc val(lb: Label, text: string) =
  lb.text = text
  if lb.width > 0:
    lb.render()


proc `text=`*(lb: Label, text: string) =
  lb.val(text)


proc text*(lb: Label, text: string) =
  lb.val(text)


proc on*(lb: Label, event: string, fn: EventFn[Label]) =
  lb.events[event] = fn


method poll*(lb: Label) =
  var widgetEv: WidgetBgEvent
  if lb.channel.tryRecv(widgetEv):
    lb.call(widgetEv.event, widgetEv.args)
    lb.render()


