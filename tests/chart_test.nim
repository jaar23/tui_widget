import tui_widget
import illwill


let xs = @["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14"]
let ys = @["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14"]
let xdata = @[2.0, 3.0, 1.0, 4.0, 6.0, 3.0, 5.0, 7.0, 9.0, 8.0]
let ydata = @[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0]

let xaxis = newAxis(1.0, 10.0, title = "x number", header=xs, data=ydata)
let yaxis = newAxis(1.0, 10.0, title="y number", header=ys, data=ydata)

var chart = newChart(1, 1, 80, 14, border=true, xAxis=xaxis, yAxis=yaxis)

#let xs = @["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14"]
let ydata2 = @[13.0, 2.0, 6.0, 10.0, 15.0, 8.0, 17.0, 19.0, 16.0, 11.0, 18.0, 12.0, 21.0, 20.0]

let xaxis2 = newAxis(title = "x number", header=xs)
let yaxis2 = newAxis(title="y number", data=ydata2)

var chart2 = newChart(1, 26, 100, 52, border=true, title="metrics", xAxis=xaxis2, yAxis=yaxis2)

var app = newTerminalApp(title = "ktop")

app.addWidget(chart)

app.addWidget(chart2)

app.run()
