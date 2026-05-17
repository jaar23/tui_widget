import tui_widget

# ---------------------------------------------------------------------------
# Runtime exception-safety demo
#
# Run with: nim c -r --threads:on tests/exception_test.nim
#
# - Click "Throw!" — its onEnter raises; safeCall traps it, the button shows
#   the red [!] error block, and the app keeps running.
# - Click "Safe" — increments a counter normally; proves the loop survived.
# - Tab between widgets — focus shifts cleanly; rerender of the failed
#   widget keeps re-running through safeCall every cycle.
# - exception_test.log captures the same trace via the user-installed
#   onWidgetError hook.
# ---------------------------------------------------------------------------

var app = newTerminalApp(title = "Exception Safety  [Tab cycle  Ctrl-C quit]",
                         border = true, rpms = 20)
app.enableMouse()

app.onWidgetError = proc(widgetId, where, msg, trace: string) =
  try:
    let f = open("exception_test.log", fmAppend)
    f.writeLine("[" & widgetId & "/" & where & "] " & msg)
    if trace.len > 0:
      f.writeLine(trace)
    f.close()
  except CatchableError:
    discard

let col1End = consoleWidth() div 2

var badBtn = newButton(1, 1, col1End, 4,
                      label = "Throw!  (onEnter raises)", id = "bad")
badBtn.onEnter = proc(b: Button, args: varargs[string]) =
  raise newException(ValueError, "intentional boom from " & b.id)

var safeCount = 0
var safeBtn = newButton(col1End + 1, 1, consoleWidth(), 4,
                       label = "Safe  (increments counter)", id = "safe")
var status = newLabel(1, 5, consoleWidth(), 7,
                     id = "status",
                     text = "Click either button to test exception safety.",
                     border = true)
safeBtn.onEnter = proc(b: Button, args: varargs[string]) =
  inc safeCount
  status.text = "Safe button clicked " & $safeCount & " times. " &
                "Bad button errors are logged to exception_test.log."

app.addWidget(badBtn)
app.addWidget(safeBtn)
app.addWidget(status)

app.run(nonBlocking = true)
