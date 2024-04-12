import tui_widget, options, std/random

var app = newTerminalApp(title="octo")

var gauge = newGauge(1, 1, 30, 3)
var btn = newButton(1, 4, 10, 6, "hit!")

# deprecated
#btn.onEnter = proc ( _: string) = gauge.set(rand(0..100).toFloat())


btn.onEnter = proc (btn: ref Button, args: varargs[string]) = 
  gauge.set(rand(0..100).toFloat())

let evtFn = proc (g: ref Button, nums: varargs[string]) =
  gauge.set(rand(0..100).toFloat())

let keyFn = proc (b: ref Button, args: varargs[string]) =
  b.label = "clicked"


btn.on("click", evtFn)
btn.on(Key.C, keyFn)

app.addWidget(gauge)
app.addWidget(btn)

app.run()
