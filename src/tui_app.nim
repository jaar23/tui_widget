import widget/base_wg, illwill, os, strutils
import std/terminal
type
  TerminalApp* = object
    title: string
    cursor: int = 0
    fullscreen: bool = true
    autoResize: bool = false
    tb: TerminalBuffer
    widgets: seq[ref BaseWidget]


proc newTerminalApp*(tb: TerminalBuffer = newTerminalBuffer(terminalWidth(),
                    terminalHeight()), title: string = ""): TerminalApp =
  result = TerminalApp(
    title: title,
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
    w.rerender()
    #w.clear()
    #w.render()


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
    app.render()
    var key = getKey()
    case key
    of Key.Tab, Key.None:
      if app.cursor > app.widgets.len - 1: app.cursor = 0
      app.widgets[app.cursor].onControl()
      inc app.cursor
    else: discard

    app.terminalBuffer.display()
    sleep(20)

