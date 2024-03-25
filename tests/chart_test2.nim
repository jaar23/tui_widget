import tui_widget
import illwill
import std/random

var ydata = newSeq[float64]()
var xs = newSeq[string]()

for i in 0..66:
  ydata.add(rand(30..100).toFloat())
  xs.add($i)


let xaxis2 = newAxis(title = "Thread", header=xs)
let yaxis2 = newAxis(title="y in mil", data=ydata)

var chart = newChart(1, 1, consoleWidth(), consoleHeight(), border=true, xAxis=xaxis2, yAxis=yaxis2)

var app = newTerminalApp(title = "ktop")

app.addWidget(chart)

app.run()
