import illwill, base_wg, os, tables
import threading/channels

type
  CheckboxObj* = object of BaseWidget
    label: string = ""
    value*: string= ""
    checkMark*: char = 'X'
    checked: bool
    events: Table[string, BoolEventFn[ref CheckboxObj]]
    keyEvents*: Table[Key, BoolEventFn[ref CheckboxObj]]

  Checkbox* = ref CheckboxObj

const forbiddenKeyBind = {Key.Tab, Key.None, Key.Escape}


proc newCheckbox*(px, py, w, h: int, id = "", 
                  title = "", label = "", 
                  value = "", checked = false, checkMark = 'X',
                  bgColor = bgNone, fgColor = fgWhite,
                  tb = newTerminalBuffer(w + 2, h + py)): Checkbox =
  let style = WidgetStyle(
    paddingX1: 1,
    paddingX2: 1,
    paddingY1: 1,
    paddingY2: 1,
    border: true,
    fgColor: fgColor,
    bgColor: bgColor
  )

  var checkbox = Checkbox(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    title: title,
    label: label,
    value: value,
    tb: tb,
    checked: checked,
    style: style,
    checkMark: checkMark,
    events: initTable[string, BoolEventFn[Checkbox]](),
    keyEvents: initTable[Key, BoolEventFn[Checkbox]]()
  )
  checkbox.channel = newChan[WidgetBgEvent]()
  checkbox.keepOriginalSize()
  return checkbox


proc newCheckbox*(px, py: int, w, h: WidgetSize, 
                  id = "", title = "", label = "", 
                  value = "", checked = false, 
                  checkMark = 'X',
                  bgColor = bgNone,
                  fgColor = fgWhite,
                  tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): Checkbox =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newCheckbox(px, py, width, height, id, title, label,
                     value, checked, checkMark,
                     bgColor, fgColor, tb)


proc newCheckbox*(id: string): Checkbox =
  var checkbox = Checkbox(
    id: id,
    checked: false,
    style: WidgetStyle(
      paddingX1: 1,
      paddingX2: 1,
      paddingY1: 1,
      paddingY2: 1,
      border: true,
      bgColor: bgNone,
      fgColor: fgWhite
    ),
    events: initTable[string, BoolEventFn[Checkbox]](),
    keyEvents: initTable[Key, BoolEventFn[Checkbox]]()
  )
  checkbox.channel = newChan[WidgetBgEvent]()
  return checkbox


proc on*(ch: Checkbox, event: string, fn: BoolEventFn[Checkbox]) =
  ch.events[event] = fn


proc on*(ch: Checkbox, key: Key, fn: BoolEventFn[Checkbox]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  ch.keyEvents[key] = fn
    

proc call*(ch: Checkbox, event: string, arg: bool) =
  let fn = ch.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(ch, arg)


proc call(ch: Checkbox, key: Key, arg: bool) =
  let fn = ch.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(ch, arg)


method render*(ch: Checkbox) =
  if not ch.illwillInit: return
  ch.clear()
  ch.renderBorder()
  if ch.title != "":
    ch.renderTitle()
  if ch.checked:
    ch.tb.fill(ch.posX + 2, ch.posY + 1, ch.posX + 2, ch.posY + 1, "[")
    ch.tb.fill(ch.posX + 3, ch.posY + 1, ch.posX + 3, ch.posY + 1, $ch.checkMark)
    ch.tb.fill(ch.posX + 4, ch.posY + 1, ch.posX + 4, ch.posY + 1, "]")
  else:
    ch.tb.fill(ch.posX + 2, ch.posY + 1, ch.posX + 2, ch.posY + 1, "[")
    ch.tb.fill(ch.posX + 3, ch.posY + 1, ch.posX + 3, ch.posY + 1, " ")
    ch.tb.fill(ch.posX + 4, ch.posY + 1, ch.posX + 4, ch.posY + 1, "]")
  ch.tb.write(ch.posX + 6, ch.posY + 1, ch.bg, ch.fg, ch.label, resetStyle)
  ch.tb.display()


method poll*(ch: Checkbox) =
  var widgetEv: WidgetBgEvent
  if ch.channel.tryRecv(widgetEv):
    ch.call(widgetEv.event, widgetEv.args)
    ch.render()


method onUpdate*(ch: Checkbox, key: Key) =
  case key
  of Key.None: ch.render()
  of Key.Escape, Key.Tab: ch.focus = false
  of Key.Enter:
    ch.checked = not ch.checked
    ch.call("enter", ch.checked)
    ch.render()
  else:
    if key in forbiddenKeyBind: discard
    elif ch.keyEvents.hasKey(key):
      ch.call(key, ch.checked)
  ch.render()
  sleep(ch.rpms)


method onControl*(ch: Checkbox) =
  ch.focus = true
  while ch.focus:
    var key = getKeyWithTimeout(ch.rpms)
    ch.onUpdate(key)


method wg*(ch: Checkbox): ref BaseWidget = ch


proc checked*(ch: Checkbox): bool = ch.checked


proc checked*(ch: Checkbox, state: bool) = ch.checked = state


proc `checked=`*(ch: Checkbox, state: bool) = ch.checked = state


proc `onEnter=`*(ch: Checkbox, enterEv: BoolEventFn[Checkbox]) =
  ch.on("enter", enterEv)


proc onEnter*(ch: Checkbox, enterEv: BoolEventFn[Checkbox]) =
  ch.on("enter", enterEv)


proc val*(ch: Checkbox, label: string) = 
  ch.label = label
  ch.render()


proc label*(ch: Checkbox): string = ch.label


proc `label=`*(ch: Checkbox, label: string) =
  ch.val(label)


proc label*(ch: Checkbox, label: string) =
  ch.val(label)
