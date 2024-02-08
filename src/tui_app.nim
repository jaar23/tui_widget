import widget/base_wg, illwill, os

type
  TerminalApp* = object
    title: string
    cursor: int = 0
    fullscreen: bool = true
    tb: TerminalBuffer
    widgets: seq[ref BaseWidget]
    

proc newTerminalApp*(tb: TerminalBuffer = newTerminalBuffer(terminalWidth(), terminalHeight()),
                     title: string = ""): TerminalApp =
  result = TerminalApp(
    title: title,
    widgets: newSeq[ref BaseWidget](),
    tb: tb
  )


proc terminalBuffer*(app: var TerminalApp): var TerminalBuffer = app.tb
  

proc addWidget*(app: var TerminalApp, widget: ref BaseWidget) =
  widget.tb = app.terminalBuffer
  app.widgets.add(widget)


proc widget*(app: var TerminalApp): seq[ref BaseWidget] = app.widgets


proc render*(app: var TerminalApp) =
  for w in app.widgets:
    w.render()


proc run*(app: var TerminalApp) =
  proc exitProc() {.noconv.} =                                                                                                                                                                                                               
    illwillDeinit()                                                                                                                                                                                                                          
    showCursor()
    quit(0)


  illwillInit(fullscreen=true)
  setControlCHook(exitProc)
  hideCursor()
  
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

