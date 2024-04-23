import illwill, base_wg, os, tables
import threading/channels

type
  Checkbox* = object of BaseWidget
    label: string = ""
    value: string= ""
    checkMark: char = 'X'
    checked: bool
    events: Table[string, BoolEventFn[ref Checkbox]]
    keyEvents*: Table[Key, BoolEventFn[ref Checkbox]]


const forbiddenKeyBind = {Key.Tab, Key.None, Key.Escape}


proc newCheckbox*(px, py, w, h: int, id = "", 
                  title = "", label = "", 
                  value = "", checked = false, checkMark = 'X',
                  bgColor = bgNone, fgColor = fgWhite,
                  tb = newTerminalBuffer(w + 2, h + py)): ref Checkbox =
  let style = WidgetStyle(
    paddingX1: 1,
    paddingX2: 1,
    paddingY1: 1,
    paddingY2: 1,
    border: true,
    fgColor: fgColor,
    bgColor: bgColor
  )

  var checkbox = (ref Checkbox)(
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
    events: initTable[string, BoolEventFn[ref Checkbox]](),
    keyEvents: initTable[Key, BoolEventFn[ref Checkbox]]()
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
                  tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): ref Checkbox =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newCheckbox(px, py, width, height, id, title, label,
                     value, checked, checkMark,
                     bgColor, fgColor, tb)



proc on*(ch: ref Checkbox, event: string, fn: BoolEventFn[ref Checkbox]) =
  ch.events[event] = fn


proc on*(ch: ref Checkbox, key: Key, fn: BoolEventFn[ref Checkbox]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  ch.keyEvents[key] = fn
    

proc call*(ch: ref Checkbox, event: string, arg: bool) =
  let fn = ch.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(ch, arg)


proc call(ch: ref Checkbox, key: Key, arg: bool) =
  let fn = ch.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(ch, arg)


method render*(ch: ref Checkbox) =
  if not ch.illwillInit: return
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
  ch.tb.write(ch.posX + 6, ch.posY + 1, resetStyle, ch.label)
  ch.tb.display()


method poll*(ch: ref Checkbox) =
  var widgetEv: WidgetBgEvent
  if ch.channel.tryRecv(widgetEv):
    ch.call(widgetEv.event, widgetEv.args)
    ch.render()


method onUpdate*(ch: ref Checkbox, key: Key) =
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
  sleep(ch.refreshWaitTime)


method onControl*(ch: ref Checkbox) =
  ch.focus = true
  while ch.focus:
    var key = getKeyWithTimeout(ch.refreshWaitTime)
    ch.onUpdate(key)


method wg*(ch: ref Checkbox): ref BaseWidget = ch


proc checked*(ch: ref Checkbox): bool = ch.checked


proc checked*(ch: ref Checkbox, state: bool) = ch.checked = state


proc `checked=`*(ch: ref Checkbox, state: bool) = ch.checked = state


proc `onEnter=`*(ch: ref Checkbox, enterEv: BoolEventFn[ref Checkbox]) =
  ch.on("enter", enterEv)


proc onEnter*(ch: ref Checkbox, enterEv: BoolEventFn[ref Checkbox]) =
  ch.on("enter", enterEv)


proc val*(ch: ref Checkbox, label: string) = 
  ch.label = label
  ch.render()


proc label*(ch: ref Checkbox): string = ch.label


proc `label=`*(ch: ref Checkbox, label: string) =
  ch.val(label)


proc label*(ch: ref Checkbox, label: string) =
  ch.val(label)
