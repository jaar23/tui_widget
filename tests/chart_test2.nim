import tui_widget
import std/random

var ydata = newSeq[float64]()
var xs = newSeq[string]()

for i in 0..50:
  ydata.add(rand(0..10000).toFloat())
  xs.add($i)


let yaxis = newAxis(title="y in mil", data=ydata)

var chart = newChart(1, 1, consoleWidth(), consoleHeight(), title="metrics", border=true, axis=yaxis)

var app = newTerminalApp(title = "ktop")

app.addWidget(chart)

app.run()

