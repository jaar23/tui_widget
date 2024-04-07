import tui_widget

var textarea = newTextArea(1, 1, 40, 5, rows=4, cols=40, title="textarea", statusbar=true)

var app = newTerminalApp(title="octo")

app.addWidget(textarea)

app.run()
