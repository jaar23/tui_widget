import illwill, base_wg, os, strutils
import tables

type
  ButtonState = enum
    Pressed, Unpressed

  Button* = object of BaseWidget
    label: string = ""
    disabled*: bool = false
    state: ButtonState = Unpressed
    events*: Table[string, EventFn[ref Button]]
    keyEvents*: Table[Key, EventFn[ref Button]]


const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.None}

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
    style: style,
    events: initTable[string, EventFn[ref Button]](),
    keyEvents: initTable[Key, EventFn[ref Button]]()
  )


proc on*(bt: ref Button, event: string, fn: EventFn[ref Button]) =
  bt.events[event] = fn


proc on*(bt: ref Button, key: Key, fn: EventFn[ref Button]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  bt.keyEvents[key] = fn
    


proc call*(bt: ref Button, event: string) =
  let fn = bt.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(bt)


proc call(bt: ref Button, key: Key) =
  let fn = bt.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(bt)


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


method onUpdate*(bt: ref Button, key: Key) =
  case key
  of Key.None: bt.render()
  of Key.Escape, Key.Tab: bt.focus = false
  of Key.Enter:
    if bt.disabled: return
    bt.call("enter")
    bt.state = Pressed
    bt.render()
  else:
    if key in forbiddenKeyBind: discard
    elif bt.keyEvents.hasKey(key):
      bt.call(key)
      



method onControl*(bt: ref Button) =
  bt.focus = true
  var delay = 10
  while bt.focus:
    var key = getKeyWithTimeout(bt.refreshWaitTime)
    bt.onUpdate(key) 

    if bt.state == Pressed:
      delay = delay - 1
    if delay == 0:
      bt.state = Unpressed
      delay = 10

  bt.render()
  sleep(bt.refreshWaitTime)



method wg*(bt: ref Button): ref BaseWidget = bt


proc onEnter*(bt: ref Button, eventFn: EventFn[ref Button]) =
  bt.on("enter", eventFn)


proc `onEnter=`*(bt: ref Button, eventFn: EventFn[ref Button]) =
  bt.on("enter", eventFn)


proc val(bt: ref Button, label: string) =
  bt.label = label
  bt.render()


proc label*(bt: ref Button): string = bt.label


proc `label=`*(bt: ref Button, label: string) =
  bt.val(label)

proc label*(bt: ref Button, label: string) =
  bt.val(label)


