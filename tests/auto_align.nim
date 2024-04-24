import tui_widget
import illwill, options

var inputBox = newInputBox(1, 1, consoleWidth(), 3, "tui widget", bgColor=bgBlue)

var display = newDisplay(1, 4, consoleWidth(), 16, "board", enableHelp=true) 

var text = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Cras quis accumsan lectus. Duis vitae rhoncus ex, at rhoncus diam. Aenean rutrum non tellus vel finibus. In hac habitasse platea dictumst. Curabitur feugiat, nibh laoreet tincidunt gravida, mi ante sagittis urna, sed ultricies lectus enim et libero. Nam tristique sem tempor lectus dignissim, ac imperdiet risus auctor. Aliquam erat volutpat. In iaculis laoreet ultrices. Curabitur pellentesque eros nec erat mattis, ac semper tortor facilisis.
Morbi quis magna laoreet, lacinia libero sed, lobortis felis. Donec vitae posuere ipsum. Curabitur volutpat vel sem et fringilla. Quisque porttitor, urna nec tincidunt finibus, urna magna finibus ligula, sed cursus libero mauris ut nisi. Nulla erat nisl, blandit non tincidunt eget, bibendum at nisi. Vestibulum imperdiet nulla eu pharetra dictum. Duis vel pretium neque. Nam ac malesuada augue, quis varius purus. Vestibulum sit amet sagittis nibh. Proin in ultricies elit. Donec euismod luctus turpis, a ultrices dui dignissim eget. In mauris dui, sagittis et tortor sed, cursus sodales lectus. Aenean mollis velit nec purus blandit, eu scelerisque velit venenatis. Cras ipsum urna, hendrerit volutpat ullamcorper a, vulputate et neque.
"""

display.add(text & text)

var button = newButton(1, 20, 20, 22, label="Confirm")

var checkbox = newCheckbox(1, 17, 20, 19, title="done", label="yes", value="y")

var checkbox2 = newCheckbox(21, 17, 40, 19, title="accept", label="yes", value="y", checkMark='*')

var table = newTable(1, 23, consoleWidth(), 33, title="table", selectionStyle=Highlight)

table.loadFromCsv("./leads-1000.csv", withHeader=true, withIndex=true)

var progress = newProgressBar(1, 35, consoleWidth(), 37, percent=0.0)

let enterEv = proc(btn: Button, args: varargs[string]) =
  progress.update(5.0)

button.onEnter = enterEv

var list = newSeq[ref ListRow]()
var i = 0
const keys = {Key.A..Key.Z}
var listRow = newListRow(0, "rhoncus feugiat.", "ttt", align=Center)
list.add(listRow)
for key in keys:
  var listRow = newListRow(i, $key, $key)
  list.add(listRow)

var label = newLabel(1, 50, 20, 50, "hello tui", bgColor=bgWhite, fgColor=fgBlack, align=Center)

let selectEv = proc(lv: ref ListView, args: varargs[string]) =
  label.text = args[0]


var listview = newListView(1, 38, consoleWidth(), 48, rows=list, title="list", bgColor=bgBlue, selectionStyle=HighlightArrow)

listView.onEnter = selectEv


var app = newTerminalApp(title="octo")

app.addWidget(inputBox, 1.0, 2)
app.addWidget(display, 1.0, 0.2)
app.addWidget(checkbox, 0.5, 0.1)
app.addWidget(checkbox2, 0.5, 0.1)
app.addWidget(button, 1.0, 2)
app.addWidget(table, 1.0, 0.2)
app.addWidget(label, 0.2, 2)
app.addWidget(progress, 0.8, 2)
app.addWidget(listView, 1.0, 0.2)
app.run()

