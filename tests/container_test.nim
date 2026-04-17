import tui_widget

# ---------------------------------------------------------------------------
# Popup container demo
#
# Main screen has an info display and an "Open Popup" button.
# Pressing Enter on the button opens a container popup with:
#   - two InputBox widgets (name, message)
#   - a Display showing submitted values
#
# Inside the popup:
#   [Tab]  - cycle to next child widget
#   [Esc]  - close the popup
# ---------------------------------------------------------------------------

var app = newTerminalApp(title="container test")

# -- popup and its children -------------------------------------------------

var popup = newContainer(5, 3, consoleWidth() - 10, consoleHeight() - 6,
                         title=" container popup  [Tab: next  Esc: close] ",
                         bgColor=bgNone, fgColor=fgWhite)

var nameInput = newInputBox(1, 1, 1.0, 0.2, title="name")
var msgInput  = newInputBox(1, 1, 1.0, 0.2, title="message")
var output    = newDisplay(1, 1, 1.0, 0.6, title="submitted values")

# add() lays out children proportionally inside the container
popup.add(nameInput, 1.0, 0.2)
popup.add(msgInput,  1.0, 0.2)
popup.add(output,    1.0, 0.6)

let nameEnter = proc(ib: InputBox, args: varargs[string]) =
  output.add("name: " & ib.value() & "\n")
  ib.value = ""

let msgEnter = proc(ib: InputBox, args: varargs[string]) =
  output.add("msg:  " & ib.value() & "\n")
  ib.value = ""

nameInput.onEnter = nameEnter
msgInput.onEnter  = msgEnter

# -- main screen ------------------------------------------------------------

var info = newDisplay(1, 1, consoleWidth(), consoleHeight() - 4,
                      title="main screen",
                      text="Welcome to the container test.\n\n" &
                           "  [Tab]    navigate between widgets\n" &
                           "  [Enter]  activate / open popup\n\n" &
                           "Press [Enter] on the button below to open the popup.")

var openBtn = newButton(1, consoleHeight() - 3, 20, consoleHeight() - 1,
                        label="Open Popup")

# Button opens the popup: show → onControl (blocks until Esc) → hide
let openEv = proc(btn: Button, args: varargs[string]) =
  popup.show(resetCursors=true)
  popup.onControl()
  popup.hide()

openBtn.onEnter = openEv

# -- wire everything up -----------------------------------------------------

app.addWidget(info)
app.addWidget(openBtn)
# Adding popup to app shares the terminal buffer and rpms;
# popup.hide() ensures it is invisible until the button opens it.
app.addWidget(popup)
popup.hide()

app.run()
