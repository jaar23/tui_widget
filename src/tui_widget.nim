import illwill, os, strutils, std/terminal, math, options
import malebolgia, threading/channels, std/tasks, sequtils, std/enumerate
import 
  widget/base_wg,
  widget/display_wg,
  widget/input_box_wg,
  widget/button_wg,
  widget/checkbox_wg,
  widget/table_wg,
  widget/progress_wg,
  widget/listview_wg,
  widget/label_wg,
  widget/gauge_wg,
  widget/textarea_wg,
  widget/container_wg,
  widget/chart_wg,
  widget/dropdown_wg,
  widget/md_display_wg,
  widget/heatmap_wg,
  widget/json_display_wg,
  widget/yaml_display_wg

export
  base_wg,
  display_wg,
  input_box_wg,
  button_wg,
  checkbox_wg,
  table_wg,
  progress_wg,
  listview_wg,
  label_wg,
  gauge_wg,
  textarea_wg,
  container_wg,
  illwill,
  chart_wg,
  dropdown_wg,
  md_display_wg,
  heatmap_wg,
  json_display_wg,
  yaml_display_wg

type
  TerminalApp* = object
    width: int
    height: int
    title: string
    bgColor: illwill.BackgroundColor 
    fgColor: illwill.ForegroundColor
    cursor: int = 0
    fullscreen: bool = true
    border: bool = true
    autoResize*: bool = true
    tb: TerminalBuffer
    widgets: seq[ref BaseWidget]
    rpms: int = 50
    origWidth: int
    origHeight: int
    mouseEnabled: bool = false 

  SizeOverflow = object of CatchableError


var bgChannel = newChan[Task]() 

proc enableMouse*(app: var TerminalApp) =
  ## Enable mouse event support. Must be called before app.run().
  app.mouseEnabled = true


proc newTerminalApp*(tb: TerminalBuffer = newTerminalBuffer(terminalWidth(),
                     terminalHeight()), title: string = "", border: bool = false,
                     bgColor = illwill.bgNone, fgColor = illwill.fgWhite,
                     rpms: int = 20): TerminalApp =
  result = TerminalApp(
    width: terminalWidth(),
    height: terminalHeight(),
    title: title,
    border: false,  # disable for full app to avoid overflow
    bgColor: bgNone,  # disable bgcolor until x
    fgColor: fgWhite, # disable fgcolor until x
    rpms: rpms,
    widgets: newSeq[ref BaseWidget](),
    tb: tb,
    origWidth: terminalWidth(),
    origHeight: terminalHeight(),
    mouseEnabled: false # disabled by default
  )


proc terminalBuffer*(app: var TerminalApp): var TerminalBuffer =
  app.tb


proc addWidget*(app: var TerminalApp, widget: ref BaseWidget) =
  widget.tb = app.terminalBuffer
  if widget.groups:
    widget.setChildTb(app.terminalBuffer)
  widget.rpms = app.rpms
  widget.keepOriginalSize()
  widget.clampToConsole()
  app.widgets.add(widget)


proc addWidget*(app: var TerminalApp, widget: ref BaseWidget, 
                width: int, height: int) =
  if app.widgets.len == 0:
    widget.posX = 1
    widget.posY = 1
    widget.width = width
    widget.height = height
  else:
    if (app.widgets[^1].width / consoleWidth()) > 0.95:
      widget.posX = min(app.widgets[^1].posX, 1)
      widget.posY = app.widgets[^1].height + 1
    else:
      widget.posX = app.widgets[^1].width + 1
      widget.posY = app.widgets[^1].posY

  widget.width = min(widget.posX + width, consoleWidth())
  widget.height = min(widget.posY + height, consoleHeight())
  widget.clampToConsole()
  widget.resize()
  app.addWidget(widget)


# WidgetSize variants treat width/height as a FRACTION OF THE CONSOLE that
# the widget should occupy. The underlying int variant uses
# `widget.height = posY + height_param`, so a `height_param` of N produces a
# widget spanning N+1 rows. To make `0.5` actually consume ~half the console
# (and three widgets at 0.5/0.3/0.2 stack to fill the screen exactly), we
# subtract 1 from the converted row/col count. `MinWidgetSpan - 1` is the
# floor so small fractions still hand a usable widget to the int variant —
# clampToConsole will hide it later if it ends up genuinely too small.

proc addWidget*(app: var TerminalApp, widget: ref BaseWidget,
                width, height: WidgetSize ) =
  let w = max(MinWidgetSpan - 1, toConsoleWidth(width)  - 1)
  let h = max(MinWidgetSpan - 1, toConsoleHeight(height) - 1)
  app.addWidget(widget, w, h)


proc addWidget*(app: var TerminalApp, widget: ref BaseWidget,
                width: int, height: WidgetSize) =
  let h = max(MinWidgetSpan - 1, toConsoleHeight(height) - 1)
  app.addWidget(widget, width, h)


proc addWidget*(app: var TerminalApp, widget: ref BaseWidget,
                width: WidgetSize, height: int = 0) =
  let w = max(MinWidgetSpan - 1, toConsoleWidth(width) - 1)
  let h = if height == 1: 0 else: height
  app.addWidget(widget, w, h)


proc addWidget*(app: var TerminalApp, 
                widget: ref BaseWidget,
                width, height, 
                offsetLeft, offsetTop, 
                offsetRight, offsetBottom: int) {.raises: [SizeOverflow, Exception].} =
  if app.widgets.len == 0:
    widget.posX = max(1 + offsetLeft, 1)
    widget.posY = max(1 + offsetTop, 1)
    widget.width = width
    widget.height = height
  else:
    if (app.widgets[^1].width / consoleWidth()) > 0.95:
      widget.posX = min(app.widgets[^1].posX, 1)
      widget.posY = app.widgets[^1].height + 1
      widget.posX += offsetLeft
      widget.posY += offsetTop
      widget.posX = max(widget.posX - offsetRight, 1)
      widget.posY = max(widget.posY - offsetBottom, app.widgets[^1].height + 1)
    else:
      widget.posX = app.widgets[^1].width + 1
      widget.posY = app.widgets[^1].posY
      widget.posX = max(app.widgets[^1].width + 1, widget.posX + offsetLeft)
      widget.posY = max(app.widgets[^1].posY, widget.posY + offsetTop)
      if app.widgets[^1].height < widget.posY:
        widget.posX = widget.posX - offsetRight
      else:
        widget.posX = max(widget.posX - offsetRight, app.widgets[^1].width + 1)
      widget.posY = max(widget.posY - offsetBottom, app.widgets[^1].posY)


  widget.width = min(widget.posX + width, consoleWidth())
  widget.height = min(widget.posY + height, consoleHeight())
  widget.clampToConsole()
  widget.resize()
  app.addWidget(widget)



proc addWidget*(app: var TerminalApp,
                widget: ref BaseWidget,
                width: WidgetSize,
                height: int,
                offsetLeft, offsetTop,
                offsetRight, offsetBottom: int) {.raises: [SizeOverflow, Exception].} =
  let w = toConsoleWidth(width)
  let h = if height == 1: 0 else: height
  app.addWidget(widget, w, h, offsetLeft, offsetTop, offsetRight, offsetBottom)


proc addWidget*(app: var TerminalApp,
                widget: ref BaseWidget,
                width: int, 
                height: WidgetSize, 
                offsetLeft, offsetTop, 
                offsetRight, offsetBottom: int) {.raises: [SizeOverflow, Exception].} =
  let h = toConsoleHeight(height)
  app.addWidget(widget, width, h, offsetLeft, offsetTop, offsetRight, offsetBottom)


proc addWidget*(app: var TerminalApp,
                widget: ref BaseWidget,
                width, height: WidgetSize, 
                offsetLeft, offsetTop, 
                offsetRight, offsetBottom: int) {.raises: [SizeOverflow, Exception].} =
  let w = toConsoleWidth(width)
  let h = toConsoleHeight(height)
  app.addWidget(widget, w, h, offsetLeft, offsetTop, offsetRight, offsetBottom)


proc addWidget*(app: var TerminalApp,
                widget: ref BaseWidget,
                width, height, 
                offsetLeft, offsetTop, 
                offsetRight, offsetBottom: WidgetSize) {.raises: [SizeOverflow, Exception].} =
  let totalWidth = consoleWidth()
  let totalHeight = consoleHeight()
  
  # Convert offsets to actual pixel/character values
  let oleft = toConsoleWidth(offsetLeft)
  let otop = toConsoleHeight(offsetTop)
  let oright = toConsoleWidth(offsetRight)
  let obtm = toConsoleHeight(offsetBottom)
  
  # Position widget starts from the offset
  widget.posX = oleft + 1
  widget.posY = otop + 1
  
  # Calculate end positions - if offset is 0, go to the edge
  let endX = if oright == 0: totalWidth else: totalWidth - oright
  let endY = if obtm == 0: totalHeight else: totalHeight - obtm
  
  # Widget dimensions are from start position to end position
  let w = toConsoleWidth(width)
  let h = toConsoleHeight(height)
  widget.width = min(oleft + w, totalWidth)
  widget.height = min(otop + h, totalHeight)

  widget.clampToConsole()
  # widget.resize()
  app.addWidget(widget)

proc widgets*(app: var TerminalApp): seq[ref BaseWidget] =
  app.widgets


proc `[]=`*(app: var TerminalApp, id: string, widget: ref BaseWidget) =
  widget.id = id
  app.addWidget(widget)


proc `[]=`*(app: var TerminalApp, id: string, widget: ref BaseWidget,
            width, height: WidgetSize) =
  widget.id = id
  app.addWidget(widget, width, height)


proc `[]=`*(app: var TerminalApp, id: string, widget: ref BaseWidget,
            width: WidgetSize, height: int) =
  widget.id = id
  app.addWidget(widget, width, height)


proc `[]=`*(app: var TerminalApp, id: string, widget: ref BaseWidget,
            width: int, height: WidgetSize) =
  widget.id = id
  app.addWidget(widget, width, height)


proc `[]`*(app: var TerminalApp, id: string): Option[ref BaseWidget] =
  result = none(ref BaseWidget) 
  for w in app.widgets:
    if w.id == id:
      result = some(w.wg)
      break


proc requiredSize*(app: var TerminalApp): (int, int, int) =
  var w, h: int = 0
  for wg in app.widgets:
    if wg.width > w:
      w = wg.width
    if wg.height > h:
      h = wg.height
  return (w, h, w * h)


proc renderAppFrame(app: var TerminalApp) =
  app.tb.fill(0, 0, app.width, app.height, app.bgColor, app.fgColor)
  let (w, h, requiredSize) = app.requiredSize()
  if app.border: app.tb.drawRect(0, 0, w + 1, h + 1)
  let title: string = ansiStyleCode(styleBright) & app.title
  if app.title != "": app.tb.write(2, 0, app.bgColor, title)


proc render*(app: var TerminalApp, nonBlocking=false) =
  for w in app.widgets:
    w.suppressDisplay = true
  # Defensive whole-buffer reset: wipes any stale cells from previous frames
  # (e.g. focus-style borders, popup overlays) so per-widget render bugs can't
  # leak into neighbour widgets' cells.
  app.renderAppFrame()
  # render all non-focused widgets first
  for i, w in app.widgets:
    if i == app.cursor: continue
    if w.visibility:
      w.safeCall "render":
        w.rerender()
  # render focused widget last so its popup overlays neighbors
  if app.cursor < app.widgets.len:
    let fw = app.widgets[app.cursor]
    if fw.visibility:
      fw.safeCall "render":
        fw.rerender()
  for w in app.widgets:
    w.suppressDisplay = false
  app.tb.display()


proc widgetInit(app: var TerminalApp) =
  for w in app.widgets:
    w.illwillInit = true
    # Last chance to clamp bounds before the first render — catches widgets
    # constructed with positional newXxx(px, py, w, h, ...) values that
    # exceed the console at construction time.
    w.clampToConsole()


proc setWidgetBlocking(app: var TerminalApp) =
  for w in app.widgets:
    w.blocking = true
    

proc runInBackground*(task: sink Task) =
  ## Sending task to background thread via channel
  ## accept only isolated variable in tasks
  ## refers to std/tasks.
  ##
  ## **Example**
  ## .. code-block::
  ##   let httpCallTask = toTask httpCall(addr app, display.id, url)
  ##   runInBackground(httpCallTask)
  ##
  bgChannel.send(task) 


proc notify*(app: ptr TerminalApp, id: string, event: string, 
             args: varargs[string]) =
  ## Notify widget via its channel, then widget will be poll
  ## by main thread and widget event will be called
  ## note that there is only string args supported.
  ## 
  ## **Example**
  ## .. code-block::
  ##   display.on("refresh", proc(dp: ref Display, args: varargs[string]) =
  ##     dp.text = args[0]
  ##   )
  ## You may be making a http call and the call is coming back in a later 
  ## time, the task is running in background and you want it to notify
  ## you once the result is ready. Then, you can using notify inside
  ## the background task
  ##
  ## **Example**
  ## .. code-block::
  ##   proc httpRequest(url: string, app: ptr TerminalApp, id: string) =
  ##     var client = newHttpClient(sslContext=newContext(verifyMode=CVerifyPeerUseEnvVars))
  ##     defer: client.close()
  ##     try:
  ##       let content = client.getContent(url)
  ##       notify(app, id, "refresh", content) # notify the widget
  ##     except:
  ##       notify(app, id, "refresh", getCurrentExceptionMsg())
  let arguments = args.toSeq()
  for w in app.widgets:
    if w.id == id: 
      w.channel.send(WidgetBgEvent(
        widgetId: id,
        event: event,
        args: arguments,
        error: ""
        ))


proc backgroundTasks() {.thread.} =
  while true:
    let task = bgChannel.recv()
    try:
      task.invoke()
    except CatchableError:
      # echo would corrupt the TUI; route to the app-level error handler if
      # one is set, otherwise swallow. Background thread has no widget id.
      let e = getCurrentException()
      let msg = (if e.isNil: "unknown" else: e.msg)
      let trc = (if e.isNil: ""        else: e.getStackTrace())
      {.gcsafe.}:
        if not globalErrorHandler.isNil:
          try: globalErrorHandler("<background>", "task", msg, trc)
          except CatchableError: discard


proc `onWidgetError=`*(app: var TerminalApp, handler: GlobalErrorHandler) =
  ## Install a process-wide handler that fires every time `safeCall` traps
  ## a widget exception (or a background task fails). Setting nil disables.
  globalErrorHandler = handler


proc pollWidgetChannel(app: var TerminalApp) =
  for w in app.widgets:
    w.safeCall "poll":
      w.poll()


proc nonBlockingControl(app: var TerminalApp) =
  if app.widgets[app.cursor].blocking:
    let w = app.widgets[app.cursor]
    w.safeCall "onControl":
      w.onControl()
    inc app.cursor
  else:
    inc app.cursor
    if app.cursor > app.widgets.len - 1: app.cursor = 0
  # Skip non-focusable widgets (e.g. a status bar). Bounded by total widget
  # count so an all-non-focusable list can't loop forever.
  var hops = 0
  while hops < app.widgets.len and not app.widgets[app.cursor].focusable:
    inc app.cursor
    if app.cursor > app.widgets.len - 1: app.cursor = 0
    inc hops


proc resize(app: var TerminalApp): bool =
  # resize
  if not app.autoResize: return false
  let origWidth = app.origWidth
  let origHeight = app.origHeight
  let windWidth = terminalWidth()
  let windHeight = terminalHeight()
  if windWidth != app.width or windHeight != app.height:
    eraseScreen()
    app.width = windWidth
    app.height = windHeight
    app.tb = newTerminalBuffer(windWidth, windHeight)
    var index = 0
    for w in  app.widgets:
      # ----------------w
      #                 |
      #                 |
      #                 |
      #                 h
      let wgHeight = w.origHeight
      let wgWidth = w.origWidth
      let wgPosY = w.origPosY
      let wgPosX = w.origPosX
      let wgWidthPercent = wgWidth / origWidth
      let wgHeightPercent = wgHeight / origHeight
      let newWgWidth = floor(windWidth.toFloat * wgWidthPercent).toInt()
      let newWgHeight = floor(windHeight.toFloat * wgHeightPercent).toInt()
      w.width = newWgWidth
      #w.height = if wgHeight < newWgHeight: wgHeight else: max(3, newWgHeight)
      w.height = newWgHeight
      # posY
      let wgPosYPercent = wgPosY / origHeight
      let newWgPosY = floor(windHeight.toFloat * wgPosYPercent).toInt()
      w.posy = max(wgPosY, newWgPosY)
      #w.posY = newWgPosY
      # posX
      let wgPosXPercent = wgPosX / origWidth
      let newWgPosX = floor(windWidth.toFloat * wgPosXPercent).toInt()
      w.posX = newWgPosX
      # Clamp the percentage-scaled bounds back into the new console size —
      # shrinking the terminal can produce inverted (width < posX) values.
      # Original requested dims stay in w.origPosX/Y/Width/Height so the
      # widget reappears at its intended layout if the terminal grows again.
      # If after clamping the widget can't fit MinWidgetSpan, it's hidden.
      w.clampToConsole()
      # resize
      w.resize()
      w.tb = app.tb
      # If clampToConsole hid the widget (terminal too tiny), unhide for
      # future cycles where it may fit again — visibility is restored on
      # each resize attempt; clampToConsole re-hides if still invalid.
      if not w.visibility and w.width > w.posX and w.height > w.posY:
        w.visibility = true
      inc index
    sleep(50)
    eraseScreen()
    return true
  else:
    return false
    

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)


proc go(app: var TerminalApp) =
  illwillInit(fullscreen = app.fullscreen, mouse = app.mouseEnabled)
  setControlCHook(exitProc)
  hideCursor()

  let (w, h, requiredSize) = app.requiredSize()
  if requiredSize > (terminalWidth() * terminalHeight()):
    stdout.styledWriteLine(terminal.fgWhite, terminal.bgRed,
                           center("terminal width and height cannot fit application.",
                               terminalWidth()))
    stdout.styledWriteLine(terminal.fgWhite, terminal.bgRed,
                           center("width: " & $w & " height: " & $h, terminalWidth()))
    stdout.resetAttributes()
    stdout.flushFile()
    quit(0)
  
  # init widgets
  app.widgetInit()

  var threadMaster = createMaster()
  threadMaster.spawn backgroundTasks()
  
  app.tb.clear()
  app.renderAppFrame() 
  while true:
    if app.resize():
      app.tb.clear()
      app.renderAppFrame()
      continue

    app.render()
    var key = getKeyWithTimeout(app.rpms)
    case key
    of Key.Tab:
      app.widgets[app.cursor].focus = false
      app.nonBlockingControl()
    of Key.Mouse:
      if app.mouseEnabled:
        let mouseInfo = getMouse()
        # Left-click shifts keyboard focus to the clicked widget
        if mouseInfo.button == MouseButton.mbLeft and mouseInfo.action == MouseButtonAction.mbaPressed:
          for i, widget in app.widgets:
            if widget.visibility and widget.focusable and
               widget.contains(mouseInfo.x, mouseInfo.y):
              app.widgets[app.cursor].focus = false
              app.cursor = i
              app.widgets[app.cursor].focus = true
              break
        for widget in app.widgets:
          if widget.visibility and widget.contains(mouseInfo.x, mouseInfo.y):
            widget.safeCall "onMouseEvent":
              widget.onMouseEvent(mouseInfo)
        app.render()
    else:
      let w = app.widgets[app.cursor]
      w.focus = true
      w.safeCall "onUpdate":
        w.onUpdate(key)

      # poll for changes from other widget
      app.pollWidgetChannel()
      app.render()


proc hold(app: var TerminalApp) =
  illwillInit(fullscreen = app.fullscreen, mouse = app.mouseEnabled)
  setControlCHook(exitProc)
  hideCursor()

  let (w, h, requiredSize) = app.requiredSize()
  if requiredSize > (terminalWidth() * terminalHeight()):
    stdout.styledWriteLine(terminal.fgWhite, terminal.bgRed,
                           center("terminal width and height cannot fit application.",
                               terminalWidth()))
    stdout.styledWriteLine(terminal.fgWhite, terminal.bgRed,
                           center("width: " & $w & " height: " & $h, terminalWidth()))
    stdout.resetAttributes()
    stdout.flushFile()
    quit(0)
  
  # init widgets
  app.widgetInit()

  # blocking mode
  app.setWidgetBlocking()

  while true:
    if app.resize():
      app.tb.clear()
      continue

    app.tb.clear()
    app.renderAppFrame()
    app.render()
    var key = getKeyWithTimeout(app.rpms)
    case key
    of Key.Tab, Key.None:
      if app.cursor > app.widgets.len - 1: app.cursor = 0
      # Skip non-focusable widgets when cycling.
      var hops = 0
      while hops < app.widgets.len and not app.widgets[app.cursor].focusable:
        inc app.cursor
        if app.cursor > app.widgets.len - 1: app.cursor = 0
        inc hops
      let w = app.widgets[app.cursor]
      w.safeCall "onControl":
        w.onControl()
      inc app.cursor
    of Key.Mouse:
      if app.mouseEnabled:
        let mouseInfo = getMouse()
        if mouseInfo.button == MouseButton.mbLeft and mouseInfo.action == MouseButtonAction.mbaPressed:
          for i, widget in app.widgets:
            if widget.visibility and widget.focusable and
               widget.contains(mouseInfo.x, mouseInfo.y):
              app.widgets[app.cursor].focus = false
              app.cursor = i
              app.widgets[app.cursor].focus = true
              break
        for widget in app.widgets:
          if widget.visibility and widget.contains(mouseInfo.x, mouseInfo.y):
            widget.safeCall "onMouseEvent":
              widget.onMouseEvent(mouseInfo)
    else: discard
    
    sleep(app.rpms)



proc run*(app: var TerminalApp, nonBlocking=false) =
  if nonBlocking:
    # running non blocking
    app.go()
  else:
    # run and hold on one control 
    app.hold()
  illwillDeinit()