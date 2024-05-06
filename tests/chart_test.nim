import tui_widget

let ydata = @[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0]

let yaxis = newAxis(title="y number", data=ydata)

var chart = newChart(1, 1, 80, 14, border=true, axis=yaxis)

let ydata2 = @[13.0, 2.0, 6.0, 10.0, 15.0, 8.0, 17.0, 19.0, 16.0, 11.0, 18.0, 12.0, 21.0, 20.0]

let yaxis2 = newAxis(title="y number", data=ydata2)

var chart2 = newChart(1, 26, 100, 52, border=true, title="metrics", axis=yaxis2)

var app = newTerminalApp(title = "ktop")

app.addWidget(chart)

app.addWidget(chart2)

app.run()
