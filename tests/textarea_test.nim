import tui_widget

var textarea = newTextArea(1, 1, consoleWidth(), 5, title="textarea", statusbar=true, enableViMode=true, cursorStyle=Ibeam)

var label = newLabel(1, 6, 40, 6, text="Welcome, Textarea")

var textarea2 = newTextArea(1, 7, consoleWidth(), 16, title="textarea 2", statusbar=true)

var app = newTerminalApp(title="octo", border=true)

app.addWidget(textarea)
app.addWidget(label)
app.addWidget(textarea2)

app.run()
