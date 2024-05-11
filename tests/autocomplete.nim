import tui_widget, std/enumerate, unicode

let autocomplete = proc(t: TextArea, args: varargs[string]) =
  # provide the logic on coming up witht the autocomplete list
  var suggestion = @[
    "A1",
    "A2",
    "A3",
    "B1",
    "B2",
    "B3"
  ]
  var completionList = newSeq[Completion]()
  for s in suggestion:
    completionList.add(Completion(icon: "-", value: s, description: "suggestion list"))
  t.autocompleteList = completionList
  

var textarea = newTextArea(1, 1, consoleWidth(), 22, title="textarea", statusbar=true, enableAutocomplete=true)

textarea.on("autocomplete", autocomplete)

var app = newTerminalApp(title="octo")

app.addWidget(textarea)

app.run()
