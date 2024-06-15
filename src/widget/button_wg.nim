import illwill, base_wg, os, strutils
import tables, threading/channels

type
  ButtonState = enum
    Pressed, Unpressed

  ButtonObj* = object of BaseWidget
    label: string = ""
    disabled*: bool = false
    buttonState: ButtonState = Unpressed
    events*: Table[string, EventFn[ref ButtonObj]]
    keyEvents*: Table[Key, EventFn[ref ButtonObj]]

  Button* = ref ButtonObj


const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.None}

proc newButton*(px, py, w, h: int, label: string, id = "",
                disabled = false, bgColor = bgBlue, fgColor = fgWhite,
                pressedBgColor = bgGreen,
                tb = newTerminalBuffer(w + 2, h + py)): Button =
  let style = WidgetStyle(
    paddingX1: 1,
    paddingX2: 1,
    paddingY1: 1,
    paddingY2: 1,
    border: true,
    fgColor: fgColor,
    bgColor: bgColor,
    pressedBgColor: pressedBgColor
  )
  result = Button(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    label: label,
    size: h - py - style.paddingY2 - style.paddingY1,
    tb: tb,
    disabled: disabled,
    style: style,
    events: initTable[string, EventFn[Button]](),
    keyEvents: initTable[Key, EventFn[Button]]()
  )
  result.channel = newChan[WidgetBgEvent]()
  result.keepOriginalSize()


proc newButton*(px, py: int, w, h: WidgetSize, label: string, id = "",
                disabled = false, bgColor = bgBlue, fgColor = fgWhite,
                pressedBgColor = bgGreen,
                tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): Button =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newButton(px, py, width, height, label, id,
                  disabled, bgColor, fgColor, pressedBgColor, tb)


proc newButton*(id: string): Button =
  var button = Button(
    id: id,
    style: WidgetStyle(
      paddingX1: 1,
      paddingX2: 1,
      paddingY1: 1,
      paddingY2: 1,
      border: true,
      bgColor: bgBlue,
      fgColor: fgWhite,
      pressedBgColor: bgGreen
    ),
    events: initTable[string, EventFn[Button]](),
    keyEvents: initTable[Key, EventFn[Button]]()
  )
  button.channel = newChan[WidgetBgEvent]()
  return button


proc on*(bt: Button, event: string, fn: EventFn[Button]) =
  bt.events[event] = fn


proc on*(bt: Button, key: Key, fn: EventFn[Button]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  bt.keyEvents[key] = fn
    


proc call*(bt: Button, event: string, args: varargs[string]) =
  let fn = bt.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(bt, args)


proc call(bt: Button, key: Key) =
  let fn = bt.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(bt)


method resize*(bt: Button) =
  bt.size = bt.height - bt.posY - bt.paddingY2 - bt.paddingY1


method render*(bt: Button) =
  if not bt.illwillInit: return
  bt.clear()
  bt.renderBorder()
  if bt.buttonState == Pressed:
    bt.renderRect(bt.x1, bt.y1, bt.x2, bt.y2, 
                  bt.style.pressedBgcolor, bt.fg)
    bt.tb.write(bt.x1, bt.y1, bt.style.pressedBgcolor, bt.fg, 
                center(bt.label, bt.width - bt.x1), resetStyle)
  else:
    bt.renderRect(bt.x1, bt.y1, bt.x2, bt.y2, bt.bg, bt.fg)
    bt.tb.write(bt.x1, bt.y1, bt.bg, bt.fg, 
                center(bt.label, bt.width - bt.x1), resetStyle)
  bt.tb.display()


method poll*(bt: Button) =
  var widgetEv: WidgetBgEvent
  if bt.channel.tryRecv(widgetEv):
    bt.call(widgetEv.event, widgetEv.args)


method onUpdate*(bt: Button, key: Key) =
  bt.call("preupdate", $key)
  case key
  of Key.None: bt.render()
  of Key.Escape, Key.Tab: bt.focus = false
  of Key.Enter:
    if bt.disabled: return
    bt.call("enter")
    bt.buttonState = Pressed
    bt.render()
  else:
    if key in forbiddenKeyBind: discard
    elif bt.keyEvents.hasKey(key):
      bt.call(key)
  bt.call("postupdate", $key)
      

method onControl*(bt: Button) =
  bt.focus = true
  var delay = 10
  while bt.focus:
    var key = getKeyWithTimeout(bt.rpms)
    bt.onUpdate(key) 

    if bt.buttonState == Pressed:
      delay = delay - 1
    if delay == 0:
      bt.buttonState = Unpressed
      delay = 10

  bt.render()
  sleep(bt.rpms)


method wg*(bt: Button): ref BaseWidget = bt


proc onEnter*(bt: Button, eventFn: EventFn[Button]) =
  bt.on("enter", eventFn)


proc `onEnter=`*(bt: Button, eventFn: EventFn[Button]) =
  bt.on("enter", eventFn)


proc val(bt: Button, label: string) =
  bt.label = label
  bt.render()


proc label*(bt: Button): string = bt.label


proc `label=`*(bt: Button, label: string) =
  bt.val(label)


proc label*(bt: Button, label: string) =
  bt.val(label)


