import illwill, base_wg, options, os

type
  Checkbox = ref object of BaseWidget
    label: string = ""
    value: string = ""
    visualSkip: int = 2
    title: string
    checked: bool
    onSpace: Option[SpaceEventProcedure]

proc newCheckbox*(w, h, px, py: int, title = "", label = "", value = "", checked = false,
                  tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): Checkbox =
  var checkbox = Checkbox(
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


proc render*(ch: var Checkbox, standalone = false) =
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
  if standalone: ch.tb.display()


method onControl*(ch: var Checkbox) =
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


proc show*(ch: var Checkbox) = ch.render(true)


proc hide*(ch: var Checkbox) = ch.render()


proc checked*(ch: var Checkbox): bool = ch.checked


proc checked*(ch: var Checkbox, state: bool) = ch.checked = state


proc onSpace*(ch: var Checkbox, cb: Option[SpaceEventProcedure]) =
  ch.onSpace = cb


proc `-`*(ch: var Checkbox) = ch.show()


proc merge*(ch: var Checkbox, wg: BaseWidget): void =
  ch.tb.copyFrom(wg.tb, wg.posX, wg.posY, wg.width, wg.height, wg.posX, wg.posY, transparency=true)


proc terminalBuffer*(ch: var Checkbox): var TerminalBuffer =
  ch.tb
