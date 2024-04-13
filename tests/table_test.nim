import tui_widget

const header = @["container id", "image", "command", "created", "status", "ports", "names"]

const data = [
  @["2f6b5bf05905", "busybox", "sh", "30 minutes ago", "Exited (0) 30 minutes ago", "", "vibrant_raman"],
  @["9d38e6b18ca4", "gcr.io/k8s-minikube/kicbase:v0.0.42", "/usr/local/bin/entr…", "3 months ago", "Exited (130) 3 months ago", "  80", " minikube"],
  @["40383873b8fa", "hello-world", "/hello", "3 months ago", "Exited (0) 3 months ago", "", "zealous_herschel"],
  @["c4140dd8b4bd", "hello-world", "/hello", "3 months ago", "Exited (0) 3 months ago", "", "pensive_hodgkin"]
]

## loading from sequence
var table = newTable(1, 1, consoleWidth(), data.len * 2, title="Docker containers")

table.headerFromArray(header)

table.loadFromSeq(data)

## loading from csv file
var table2 = newTable(1, 10, consoleWidth(), consoleHeight(), title="leads", maxColWidth=20)

table2.loadFromCsv("./leads-1000.csv", withHeader=true, withIndex=true)

var app = newTerminalApp(title="Tables", border=false)

app.addWidget(table)
app.addWidget(table2)
 
app.run()

