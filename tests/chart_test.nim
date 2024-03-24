import tui_widget
import illwill


let xs = @["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
let ys = @["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
let xdata = @["2", "3", "1", "4", "6", "3", "5", "7", "9", "8"]
let ydata = @["1", "4", "3", "4", "6", "3", "2", "8", "2", "9"]

let xaxis = newAxis(1.0, 10.0, title = "x number", header=xs, data=xdata)
let yaxis = newAxis(1.0, 10.0, title="y number", header=ys, data=ydata)

var chart = newChart(1, 1, 100, 20, border=true, xAxis=xaxis, yAxis=yaxis)

var app = newTerminalApp(title = "ktop")

app.addWidget(chart)

app.run()
