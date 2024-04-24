import tui_widget
import illwill, options, std/enumerate

var inputBox = newInputBox(id="input")
inputBox.border = true
inputBox.title = "input"


var display = newDisplay("board")
display.statusbar = true
display.enableHelp = true
display.title = "board"
display.text = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Cras quis accumsan lectus. Duis vitae rhoncus ex, 
at rhoncus diam. Aenean rutrum non tellus vel finibus. In hac habitasse platea dictumst. Curabitur feugiat, 
nibh laoreet tincidunt gravida, mi ante sagittis urna, sed ultricies lectus enim et libero. Nam tristique sem 
tempor lectus dignissim, ac imperdiet risus auctor. Aliquam erat volutpat. In iaculis laoreet ultrices. 
Curabitur pellentesque eros nec erat mattis, ac semper tortor facilisis.
Morbi quis magna laoreet, lacinia libero sed, lobortis felis. Donec vitae posuere ipsum. Curabitur volutpat 
vel sem et fringilla. Quisque porttitor, urna nec tincidunt finibus, urna magna finibus ligula, sed cursus 
libero mauris ut nisi. Nulla erat nisl, blandit non tincidunt eget, bibendum at nisi. Vestibulum imperdiet 
nulla eu pharetra dictum. Duis vel pretium neque. Nam ac malesuada augue, quis varius purus. Vestibulum sit 
amet sagittis nibh. Proin in ultricies elit. Donec euismod luctus turpis, a ultrices dui dignissim eget. 
In mauris dui, sagittis et tortor sed, cursus sodales lectus. Aenean mollis velit nec purus blandit, eu 
scelerisque velit venenatis. Cras ipsum urna, hendrerit volutpat ullamcorper a, vulputate et neque.
"""
display.bg(bgWhite)
display.fg(fgBlack)

var button = newButton(id="btn")
button.label = "Confirm"

var checkbox = newCheckbox(id="ch1")
checkbox.title = "done"
checkbox.label = "yes" 
checkbox.value = "y"

var checkbox2 = newCheckbox(id="ch2")
checkbox2.title = "accept"
checkbox2.label = "yes" 
checkbox2.value = "y" 
checkbox2.checkMark = '*'
checkbox2.bg(bgWhite)
checkbox2.fg(fgBlack)

var table = newTable(id="leadtable")
table.title = "table"
table.selectionStyle = Highlight
table.loadFromCsv("./leads-1000.csv", withHeader=true, withIndex=true)
table.border = false
table.statusbar = true
table.bg(bgWhite)
table.fg(fgBlack)

var progress = newProgressBar(id="pb1")

button.onEnter = proc (btn: Button, args: varargs[string]) =
  progress.update(5.0)

var list = newSeq[ListRow]()

const keys = {Key.A..Key.Z}
for i, key in enumerate(keys):
  var listRow = newListRow(i, $key, $key)
  list.add(listRow)

var listview = newListView(id="list")
listView.rows = list
listView.title = "list" 
listView.bg(bgBlue) 
listView.selectionStyle = HighlightArrow

var label = newLabel(id="lb1")
label.text = "hello tui" 
label.bg(bgWhite) 
label.fg(fgBlack)
label.align = Center


listView.onEnter = proc(lv: ListView, args: varargs[string]) =
  label.text = args[0]


var app = newTerminalApp(title="octo")
# adding widget and assign width and height
# based on percentage. 
app.addWidget(inputBox, 1.0, 2)
app.addWidget(display, 1.0, 0.2)
app.addWidget(checkbox, 0.5, 0.1)
app.addWidget(checkbox2, 0.5, 0.1)
app.addWidget(button, 1.0, 2)
app.addWidget(table, 1.0, 0.2)
app.addWidget(progress, 0.8, 2)
app.addWidget(listView, 1.0, 0.2)
app.addWidget(label, 0.2, 1)

app.run(nonBlocking=true)

