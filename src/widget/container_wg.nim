import illwill, base_wg, tables, threading/channels

type
  ContainerObj* = object of BaseWidget
    widgets: seq[ref BaseWidget]
    events: Table[string, EventFn[ref ContainerObj]]
    keyEvents: Table[Key, EventFn[ref ContainerObj]]

  Container* = ref ContainerObj

const forbiddenKeyBind = {Key.Tab, Key.None}


proc newContainer*(px, py, w, h: int, id = "", title = "",
                  border = true, bgColor = bgNone,
                  fgColor = fgWhite, widgets = newSeq[ref BaseWidget](),
                  tb = newTerminalBuffer(w+2, h + py)): Container =
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

  result = Container(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    title: title,
    tb: tb,
    style: style,
    groups: true,
    events: initTable[string, EventFn[Container]](),
    keyEvents: initTable[Key, EventFn[Container]]()
  )
  result.channel = newChan[WidgetBgEvent]()
  result.keepOriginalSize()


proc newContainer*(px, py: int, w, h: WidgetSize, id = "", title = "",
                  border = true, bgColor = bgNone,
                  fgColor = fgWhite, widgets = newSeq[ref BaseWidget](),
                  tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): Container =
  let width = toConsoleWidth(w)
  let height = toConsoleHeight(h)
  return newContainer(px, py, width, height, id, title,
                      border, bgColor, fgColor, widgets, tb)


proc newContainer*(id: string): Container =
  var container = Container(
    id: id,
    groups: true,
    style: WidgetStyle(
      paddingX1: 1,
      paddingX2: 1,
      paddingY1: 1,
      paddingY2: 1,
      border: true,
      bgColor: bgWhite,
      fgColor: fgBlack
    ),
    events: initTable[string, EventFn[Container]](),
    keyEvents: initTable[Key, EventFn[Container]]()
  )
  container.channel = newChan[WidgetBgEvent]()
  return container


proc add*(ctr: Container, wg: ref BaseWidget, width: float, height: float) =
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
  wg.rpms = ctr.rpms
  wg.illwillInit = true
  wg.resize()   # recompute size/derived fields after repositioning
  ctr.widgets.add(wg)


method setChildTb*(ctr: Container, tb: TerminalBuffer): void =
  for w in ctr.widgets:
    w.tb = tb

proc on*(ctr: Container, event: string, fn: EventFn[Container]) =
  ctr.events[event] = fn


proc on*(ctr: Container, key: Key, fn: EventFn[Container]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind:
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  ctr.keyEvents[key] = fn


method call*(ctr: Container, event: string, args: varargs[string]) =
  if ctr.events.hasKey(event):
    let fn = ctr.events[event]
    fn(ctr, args)


method call*(ctr: ContainerObj, event: string, args: varargs[string]) =
  if ctr.events.hasKey(event):
    let fn = ctr.events[event]
    let ctrRef = ctr.asRef()
    fn(ctrRef, args)


proc call(ctr: Container, key: Key) =
  if ctr.keyEvents.hasKey(key):
    let fn = ctr.keyEvents[key]
    fn(ctr)


method render*(ctr: Container) =
  ctr.clear()
  ctr.renderBorder()
  ctr.renderTitle()
  for w in ctr.widgets:
    if w.visibility:
      w.rerender()
  if not ctr.suppressDisplay: ctr.tb.display()


method poll*(ctr: Container) =
  ## Propagate channel poll to all children (needed in non-blocking mode).
  for w in ctr.widgets:
    w.poll()


proc show*(ctr: Container, resetCursors = false) =
  ## Make Container and all children visible. Call before onControl() for popup use.
  ## Clears the full terminal buffer first so background widgets don't bleed through.
  ctr.visibility = true
  ctr.cursor = 0
  for w in ctr.widgets:
    w.visibility = true
    w.tb = ctr.tb
    w.illwillInit = true
    if resetCursors: w.resetCursor()
  ctr.tb.fill(0, 0, terminalWidth(), terminalHeight(), bgNone, fgWhite, " ")
  ctr.render()


proc hide*(ctr: Container) =
  ## Hide Container and all children. Releases focus.
  ctr.focus = false
  ctr.visibility = false
  for w in ctr.widgets:
    w.visibility = false
    w.focus = false
  ctr.clear()


method onUpdate*(ctr: Container, key: Key) =
  ## Non-blocking mode: Tab cycles focus between children; other keys are
  ## forwarded to the currently focused child.
  case key
  of Key.Escape:
    ctr.focus = false
  of Key.Tab:
    if ctr.widgets.len > 0:
      if ctr.cursor < ctr.widgets.len:
        ctr.widgets[ctr.cursor].focus = false
      inc ctr.cursor
      if ctr.cursor >= ctr.widgets.len:
        ctr.cursor = 0
      ctr.widgets[ctr.cursor].focus = true
  of Key.None: discard
  else:
    if ctr.keyEvents.hasKey(key):
      ctr.call(key)
    elif ctr.cursor < ctr.widgets.len:
      ctr.widgets[ctr.cursor].onUpdate(key)
  ctr.render()


method onControl*(ctr: Container) =
  ## Blocking mode: Tab enters child widgets sequentially; Escape exits Container.
  ## Mirrors TerminalApp.hold() but scoped to Container's child list.
  ## Returns immediately if the container is hidden (visibility = false).
  if not ctr.visibility: return
  ctr.focus = true
  ctr.cursor = 0

  # ensure all children are ready
  for w in ctr.widgets:
    w.illwillInit = true
    w.rpms = ctr.rpms
    w.tb = ctr.tb
    w.focus = false

  while ctr.focus:
    # highlight the focused child (double border)
    for i, w in ctr.widgets:
      w.focus = (i == ctr.cursor)
    ctr.render()

    var key = getKeyWithTimeout(ctr.rpms)
    case key
    of Key.Escape:
      # Container always owns Esc — never let a child consume it
      ctr.focus = false
    of Key.Tab:
      # Advance focus to next child; Container owns Tab too
      if ctr.widgets.len > 0:
        inc ctr.cursor
        if ctr.cursor >= ctr.widgets.len:
          ctr.cursor = 0
    of Key.None:
      discard
    else:
      # Forward all other keys to the focused child via onUpdate.
      # This keeps the Container's event loop alive so Esc/Tab are
      # always interceptable (calling child.onControl() would block
      # and the child would consume Esc before Container sees it).
      if ctr.keyEvents.hasKey(key):
        ctr.call(key)
      elif ctr.cursor < ctr.widgets.len:
        ctr.widgets[ctr.cursor].onUpdate(key)

  # clear all child focus on container exit
  for w in ctr.widgets:
    w.focus = false
  ctr.render()


method onMouseEvent*(ctr: Container, mouseInfo: MouseInfo) =
  for i, child in ctr.widgets:
    if child.visibility and child.contains(mouseInfo.x, mouseInfo.y):
      if mouseInfo.button == MouseButton.mbLeft and mouseInfo.action == MouseButtonAction.mbaPressed:
        if ctr.cursor < ctr.widgets.len:
          ctr.widgets[ctr.cursor].focus = false
        ctr.cursor = i
        ctr.widgets[ctr.cursor].focus = true
      child.onMouseEvent(mouseInfo)
      return
  if not ctr.onMouse.isNil:
    ctr.onMouse(ctr, mouseInfo)

method wg*(ctr: Container): ref BaseWidget = ctr
