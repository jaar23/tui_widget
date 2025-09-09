import tui_widget
import illwill, options, std/enumerate, math, random, strutils
import widget/heatmap_wg

# Create sample heatmap data for different scenarios
proc createSampleHeatmapData1(): (HeatmapData, seq[string], seq[string]) =
  let boroughs = @["BRONX", "BROOKLYN", "MANHATTAN", "QUEENS", "STATEN ISLAND"]
  let years = @["2010", "2011", "2012", "2013", "2014", "2015", "2016", "2017"]
  
  var data = newSeq[seq[float]](boroughs.len)
  for i in 0..<boroughs.len:
    data[i] = newSeq[float](years.len)
    for j in 0..<years.len:
      # Create sample data similar to NYC housing data
      case i:
      of 0: # BRONX
        data[i][j] = 2500.0 + rand(1000.0)
      of 1: # BROOKLYN  
        data[i][j] = 3000.0 + rand(2000.0)
      of 2: # MANHATTAN
        data[i][j] = 2800.0 + rand(1500.0)
      of 3: # QUEENS
        data[i][j] = 1500.0 + rand(800.0)
      of 4: # STATEN ISLAND
        data[i][j] = 800.0 + rand(400.0)
      else:
        data[i][j] = rand(1000.0)
  
  return (data, boroughs, years)

proc createSampleHeatmapData2(): (HeatmapData, seq[string], seq[string]) =
  let months = @["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  let departments = @["Sales", "Marketing", "Engineering", "Support", "HR"]
  
  var data = newSeq[seq[float]](departments.len)
  for i in 0..<departments.len:
    data[i] = newSeq[float](months.len)
    for j in 0..<months.len:
      # Create temperature-like data with seasonal variations
      let baseTemp = sin((j.float * 2 * PI) / 12.0) * 20 + 50
      data[i][j] = baseTemp + rand(15.0) - 7.5
  
  return (data, departments, months)

proc createSampleHeatmapData3(): (HeatmapData, seq[string], seq[string]) =
  let servers = @["Web-01", "Web-02", "DB-01", "DB-02", "Cache-01", "Cache-02"]
  let timeSlots = @["00:00", "04:00", "08:00", "12:00", "16:00", "20:00"]
  
  var data = newSeq[seq[float]](servers.len)
  for i in 0..<servers.len:
    data[i] = newSeq[float](timeSlots.len)
    for j in 0..<timeSlots.len:
      # Simulate CPU usage patterns (higher during business hours)
      let cpuUsage = if j >= 2 and j <= 4: rand(80.0) + 20 else: rand(40.0) + 10
      data[i][j] = cpuUsage
  
  return (data, servers, timeSlots)

# Create heatmap widgets
var (data1, rowLabels1, colLabels1) = createSampleHeatmapData1()
var heatmap1 = newHeatmap(id="heatmap1")
heatmap1.border = true
heatmap1.title = "NYC Housing Data by Borough"
heatmap1.setData(data1, rowLabels1, colLabels1)
heatmap1.colorScheme = RedScale
heatmap1.showGrid = true
heatmap1.showLabels = true
heatmap1.showColorbar = true
heatmap1.cellWidth = 8
heatmap1.cellHeight = 2

var (data2, rowLabels2, colLabels2) = createSampleHeatmapData2()
var heatmap2 = newHeatmap(id="heatmap2")
heatmap2.border = true
heatmap2.title = "Department Performance by Month"
heatmap2.setData(data2, rowLabels2, colLabels2)
heatmap2.colorScheme = BlueScale
heatmap2.showGrid = false
heatmap2.showLabels = true
heatmap2.showColorbar = true
heatmap2.cellWidth = 6
heatmap2.cellHeight = 1

var (data3, rowLabels3, colLabels3) = createSampleHeatmapData3()
var heatmap3 = newHeatmap(id="heatmap3")
heatmap3.border = true
heatmap3.title = "Server CPU Usage by Time"
heatmap3.setData(data3, rowLabels3, colLabels3)
heatmap3.colorScheme = Rainbow
heatmap3.showGrid = true
heatmap3.showLabels = true
heatmap3.showValues = true
heatmap3.showColorbar = true
heatmap3.cellWidth = 7
heatmap3.cellHeight = 1

# Create control widgets
var button1 = newButton(id="btn1")
button1.label = "Generate New Data"

var button2 = newButton(id="btn2")
button2.label = "Toggle Color Schemes"

var button3 = newButton(id="btn3")
button3.label = "Toggle Display Options"

var display = newDisplay(id="info")
display.title = "Heatmap Widget Info"
display.text = """
Heatmap Widget Demo

Features:
- Multiple color schemes: Red, Blue, Green, Gray, Rainbow
- Scrollable for large datasets
- Configurable cell sizes
- Optional grid, labels, values, and colorbar
- Auto-scaling of values

Controls:
- [C] Cycle color scheme
- [G] Toggle grid display
- [L] Toggle labels
- [V] Toggle values display
- [B] Toggle colorbar
- [←→↑↓] Scroll through data
- [?] Help

Three heatmaps showing:
1. NYC Housing Data (Red scale)
2. Department Performance (Blue scale)  
3. Server CPU Usage (Rainbow scale)

Use buttons to:
- Generate completely new random datasets
- Cycle through different color schemes
- Toggle various display options
"""

var progress = newProgressBar(id="progress")

# Event handlers
button1.onEnter = proc (btn: Button, args: varargs[string]) =
  # Generate completely new random data for all heatmaps
  var newData1 = newSeq[seq[float]](5)
  for i in 0..<5:
    newData1[i] = newSeq[float](8)
    for j in 0..<8:
      newData1[i][j] = rand(5000.0) + 500.0
  heatmap1.setData(newData1, rowLabels1, colLabels1)
  
  var newData2 = newSeq[seq[float]](5)
  for i in 0..<5:
    newData2[i] = newSeq[float](12)
    for j in 0..<12:
      newData2[i][j] = rand(100.0)
  heatmap2.setData(newData2, rowLabels2, colLabels2)
  
  var newData3 = newSeq[seq[float]](6)
  for i in 0..<6:
    newData3[i] = newSeq[float](6)
    for j in 0..<6:
      newData3[i][j] = rand(100.0)
  heatmap3.setData(newData3, rowLabels3, colLabels3)
  
  progress.update(30.0)

button2.onEnter = proc (btn: Button, args: varargs[string]) =
  # Cycle color schemes for all heatmaps
  case heatmap1.colorScheme:
  of RedScale: 
    heatmap1.colorScheme = BlueScale
    heatmap2.colorScheme = GreenScale
    heatmap3.colorScheme = GrayScale
  of BlueScale: 
    heatmap1.colorScheme = GreenScale
    heatmap2.colorScheme = GrayScale
    heatmap3.colorScheme = Rainbow
  of GreenScale: 
    heatmap1.colorScheme = GrayScale
    heatmap2.colorScheme = Rainbow
    heatmap3.colorScheme = RedScale
  of GrayScale: 
    heatmap1.colorScheme = Rainbow
    heatmap2.colorScheme = RedScale
    heatmap3.colorScheme = BlueScale
  of Rainbow: 
    heatmap1.colorScheme = RedScale
    heatmap2.colorScheme = BlueScale
    heatmap3.colorScheme = GreenScale
  
  progress.update(15.0)

button3.onEnter = proc (btn: Button, args: varargs[string]) =
  # Toggle various display options
  heatmap1.showGrid = not heatmap1.showGrid
  heatmap1.showValues = not heatmap1.showValues
  
  heatmap2.showGrid = not heatmap2.showGrid
  heatmap2.showValues = not heatmap2.showValues
  
  heatmap3.showGrid = not heatmap3.showGrid
  heatmap3.showColorbar = not heatmap3.showColorbar
  
  progress.update(10.0)

var inputBox = newInputBox(id="input")
inputBox.border = true
inputBox.title = "Set Cell Width (1-10)"

# InputBox to change cell width
inputBox.onEnter = proc (ib: InputBox, args: varargs[string]) =
  let inputValue = ib.value
  if inputValue != "":
    try:
      let cellWidth = parseInt(inputValue)
      if cellWidth >= 1 and cellWidth <= 10:
        heatmap1.cellWidth = cellWidth
        heatmap2.cellWidth = cellWidth
        heatmap3.cellWidth = cellWidth
        progress.update(5.0)
      ib.value = ""
    except:
      ib.value = ""

var app = newTerminalApp(title="Heatmap Widget Demo")

# Layout:
# - Top row: info display (left) and input box (right)
# - Middle row: three heatmaps side by side
# - Bottom row: control buttons and progress bar

# Info and input
app.addWidget(display, 0.6, 0.25)
app.addWidget(inputBox, 0.4, 0.08)

# Three heatmaps in a row
app.addWidget(heatmap1, 0.33, 0.4)
app.addWidget(heatmap2, 0.33, 0.4)
app.addWidget(heatmap3, 0.34, 0.4)

# Control buttons and progress
app.addWidget(button1, 0.25, 0.08)
app.addWidget(button2, 0.25, 0.08)
app.addWidget(button3, 0.25, 0.08)
app.addWidget(progress, 0.25, 0.08)

app.run()