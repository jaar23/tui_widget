import tui_widget
import illwill, options, std/enumerate, math, random, strutils

# Create sample data for different chart types
var sampleData1: ChartData = @[]
for i in 0..9:
  sampleData1.add(DataPoint(label: $i, value: sin(i.float * 0.5) * 50 + 50))

var sampleData2: ChartData = @[]
let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
for i, month in enumerate(months):
  sampleData2.add(DataPoint(label: month, value: rand(100.0)))

var sampleData3: ChartData = @[]
let products = ["A", "B", "C", "D", "E"]
for i, product in enumerate(products):
  sampleData3.add(DataPoint(label: product, value: rand(80.0) + 20))

# Create chart widgets
var lineChart = newChart(id="linechart")
lineChart.border = true
lineChart.title = "Line Chart - Sine Wave"
lineChart.chartType = LineChart
lineChart.setData(sampleData1)
lineChart.showGrid = true
lineChart.showLabels = true

var barChart = newChart(id="barchart") 
barChart.border = true
barChart.title = "Bar Chart - Monthly Sales"
barChart.chartType = BarChart
barChart.setData(sampleData2)
barChart.showGrid = false
barChart.showLabels = true

var productChart = newChart(id="productchart")
productChart.border = true
productChart.title = "Product Performance"
productChart.chartType = BarChart
productChart.setData(sampleData3)
productChart.showValues = true

# Create control widgets
var button1 = newButton(id="btn1")
button1.label = "Add Random Data"

var button2 = newButton(id="btn2")  
button2.label = "Clear Charts"

var button3 = newButton(id="btn3")
button3.label = "Generate New Data"

var display = newDisplay(id="info")
display.title = "Chart Info"
display.text = """
Chart Widget Demo

Controls:
- [T] Toggle chart type (Line/Bar)
- [G] Toggle grid display
- [L] Toggle labels
- [V] Toggle values
- [?] Help

Use buttons to:
- Add random data points
- Clear all charts
- Generate completely new datasets

Enter numeric values in input box and press Enter to add data points.
"""

var progress = newProgressBar(id="progress")

# Event handlers
button1.onEnter = proc (btn: Button, args: varargs[string]) =
  let newPoint = DataPoint(label: "R" & $rand(99), value: rand(100.0))
  lineChart.addDataPoint(newPoint.label, newPoint.value)
  barChart.addDataPoint(newPoint.label, newPoint.value)
  productChart.addDataPoint(newPoint.label, newPoint.value)
  progress.update(10.0)

button2.onEnter = proc (btn: Button, args: varargs[string]) =
  lineChart.clearData()
  barChart.clearData() 
  productChart.clearData()
  progress.reset()

button3.onEnter = proc (btn: Button, args: varargs[string]) =
  # Generate new sine wave data
  var newData1: ChartData = @[]
  for i in 0..12:
    newData1.add(DataPoint(label: $i, value: cos(i.float * 0.3) * 30 + 60))
  lineChart.setData(newData1)
  
  # Generate new random sales data
  var newData2: ChartData = @[]
  let quarters = ["Q1", "Q2", "Q3", "Q4"]
  for i, quarter in enumerate(quarters):
    newData2.add(DataPoint(label: quarter, value: rand(150.0) + 50))
  barChart.setData(newData2)
  
  # Generate new product data
  var newData3: ChartData = @[]
  let categories = ["Cat1", "Cat2", "Cat3", "Cat4", "Cat5", "Cat6"]
  for i, category in enumerate(categories):
    newData3.add(DataPoint(label: category, value: rand(120.0) + 10))
  productChart.setData(newData3)
  
  progress.update(25.0)

var inputBox = newInputBox(id="input")
inputBox.border = true
inputBox.title = "Add Data Point (enter number)"

# InputBox onEnter event - the InputBox automatically passes its current value
inputBox.onEnter = proc (ib: InputBox, args: varargs[string]) =
  let inputValue = ib.value  # Get the current value from the InputBox
  if inputValue != "":
    try:
      let value = parseFloat(inputValue)
      let label = "U" & $rand(99)
      lineChart.addDataPoint(label, value)
      barChart.addDataPoint(label, value)
      productChart.addDataPoint(label, value)
      ib.value = ""  # Clear input box
      progress.update(5.0)
    except:
      # Invalid number, ignore silently or could add error feedback
      ib.value = ""  # Clear invalid input

var app = newTerminalApp(title="Chart Widget Demo")

# Layout: 
# - Top row: info display (left) and input box (right)
# - Middle row: three charts side by side
# - Bottom row: control buttons and progress bar

# Info and input
app.addWidget(display, 0.6, 0.25)
app.addWidget(inputBox, 0.4, 0.08)

# Three charts in a row  
app.addWidget(lineChart, 0.33, 0.4)
app.addWidget(barChart, 0.33, 0.4)
app.addWidget(productChart, 0.34, 0.4)

# Control buttons
app.addWidget(button1, 0.25, 0.08)
app.addWidget(button2, 0.25, 0.08) 
app.addWidget(button3, 0.25, 0.08)
app.addWidget(progress, 0.25, 0.08)

app.run()