import tui_widget, options, std/random

var app = newTerminalApp(title="octo")

var gauge = newGauge(1, 1, 30, 3)
var btn = newButton(1, 4, 10, 6, "hit!")

let ev: EnterEventProcedure = proc ( _: string) = gauge.set(rand(0..100).toFloat())
btn.onEnter(some(ev))

app.addWidget(gauge)
app.addWidget(btn)

app.run()
