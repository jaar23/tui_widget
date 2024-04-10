import illwill, base_wg, options, os, strutils

type
  ButtonState = enum
    Pressed, Unpressed

  Button* = object of BaseWidget
    label: string = ""
    disabled: bool = false
    onEnter: Option[EnterEventProcedure]
    state: ButtonState = Unpressed


proc newButton*(px, py, w, h: int, label: string, 
                disabled = false, bgColor = bgGreen, fgColor = fgWhite,
                tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): ref Button =
  let style = WidgetStyle(
    paddingX1: 1,
    paddingX2: 1,
    paddingY1: 1,
    paddingY2: 1,
    border: true,
    fgColor: fgColor,
    bgColor: bgColor
  )
  result = (ref Button)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    label: label,
    tb: tb,
    disabled: disabled,
    style: style
  )


method render*(bt: ref Button) =
  if not bt.illwillInit: return
  if bt.state == Pressed:
    bt.renderBorder()
    bt.tb.write(bt.x1, bt.y1, bt.bg, center(bt.label, bt.width - 2), resetStyle)
  else:
    bt.renderBorder()
    bt.tb.write(bt.x1, bt.y1, bgBlue, fgBlack, 
                center(bt.label, bt.width - 2), resetStyle)
  bt.tb.display()


method onControl*(bt: ref Button) =
  bt.focus = true
  var delay = 100
  while bt.focus:
    var key = getKeyWithTimeout(bt.refreshWaitTime)
    case key
    of Key.None: bt.render()
    of Key.Escape, Key.Tab: bt.focus = false
    of Key.Space, Key.Enter:
      if bt.disabled: return
      if bt.onEnter.isSome:
        let fn = bt.onEnter.get
        fn("")
        bt.state = Pressed
        bt.render()
    else: discard
    if bt.state == Pressed:
      delay = delay - 1
    if delay == 0:
      bt.state = Unpressed
      delay = 100
  bt.render()
  sleep(bt.refreshWaitTime)


method wg*(bt: ref Button): ref BaseWidget = bt


proc onEnter*(bt: ref Button, cb: EnterEventProcedure) =
  bt.onEnter = some(cb)


proc `onEnter=`*(bt: ref Button, cb: EnterEventProcedure) =
  bt.onEnter = some(cb)

