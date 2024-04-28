import illwill, os, strutils, std/terminal, math, options
import malebolgia, threading/channels, std/tasks, sequtils
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
  widget/chart_wg,
  widget/gauge_wg,
  widget/textarea_wg,
  widget/container_wg

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
  chart_wg,
  gauge_wg,
  textarea_wg,
  container_wg,
  illwill

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

  SizeOverflow = object of CatchableError


var bgChannel = newChan[Task]() 

proc newTerminalApp*(tb: TerminalBuffer = newTerminalBuffer(terminalWidth(),
                     terminalHeight()), title: string = "", border: bool = false,
                     bgColor = illwill.bgNone, fgColor = illwill.fgWhite,
                     rpms: int = 20): TerminalApp =
  result = TerminalApp(
    width: terminalWidth(),
    height: terminalHeight(),
    title: title,
    border: border,
    bgColor: bgNone, # disable bgcolor until x
    fgColor: fgWhite, # disable fgcolor until x
    rpms: rpms,
    widgets: newSeq[ref BaseWidget](),
    tb: tb,
    origWidth: terminalWidth(),
    origHeight: terminalHeight()
  )


proc terminalBuffer*(app: var TerminalApp): var TerminalBuffer =
  app.tb


proc addWidget*(app: var TerminalApp, widget: ref BaseWidget) =
  widget.tb = app.terminalBuffer
  if widget.groups:
    widget.setChildTb(app.terminalBuffer)
  widget.rpms = app.rpms
  widget.keepOriginalSize()
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
  widget.resize()
  app.addWidget(widget) 


proc addWidget*(app: var TerminalApp, widget: ref BaseWidget, 
                width, height: WidgetSize ) =
  let w = toConsoleWidth(width)
  let h = toConsoleHeight(height)
  app.addWidget(widget, w, h)


proc addWidget*(app: var TerminalApp, widget: ref BaseWidget, 
                width: int, height: WidgetSize) =
  let h = toConsoleHeight(height)
  app.addWidget(widget, width, h)


proc addWidget*(app: var TerminalApp, widget: ref BaseWidget, 
                width: WidgetSize, height: int = 0) =
  let w = toConsoleWidth(width)
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
  widget.resize()
  app.addWidget(widget) 



proc addWidget*(app: var TerminalApp, 
                widget: ref BaseWidget,
                width: WidgetSize, 
                height: int, 
                offsetLeft, offsetTop, 
                offsetRight, offsetBottom: int) {.raises: [SizeOverflow, Exception].} =
  let w = toConsoleWidth(width)
  #let h = if height == 1: 0 else: height
  app.addWidget(widget, w, height, offsetLeft, offsetTop, offsetRight, offsetBottom)


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
    if w.visibility:
      try:
        w.rerender()
      except:
        w.onError(getCurrentExceptionMsg())


proc widgetInit(app: var TerminalApp) =
  for w in app.widgets:
    w.illwillInit = true


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
    except:
      echo getCurrentExceptionMsg()


proc pollWidgetChannel(app: var TerminalApp) =
  for w in app.widgets:
    w.poll()


proc nonBlockingControl(app: var TerminalApp) =
  if app.widgets[app.cursor].blocking:
    app.widgets[app.cursor].onControl()
    inc app.cursor
  else:
    inc app.cursor
    if app.cursor > app.widgets.len - 1: app.cursor = 0


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
      # resize
      w.resize()
      w.tb = app.tb
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
  illwillInit(fullscreen = app.fullscreen)
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
    else:
      app.widgets[app.cursor].focus = true
      app.widgets[app.cursor].onUpdate(key)

      # poll for changes from other widget
      app.pollWidgetChannel()
      app.render()
    #sleep(app.rpms)


proc hold(app: var TerminalApp) =
  illwillInit(fullscreen = app.fullscreen)
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
      try:
        if app.cursor > app.widgets.len - 1: app.cursor = 0
        app.widgets[app.cursor].onControl()
      except:
        let err = getCurrentException()
        app.widgets[app.cursor].onError(err.getStackTrace())
      inc app.cursor
    else: discard
    
    sleep(app.rpms)



proc run*(app: var TerminalApp, nonBlocking=false) =
  if nonBlocking:
    # running non blocking
    app.go()
  else:
    # run and hold on one control 
    app.hold()
