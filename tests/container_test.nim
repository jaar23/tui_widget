import tui_widget

var ctr = newContainer(15, 15, 45, 30, title="container", bgColor=bgWhite, fgColor=fgBlack)

var input = newInputBox(2, 2, 0.85, 0.25, title="input")

var display = newDisplay(2, 5, 0.5, 0.25, title="display", text="hello container\nthere..")

var display2 = newDisplay(2, 5, 0.5, 0.25, title="display", text="hello container\nthere..")

ctr.add(input, 1.0, 0.25)

ctr.add(display, 0.5, 0.75)

ctr.add(display2, 0.5, 0.75)

input.value = $input.posX & "-" & $input.posY & "-" & $input.width & "-" & $input.height

var app = newTerminalApp(title="container test")

app.addWidget(ctr)

app.run()

              
