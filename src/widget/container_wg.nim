import illwill, base_wg, tables, threading/channels

type
  Container* = object of BaseWidget
    widgets: seq[ref BaseWidget]
    events: Table[string, EventFn[ref Container]]
    keyEvents: Table[Key, EventFn[ref Container]]

const forbiddenKeyBind = {Key.Tab, Key.None}

proc newContainer*(px, py, w, h: int, id = "", title = "",
                  border = true, bgColor = bgNone,
                  fgColor = fgWhite, widgets = newSeq[ref BaseWidget](),
                  tb = newTerminalBuffer(w+2, h + py)): ref Container =
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
 
  result = (ref Container)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    title: title,
    tb: tb,
    style: style,
    groups: true,
    events: initTable[string, EventFn[ref Container]](),
    keyEvents: initTable[Key, EventFn[ref Container]]()
  )
  result.channel = newChan[WidgetBgEvent]()
  result.keepOriginalSize()


proc newContainer*(px, py: int, w, h: WidgetSize, id = "", title = "",
                  border = true, bgColor = bgNone,
                  fgColor = fgWhite, widgets = newSeq[ref BaseWidget](),
                  tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): ref Container =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newContainer(px, py, width, height, id, title,
                      border, bgColor, fgColor, widgets, tb) 



proc add*(ctr: ref Container, wg: ref BaseWidget, width: float, height: float) =
  # calculate w, h in container
  let w = ((ctr.x2 - ctr.x1).toFloat * width).toInt
  let h = ((ctr.y2 - ctr.y1).toFloat * height).toInt
  if ctr.widgets.len == 0:
    wg.posX = ctr.x1
    wg.posY = ctr.y1
    wg.width = ctr.x1 + w
    wg.height = ctr.y1 + h
  else:
    if (ctr.widgets[^1].width / ctr.width) > 0.95:
      # next line
      wg.posX = ctr.widgets[^1].posX
      wg.posY = ctr.widgets[^1].height + 1
    else:
      # inline
      wg.posX = ctr.widgets[^1].width + 1
      wg.posY = ctr.widgets[^1].posY

  wg.width = min(wg.posX + w, ctr.x2)
  wg.height = min(wg.posY + h, ctr.y2)
  wg.bg(ctr.bg)
  wg.fg(ctr.fg)
  wg.tb = ctr.tb
  ctr.widgets.add(wg)



method setChildTb*(ctr: ref Container, tb: TerminalBuffer): void =
  for w in ctr.widgets:
    w.tb = tb

proc on*(ctr: ref Container, event: string, fn: EventFn[ref Container]) =
  ctr.events[event] = fn


proc on*(ctr: ref Container, key: Key, fn: EventFn[ref Container]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  ctr.keyEvents[key] = fn
    

method call*(ctr: ref Container, event: string, args: varargs[string]) =
  let fn = ctr.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(ctr, args)


method call*(ctr: Container, event: string, args: varargs[string]) =
  let fn = ctr.events.getOrDefault(event, nil)
  if not fn.isNil:
    let ctrRef = ctr.asRef()
    fn(ctrRef, args)
    

proc call(ctr: ref Container, key: Key) =
  let fn = ctr.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(ctr)


method render*(ctr: ref Container) =
  ctr.clear()
  ctr.renderBorder()
  ctr.renderTitle()
  for w in ctr.widgets:
    if w.visibility:
      w.rerender()
  ctr.tb.display()


proc baseControl(ctr: ref Container) =
  # container widget
  while true:
    var key = getKeyWithTimeout(ctr.refreshWaitTime)
    case key
    of Key.Escape:
      ctr.focus = false
      break
    of Key.Tab:
      inc ctr.cursor
      break
    else:
      if ctr.keyEvents.hasKey(key):
        ctr.call(key)
      #ctr.render()


method onUpdate*(ctr: ref Container, key: Key) =
  case key
  of Key.Tab, Key.None:
    if ctr.cursor == 0:
      ctr.baseControl
    if not ctr.focus: return
    if ctr.cursor > ctr.widgets.len: ctr.cursor = 0
    ctr.widgets[ctr.cursor - 1].onControl()
    inc ctr.cursor
  of Key.Escape: 
    ctr.focus = false
  else: discard
  ctr.render()
 

method onControl*(ctr: ref Container) =
  # another main loop for the child widget
  ctr.focus = true
  for w in ctr.widgets: 
    w.blocking = true
    w.illwillInit = true
  while ctr.focus:
    ctr.clear()
    ctr.render()
    var key = getKeyWithTimeout(ctr.refreshWaitTime)
    ctr.onUpdate(key)


method wg*(ctr: ref Container): ref BaseWidget = ctr





