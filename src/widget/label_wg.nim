import base_wg, illwill, strutils
import tables, threading/channels

type
  LabelObj* = object of BaseWidget
    text: string = ""
    align*: Alignment = Left
    textOverlay*: bool = false
      ## When true, render() skips the tb.write text line; a postDisplay
      ## hook is expected to overlay the text via stdout. Used for
      ## CJK / wide-glyph correctness. Pair with `enableTextOverlay()`
      ## to get a default overlay closure.
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
    height: h,
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
  if lb.events.hasKey(event):
    let fn = lb.events[event]
    fn(lb, args)


method call*(lb: LabelObj, event: string, args: varargs[string]) =
  if lb.events.hasKey(event):
    let fn = lb.events[event]
    # new reference will be created
    let lbRef = lb.asRef()
    fn(lbRef, args)

 
method render*(lb: Label) =
  if not lb.illwillInit: return
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

  # When textOverlay is set, leave the cleared cells alone; a postDisplay
  # hook will write the text via stdout so wide glyphs render correctly.
  if not lb.textOverlay:
    lb.tb.write(lb.x1, lb.y1, lb.bg, lb.fg, text, resetStyle)
  if not lb.suppressDisplay: lb.tb.display()


proc enableTextOverlay*(lb: Label) =
  ## Opt the label into wide-glyph-correct rendering. Sets `textOverlay`
  ## and wires a `postDisplay` closure that emits the (alignment-padded
  ## and visually-clipped) text directly to stdout. The terminal handles
  ## CJK/emoji width natively so nothing in our code tracks per-cell
  ## visual position within the text.
  lb.textOverlay = true
  lb.postDisplay = proc(wg: ref BaseWidget) =
    let lb = Label(wg)
    if not lb.illwillInit or not lb.textOverlay: return
    let w = max(1, lb.x2 - lb.x1)
    let raw = lb.text
    let body =
      if visualWidth(raw) > w:
        clipToVisualWidth(raw, max(1, w - 2)) & ".."
      else:
        raw
    let used = visualWidth(body)
    let pad  = max(0, w - used)
    var line = ""
    case lb.align
    of Right:
      line = " ".repeat(pad) & body
    of Center:
      let l = pad div 2
      let r = pad - l
      line = " ".repeat(l) & body & " ".repeat(r)
    else:
      line = body & " ".repeat(pad)
    # x1/y1 are 0-indexed TB cells; terminal cursor positioning is 1-indexed.
    stdout.write("\e[", lb.y1 + 1, ";", lb.x1 + 1, "f", line)


method wg*(lb: Label): ref BaseWidget = lb


proc val(lb: Label, text: string) =
  # Skip the render when text hasn't changed. Background threads (e.g. a
  # spinner notifying status labels every 150ms) hit this setter
  # repeatedly with the SAME value; each call would otherwise trigger a
  # tb.display() flush, and the flush re-emits every cell whose
  # forceWrite flag is set — which is every horizontal box-char in any
  # widget border (see illwill.nim:1535). The visible result is a
  # constant border repaint storm whose source is invisible because
  # nothing in the label itself appears to change. This guard cuts the
  # storm at its root.
  if lb.text == text: return
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
    # NOTE: do NOT call lb.render() here unconditionally. The handler is
    # already responsible for updating state (and `text=` re-renders when
    # the value actually changed). An unconditional render here calls
    # tb.display() on every channel event, which re-emits every forceWrite
    # cell in the buffer — the entire app's borders — even when nothing
    # on this label changed. With a 150ms spinner tick pumping channel
    # events, that's a constant border-repaint storm on idle.


