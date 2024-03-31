import illwill, os, strutils, std/terminal, std/colors
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
  widget/gauge_wg


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
    refreshWaitTime: int = 50


proc newTerminalApp*(tb: TerminalBuffer = newTerminalBuffer(terminalWidth(),
                     terminalHeight()), title: string = "", border: bool = true,
                     refreshWaitTime: int = 50): TerminalApp =
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
  app.widgets.add(widget)


proc widgets*(app: var TerminalApp): seq[ref BaseWidget] =
  app.widgets


proc render*(app: var TerminalApp) =
  for w in app.widgets:
    if w.visibility:
      w.rerender()


proc requiredSize*(app: var TerminalApp): (int, int, int) =
  var w, h: int = 0
  for wg in app.widgets:
    if wg.width > w:
      w = wg.width
    if wg.height > h:
      h = wg.height
  return (w, h, w * h)


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
    quit(0)

  while true:
    app.tb.clear()
    sleep(100)
    #app.tb.setForegroundColor(fgRed)
    #app.tb.setBackgroundColor(bgWhite)
    if app.border: app.tb.drawRect(0, 0, w + 1, h + 1)
    let title: string = ansiStyleCode(styleBright) & app.title
    if app.title != "": app.tb.write(2, 0, title)
    app.render()
    var key = getKey()
    case key
    of Key.Tab, Key.None:
      if app.cursor > app.widgets.len - 1: app.cursor = 0
      app.widgets[app.cursor].onControl()
      inc app.cursor
    else: discard

    #app.tb.display()
    sleep(app.refreshWaitTime)


