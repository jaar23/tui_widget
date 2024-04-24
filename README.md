# tui_widget

Terminal UI widget based on [illwill](https://github.com/johnnovak/illwill/tree/master)

These widget is <b>under development</b>, things might change or break!

** docs work in progress **

### Quick preview

![preview](./docs/images/tui_widget.gif)

It feels like an old school software, let's stick with the keyboard :D, it is navigate by `[tab]` button between widgets.

You can use the widget with illwill or bootstrap with `TerminalApp`.

### Simple Example

```nim
import tui_widget, illwill
# 1
var inputBox = newInputBox(1, 1, consoleWidth(), 3, "message")
# 2
var display = newDisplay(1, 4, consoleWidth(), 16, "display panel") 
# 3
let enterEv = proc(ib: InputBox, arg: varargs[string]) =
  display.add(inputBox.value & "\n")
  inputBox.value("")

inputBox.onEnter = enterEv
# 4
var app = newTerminalApp(title="tui widget")

app.addWidget(inputBox)
app.addWidget(display)
# 5
app.run()
```


### Usage
```shell
git clone https://github.com/jaar23/tui_widget.git

cd tui_widget && nimble install
```

### Doc (WIP)

[Getting Started](./docs/getting-started.md)

[Widgets](./docs/widgets.md)

[Events](./docs/events.md)

[TerminalApp](./docs/terminal-app.md)

### Examples

Refers to tests / examples folder for example.

- basic [example](./tests/tui_test.nim)

- chart [example](./tests/chart_test.nim)
  
  ![chart](./docs/images/chart_test.png)

- gauge [example](./tests/gauge_test.nim)

- display [example](./tests/display_test.nim)

- terminal app and widgets [example](./examples/dir.nim)
  
  ![dir](./examples/dir_demo.png)
  

