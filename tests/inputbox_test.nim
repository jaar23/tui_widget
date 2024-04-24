import tui_widget
import illwill, options

var inputBox = newInputBox(1, 1, consoleWidth(), 3, "message")
var display = newDisplay(1, 4, consoleWidth(), 16, "board") 

let enterEv = proc(ib: InputBox, arg: varargs[string]) =
  display.add(inputBox.value & "\n")
  inputBox.value("")

inputBox.onEnter = enterEv

inputBox.on(Key.CtrlD, enterEv)

var app = newTerminalApp(title="tui widget")

app.addWidget(inputBox)
app.addWidget(display)
app.run()
