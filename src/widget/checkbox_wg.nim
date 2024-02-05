import illwill, base_wg, options, os

type
  Checkbox = object of BaseWidget
    label: string = ""
    value: string = ""
    visualSkip: int = 2
    title: string
    checked: bool
    onSpace: Option[SpaceEventProcedure]

proc newCheckbox*(w, h, px, py: int, title = "", label = "", 
                  value = "", checked = false,
                  tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): ref Checkbox =
  var checkbox = (ref Checkbox)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    title: title,
    label: label,
    value: value,
    tb: tb,
    checked: checked,
  )
  return checkbox


proc render*(ch: ref Checkbox, display = true) =
  if display:
    ch.tb.drawRect(ch.width, ch.height, ch.posX, ch.posY, doubleStyle=ch.focus)
    if ch.title != "":
      ch.tb.write(ch.posX + 2, ch.posY, ch.title)
    if ch.checked:
      ch.tb.fill(ch.posX + 2, ch.posY + 1, ch.posX + 2, ch.posY + 1, "[")
      ch.tb.fill(ch.posX + 3, ch.posY + 1, ch.posX + 3, ch.posY + 1, "X")
      ch.tb.fill(ch.posX + 4, ch.posY + 1, ch.posX + 4, ch.posY + 1, "]")
    else:
      ch.tb.fill(ch.posX + 2, ch.posY + 1, ch.posX + 2, ch.posY + 1, "[")
      ch.tb.fill(ch.posX + 3, ch.posY + 1, ch.posX + 3, ch.posY + 1, " ")
      ch.tb.fill(ch.posX + 4, ch.posY + 1, ch.posX + 4, ch.posY + 1, "]")
    ch.tb.write(ch.posX + 6, ch.posY + 1, resetStyle, ch.label)
    ch.tb.display()
  else:
    echo "not implement"


method onControl*(ch: ref Checkbox) =
  ch.focus = true
  while ch.focus:
    var key = getKey()
    case key
    of Key.None: ch.render(true)
    of Key.Escape, Key.Tab: ch.focus = false
    of Key.Space, Key.Enter:
      ch.checked = not ch.checked
      if ch.onSpace.isSome:
        let fn = ch.onSpace.get
        fn(ch.value, ch.checked)
      ch.render(true)
    else: discard
  ch.render(true)
  sleep(20)


proc show*(ch: ref Checkbox) = ch.render(true)


proc hide*(ch: ref Checkbox) = ch.render()


proc checked*(ch: ref Checkbox): bool = ch.checked


proc checked*(ch: ref Checkbox, state: bool) = ch.checked = state


proc onSpace*(ch: ref Checkbox, cb: Option[SpaceEventProcedure]) =
  ch.onSpace = cb


proc `-`*(ch: ref Checkbox) = ch.show()


proc merge*(ch: ref Checkbox, wg: BaseWidget): void =
  ch.tb.copyFrom(wg.tb, wg.posX, wg.posY, wg.width, wg.height, wg.posX, wg.posY, transparency=true)


proc terminalBuffer*(ch: ref Checkbox): var TerminalBuffer =
  ch.tb
