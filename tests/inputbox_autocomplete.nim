import tui_widget, std/enumerate, unicode

let autocomplete = proc(ib: InputBox, args: varargs[string]) =
  var suggestion = @[
    "alpha",
    "alphabet",
    "alphanumeric",
    "beta",
    "gamma",
    "delta"
  ]
  var completionList = newSeq[Completion]()
  for s in suggestion:
    completionList.add(Completion(icon: "[P]", value: s, description: "suggestion"))
  ib.autocompleteList = completionList


var inputbox = newInputBox(1, 1, consoleWidth(), 3,
                           title = "inputbox autocomplete",
                           statusbar = true,
                           enableAutocomplete = true)

inputbox.on("autocomplete", autocomplete)

var app = newTerminalApp(title = "octo")

app.addWidget(inputbox)

app.run()
