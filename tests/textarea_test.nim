import tui_widget

var textarea = newTextArea(1, 1, consoleWidth(), 5, title="textarea", statusbar=true)

var label = newLabel(1, 6, 40, 6, text="Welcome, Textarea")

var app = newTerminalApp(title="octo", border=true)

app.addWidget(textarea)
app.addWidget(label)

app.run()
