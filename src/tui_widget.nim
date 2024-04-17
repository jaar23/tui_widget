import illwill, os, strutils, std/terminal
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
import malebolgia, times, std/tasks, sequtils, macros
import threading/channels

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
    title: string
    cursor: int = 0
    fullscreen: bool = true
    border: bool = true
    autoResize: bool = false # not implement yet
    tb: TerminalBuffer
    widgets: seq[ref BaseWidget]
    refreshWaitTime: int = 20


  # WidgetEvent* = object
  #   widgetId*: int
  #   widgetEvent*: string
  #   args*: seq[string]
  #   error: string
  #

var backgroundChannel = newChan[Task]()
var widgetChannel = newChan[WidgetEvent]()

export backgroundChannel
export widgetChannel

proc newTerminalApp*(tb: TerminalBuffer = newTerminalBuffer(terminalWidth(),
                     terminalHeight()), title: string = "", border: bool = true,
                     refreshWaitTime: int = 20): TerminalApp =
  result = TerminalApp(
    title: title,
    border: border,
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
  if widget.id == 0:
    widget.id = app.widgets.len + 1
  app.widgets.add(widget)


proc widgets*(app: var TerminalApp): seq[ref BaseWidget] =
  app.widgets


proc render*(app: var TerminalApp) =
  for w in app.widgets:
    if w.visibility:
      try:
        w.rerender()
      except:
        w.onError("E01")


proc requiredSize*(app: var TerminalApp): (int, int, int) =
  var w, h: int = 0
  for wg in app.widgets:
    if wg.width > w:
      w = wg.width
    if wg.height > h:
      h = wg.height
  return (w, h, w * h)


proc widgetInit(app: var TerminalApp) =
  for w in app.widgets:
    w.illwillInit = true

# background thread works
# proc backgroundTasks() =
#   let f = open("background.txt", fmWrite)
#   while true:
#     f.write(now().getDateStr() & "\n")
#     f.flushFile()
#     sleep(2000)
#   defer:
#     f.write("closed")
#     f.close()

proc backgroundTasks() {.thread.} =
  while true:
    try:
      let bgtask = backgroundChannel.recv()
      bgtask.invoke()
      #let f = open("background.txt", fmWrite)
      #f.write("background called\n")
    except:
      #let f = open("background.txt", fmWrite)
      #f.write(getCurrentExceptionMsg())
      echo getCurrentExceptionMsg()


proc eventNotification(app: var TerminalApp) =
  var widgetEv: WidgetEvent
  let recved = widgetChannel.tryRecv(widgetEv)
  # let f = open("background.txt", fmAppend)
  if not recved: return
  #   f.write("nothing received\n")
  #  return
  # f.write("got something from widget channel\n")
  try:
    for w in app.widgets:
      if w.id == widgetEv.widgetId:
        w.channel.send widgetEv
        # f.write("found the widget!!")
        #w.call(widgetEv.widgetEvent, widgetEv.args)
        #w.rerender()
    # let w = app.widgets.filter(proc (x: ref BaseWidget): bool = x.id == widgetEv.widgetId)
    # if w.len > 0:
    #   echo "widget found"
    #   w[0].call(widgetEv.widgetEvent, widgetEv.args)
    # else:
    #   echo "widget not founddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  except:
    #f.write(getCurrentExceptionMsg())
    echo getCurrentExceptionMsg()
  #app.render()
  #app.tb.display()


proc run*(app: var TerminalApp) =
  proc exitProc() {.noconv.} =
    illwillDeinit()
    showCursor()
    quit(0)

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
  
  # background task
  var threadpool = createMaster()
  threadpool.spawn backgroundTasks()

  while true:
    app.tb.clear()
    if app.border: app.tb.drawRect(0, 0, w + 1, h + 1)
    
    let title: string = ansiStyleCode(styleBright) & app.title
    if app.title != "": app.tb.write(2, 0, title)


    app.render()
    #app.eventNotification()
    
    var key = getKeyWithTimeout(app.refreshWaitTime)
    case key
    of Key.Tab, Key.None:
      try:
        if app.cursor > app.widgets.len - 1: app.cursor = 0
        app.widgets[app.cursor].onControl()
      except:
        app.widgets[app.cursor].onError("E01")
      inc app.cursor
    else: discard
    #sleep(app.refreshWaitTime)



proc notifyWidget*(widgetId: int, widgetEvent: string, args: varargs[string]) =
  let arguments = args.toSeq()
  widgetChannel.send(WidgetEvent(
    widgetId: widgetId,
    widgetEvent: widgetEvent,
    args: arguments,
    error: ""
  ))

proc notifyWidget*(widget: ptr BaseWidget, widgetEvent: string, args: varargs[string]) =
  let arguments = args.toSeq()
  widget[].channel.send(WidgetEvent(
    widgetId: 0,
    widgetEvent: widgetEvent,
    args: arguments,
    error: "",
  ))


proc runInBackground*(task: sink Task) =
  backgroundChannel.send(task)
