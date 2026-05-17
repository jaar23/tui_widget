import tui_widget

# ---------------------------------------------------------------------------
# Mouse support demo
#
# Run with: nim c -r --threads:on tests/mouse_test.nim
#
# Mouse actions:
#   Left-click any widget     shifts keyboard focus to it
#   Left-click button         fires the action, updates label
#   Left-click checkbox       toggles checked state
#   Left-click dropdown       expands, selects and collapses
#   Scroll wheel on listview  scrolls without needing focus
# ---------------------------------------------------------------------------

var app = newTerminalApp(title = "Mouse Demo  [Tab: next  Ctrl-C: quit]",
                         border = true, rpms = 20)
app.enableMouse()

let col1End  = consoleWidth() div 2
let col2Start = col1End + 1
let row1End  = 4
let row2Start = 5
let row2End  = consoleHeight() div 2
let row3Start = row2End + 1

# -- Button ------------------------------------------------------------------

var clickCount = 0
var btn = newButton(1, 1, col1End, row1End,
                    label = "Click Me  [Enter / left-click]", id = "btn")

var btnStatus = newLabel(1, row2Start, col1End, row2Start + 2,
                         id = "btnStatus", text = "No clicks yet", border = true)

btn.onEnter = proc(b: Button, args: varargs[string]) =
  inc clickCount
  b.label = "Clicked " & $clickCount & (if clickCount == 1: " time" else: " times")
  btnStatus.text = "Last action: button click #" & $clickCount
  btnStatus.render()

# -- Checkboxes --------------------------------------------------------------

let cbMid = (col1End + 1) div 2
var cb1 = newCheckbox(1, row2Start + 3, cbMid, row2Start + 5,
                      id = "cb1", label = "Option A")
var cb2 = newCheckbox(cbMid + 1, row2Start + 3, col1End, row2Start + 5,
                      id = "cb2", label = "Option B")

var cbStatus = newLabel(1, row2Start + 6, col1End, row2Start + 8,
                        id = "cbStatus", text = "A: OFF   B: OFF", border = true)

let updateCbStatus = proc() =
  cbStatus.text = "A: " & (if cb1.checked: "ON " else: "OFF") &
                  "   B: " & (if cb2.checked: "ON " else: "OFF")
  cbStatus.render()

cb1.onEnter = proc(cb: Checkbox, state: bool) = updateCbStatus()
cb2.onEnter = proc(cb: Checkbox, state: bool) = updateCbStatus()

# -- Dropdown ----------------------------------------------------------------

var dd = newDropdown(1, row3Start, col1End, row3Start + 3,
                     id = "dd",
                     placeholder = "Left-click or [Enter] to open",
                     options = @[
                       newDropdownOption("Nim",    "nim"),
                       newDropdownOption("Python", "python"),
                       newDropdownOption("Go",     "go"),
                       newDropdownOption("Rust",   "rust"),
                     ],
                     maxVisibleOptions = 4,
                     border = true)

var ddStatus = newLabel(1, row3Start + 4, col1End, row3Start + 6,
                        id = "ddStatus", text = "No selection yet", border = true)

dd.onSelect = proc(d: Dropdown, args: varargs[string]) =
  ddStatus.text = "Selected: " & (if args.len > 1: args[1] else: "?") &
                  "  (value=" & (if args.len > 0: args[0] else: "?") & ")"
  ddStatus.render()

# -- ListView (right column) ------------------------------------------------

var lvRows: seq[ListRow]
for i in 1..20:
  lvRows.add(newListRow(i - 1, "Item " & $i, "item" & $i))

var lv = newListView(col2Start, 1, consoleWidth(), row2End,
                     id = "lv",
                     title = "Scroll wheel or [Up]/[Down] to navigate",
                     rows = lvRows,
                     border = true,
                     mouseEnabled = true)

var lvStatus = newLabel(col2Start, row2End + 1, consoleWidth(), row2End + 3,
                        id = "lvStatus", text = "Nothing selected yet", border = true)

lv.onEnter = proc(l: ListView, args: varargs[string]) =
  let val = if args.len > 0: args[0] else: "?"
  lvStatus.text = "Selected: " & val & "  (scroll wheel navigates, [Enter] selects)"
  lvStatus.render()

# -- Wire up -----------------------------------------------------------------

app.addWidget(btn)
app.addWidget(btnStatus)
app.addWidget(cb1)
app.addWidget(cb2)
app.addWidget(cbStatus)
app.addWidget(dd)
app.addWidget(ddStatus)
app.addWidget(lv)
app.addWidget(lvStatus)

app.run(nonBlocking = true)
