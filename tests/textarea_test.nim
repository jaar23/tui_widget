import tui_widget

var textarea = newTextArea(1, 1, consoleWidth(), 10, title="textarea", statusbar=true, enableViMode=true, cursorStyle=Ibeam)

let clearEv = proc (t: ref TextArea, args: varargs[string]) =
  t.value = ""

textarea.on("clear", clearEv)

var label = newLabel(1, 11, 40, 11, text="Welcome, Textarea")

var textarea2 = newTextArea(1, 12, consoleWidth(), 22, title="textarea 2", statusbar=true)

textarea2.value("hello world!")

var app = newTerminalApp(title="octo", border=true)

app.addWidget(textarea)
app.addWidget(label)
app.addWidget(textarea2)

app.run()
