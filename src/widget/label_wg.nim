import base_wg, illwill, strutils

type
  Label* = object of BaseWidget
    text: string = ""
    align: Alignment = Left


proc newLabel*(px, py, w, h: int, text: string,
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
    text: text,
    tb: tb,
    style: style,
    align: align
  )


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
