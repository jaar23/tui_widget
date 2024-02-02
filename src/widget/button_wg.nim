import illwill, base_wg, options, os, strutils

type
  ButtonState = enum
    Pressed, Unpressed

  Button = ref object of BaseWidget
    label: string = ""
    disabled: bool = false
    onEnter: Option[EnterEventProcedure]
    state: ButtonState = Unpressed


proc newButton*(w, h, px, py: int, label: string, disabled = false, bgColor = bgGreen,
                tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): Button =
  var button = Button(
    width: w,
    height: h,
    posX: px,
    posY: py,
    label: label,
    tb: tb,
    disabled: disabled
  )
  return button


proc render*(bt: var Button, standalone = false) =
  if bt.state == Pressed:
    bt.tb.drawRect(bt.width, bt.height, bt.posX, bt.posY, doubleStyle=bt.focus)
    bt.tb.write(bt.posX + 1, bt.posY + 1, bgGreen, center(bt.label, bt.width - 2), resetStyle)
  else:
    bt.tb.drawRect(bt.width, bt.height, bt.posX, bt.posY, doubleStyle=bt.focus)
    bt.tb.write(bt.posX + 1, bt.posY + 1, bgBlue, fgBlack, center(bt.label, bt.width - 2), resetStyle)

  if standalone: bt.tb.display()


# proc rerender*(bt: var Button, standalone = false) =
#   bt.tb.drawRect(bt.width, bt.height, bt.posX, bt.posY, doubleStyle=bt.focus)
#   bt.tb.write(bt.posX + 2, bt.posY + 1, bgBlue, bt.label, resetStyle)
#   if standalone: bt.tb.display()
#

method onControl*(bt: var Button) =
  bt.focus = true
  var delay = 100
  while bt.focus:
    var key = getKey()
    case key
    of Key.None: bt.render(true)
    of Key.Escape, Key.Tab: bt.focus = false
    of Key.Space, Key.Enter:
      if bt.disabled: return
      if bt.onEnter.isSome:
        let fn = bt.onEnter.get
        fn("")
        bt.state = Pressed
        bt.render()
     # bt.render(true)
    else: discard
    if bt.state == Pressed:
      delay = delay - 1
    if delay == 0: 
      bt.state = Unpressed
      delay = 100
  bt.render(true)
  sleep(20)


proc onEnter*(bt: var Button, cb: Option[EnterEventProcedure]) = 
  bt.onEnter = cb

proc show*(bt: var Button) = bt.render(true)


proc hide*(bt: var Button) = bt.render()


proc `-`*(bt: var Button) = bt.show()


proc terminalBuffer*(bt: var Button): var TerminalBuffer =
  bt.tb


