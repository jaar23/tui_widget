import tui_widget

var lb1 = newLabel(id="lb1")
lb1.text = "hello tui"

var lb2 = newLabel(id="lb2")
lb2.text = "hello tui"
lb2.border = true

var lb3 = newLabel(id="lb3")
lb3.text = "hello tui"
lb3.border = true
lb3.bg(bgRed)

var inputBox = newInputBox(1, 4, consoleWidth(), 6, "message")

var app = newTerminalApp(title="octo")
app.addWidget(lb1, 0.2, 1)
app.addWidget(lb2, 0.2, 1)
app.addWidget(lb3, 0.2, 1)
app.addWidget(inputBox)
app.run()
