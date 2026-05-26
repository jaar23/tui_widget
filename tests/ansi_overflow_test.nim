## Interactive test: render styled (ANSI) text in Display + ListView
## and verify nothing bleeds past the right border.
##
## Run with:
##   nim c -r --threads:on tests/ansi_overflow_test.nim
##
## Press Tab to cycle widgets, Esc to quit.

import ../src/tui_widget

const styled = "\e[31mhello world this is styled red text\e[0m followed by plain text that keeps going past the visible width of forty cells"

var app = newTerminalApp(title = "ANSI overflow test")

var dp = newDisplay(1, 1, 40, 8, id = "dp", title = "display (styled)",
                    text = styled)

var lv = newListView(1, 10, 40, 18, id = "lv", title = "listview-plain",
                     rows = @[
                       newListRow(0, styled, "v1"),
                       newListRow(1, "\e[32mgreen styled row\e[0m", "v2"),
                       newListRow(2, "normal row, no styling", "v3"),
                     ])

var lvo = newListView(1, 20, 40, 28, id = "lvo", title = "listview-overlay",
                      rows = @[
                        newListRow(0, styled, "v1"),
                        newListRow(1, "\e[34mblue styled row in overlay\e[0m", "v2"),
                        newListRow(2, "normal overlay row", "v3"),
                      ])
lvo.enableTextOverlay()

app.addWidget(dp)
app.addWidget(lv)
app.addWidget(lvo)
app.run()
