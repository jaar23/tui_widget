import illwill, os, strutils, std/terminal
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
  widget/textarea_wg

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
    autoResize: bool = false # not implement yet
    tb: TerminalBuffer
    widgets: seq[ref BaseWidget]
    refreshWaitTime: int = 20


var bgChannel = newChan[Task]() 

proc newTerminalApp*(tb: TerminalBuffer = newTerminalBuffer(terminalWidth(),
                     terminalHeight()), title: string = "", border: bool = false,
                     bgColor = illwill.bgNone, fgColor = illwill.fgWhite,
                     refreshWaitTime: int = 20): TerminalApp =
  result = TerminalApp(
    width: terminalWidth(),
    height: terminalHeight(),
    title: title,
    border: border,
    bgColor: bgColor,
    fgColor: fgColor,
    refreshWaitTime: refreshWaitTime,
    widgets: newSeq[ref BaseWidget](),
    tb: tb
  )


proc terminalBuffer*(app: var TerminalApp): var TerminalBuffer =
  app.tb


proc addWidget*(app: var TerminalApp, widget: ref BaseWidget) =
  widget.tb = app.terminalBuffer
  if widget.groups:
    widget.setChildTb(app.terminalBuffer)
  widget.refreshWaitTime = app.refreshWaitTime
  app.widgets.add(widget)


proc widgets*(app: var TerminalApp): seq[ref BaseWidget] =
  app.widgets


proc requiredSize*(app: var TerminalApp): (int, int, int) =
  var w, h: int = 0
  for wg in app.widgets:
    if wg.width > w:
      w = wg.width
    if wg.height > h:
      h = wg.height
  return (w, h, w * h)


proc render*(app: var TerminalApp) =
  app.tb.fill(0, 0, app.width, app.height, app.bgColor, app.fgColor)
  for w in app.widgets:
    if w.visibility:
      try:
        w.rerender()
      except:
        w.onError("E01")


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


proc resize(app: var TerminalApp) =
  # resize
  let windWidth = terminalWidth()
  let windHeight = terminalHeight()
  if windWidth != app.width or windHeight != app.height:
    app.width = windWidth
    app.height = windHeight
    sleep(2000)
    app.tb.clear()
    app.render()


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
  if app.border: app.tb.drawRect(0, 0, w + 1, h + 1)
  let title: string = ansiStyleCode(styleBright) & app.title
  if app.title != "": app.tb.write(2, 0, title)

  while true:
    app.render()
    var key = getKeyWithTimeout(app.refreshWaitTime)
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
    app.tb.clear()
    if app.border: app.tb.drawRect(0, 0, w + 1, h + 1)
    let title: string = ansiStyleCode(styleBright) & app.title
    if app.title != "": app.tb.write(2, 0, title)
    app.render()
    var key = getKeyWithTimeout(app.refreshWaitTime)
    case key
    of Key.Tab, Key.None:
      try:
        if app.cursor > app.widgets.len - 1: app.cursor = 0
        app.widgets[app.cursor].onControl()
      except:
        app.widgets[app.cursor].onError("E01")
      inc app.cursor
    of Key.ShiftR:
      app.tb.clear()
      app.tb.display()
    else: discard
    
    sleep(app.refreshWaitTime)



proc run*(app: var TerminalApp, nonBlocking=false) =
  if nonBlocking:
    # running non blocking
    app.go()
  else:
    # run and hold on one control 
    app.hold()
