import tui_widget

let rawtextWithNextLine = """This is line 
This is line 2 888888kkkk lllll aaaaa
This is line 3
this is line 4
this is line 5
this is line 6
this is line 7
this is line 8
this is line 9
this is line 10
this is line 11
this is line 12
"""

var textWithNextLine = "This is line 1\nThis is line 2\nThis is line 3\n"

var dp1 = newDisplay(1, 1, 30, 10, title="raw text with next line", text=rawtextWithNextLine)

var dp2 = newDisplay(1, 11, 30, 21, title="text with next line", text=textWithNextLine)

var app = newTerminalApp()

app.addWidget(dp1)
app.addWidget(dp2)

app.run()
