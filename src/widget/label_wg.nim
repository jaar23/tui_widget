import base_wg, illwill, strutils
import tables, threading/channels

type
  Label* = object of BaseWidget
    text: string = ""
    align: Alignment = Left
    events: Table[string, EventFn[ref Label]]

proc newLabel*(px, py, w, h: int, id = "", text = "",
               border = false, align = Left,
               bgColor = bgNone, fgColor = fgWhite,
               tb = newTerminalBuffer(w + 2, h + py)): ref Label =
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
  result = (ref Label)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    text: text,
    tb: tb,
    style: style,
    align: align,
    events: initTable[string, EventFn[ref Label]]()
  )
  result.channel = newChan[WidgetBgEvent]()
  result.keepOriginalSize()


proc newLabel*(px, py: int, w, h: WidgetSize, id = "", 
               text = "", border = false, align = Left,
               bgColor = bgNone, fgColor = fgWhite,
               tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): ref Label =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newLabel(px, py, width, height, id, text, border, align,
                  bgColor, fgColor, tb) 


method render*(lb: ref Label) =
  if not lb.illwillInit: return
  if lb.border: lb.renderBorder()
  var text: string
  if lb.align == Right:
    text = align(lb.text, lb.x2 - lb.paddingX1)
  elif lb.align == Center:
    text = center(lb.text, lb.x2 - lb.paddingX1)
  else:
    text = alignLeft(lb.text, lb.x2 - lb.paddingX1)
  lb.tb.write(lb.x1, lb.y1, lb.bg, lb.fg, text, resetStyle)
  lb.tb.display()


method wg*(lb: ref Label): ref BaseWidget = lb


proc val(lb: ref Label, text: string) =
  let size = lb.x2 - lb.x1
  if text.len > size:
    lb.text = text[0..size - 2] & ".."
  else:
    lb.text = text
  lb.render()


proc `text=`*(lb: ref Label, text: string) =
  lb.val(text)


proc text*(lb: ref Label, text: string) =
  lb.val(text)


proc on*(lb: ref Label, event: string, fn: EventFn[ref Label]) =
  lb.events[event] = fn


method call*(lb: ref Label, event: string, args: varargs[string]) =
  let fn = lb.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(lb, args)


method call*(lb: Label, event: string, args: varargs[string]) =
  let fn = lb.events.getOrDefault(event, nil)
  if not fn.isNil:
    # new reference will be created
    let lbRef = lb.asRef()
    fn(lbRef, args)
    

method poll*(lb: ref Label) =
  var widgetEv: WidgetBgEvent
  if lb.channel.tryRecv(widgetEv):
    lb.call(widgetEv.event, widgetEv.args)
    lb.render()


