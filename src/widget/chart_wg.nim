import illwill, base_wg, os, strutils, tables, math, sequtils, display_wg
import threading/channels

type
  ChartType* = enum
    LineChart, BarChart, DottedChart
  
  DataPoint* = object
    label*: string
    value*: float
  
  ChartData* = seq[DataPoint]
  
  Chart* = ref ChartObj

  ChartObj* = object of BaseWidget
    data*: ChartData
    chartType*: ChartType
    maxValue*: float
    minValue*: float
    autoScale*: bool
    showGrid*: bool
    showLabels*: bool
    showValues*: bool
    showLegend*: bool
    gridChar*: string
    barChar*: string
    lineChar*: string
    dotChar*: string
    pointChar*: string
    maxVisiblePoints*: int
    scrollOffset*: int
    showLeftIndicator*: bool
    showRightIndicator*: bool
    autoScroll*: bool  # Auto-scroll to show latest data
    events*: Table[string, EventFn[Chart]]
    keyEvents*: Table[Key, EventFn[Chart]]

proc help(ch: Chart, args: varargs[string]): void
proc on*(ch: Chart, key: Key, fn: EventFn[Chart]) {.raises: [EventKeyError].}
proc toggleChartType(ch: Chart, args: varargs[string]): void
proc toggleGrid(ch: Chart, args: varargs[string]): void
proc toggleLabels(ch: Chart, args: varargs[string]): void
proc toggleAutoScroll(ch: Chart, args: varargs[string]): void
proc calculateMaxVisiblePoints*(ch: Chart) : void
proc toggleLegend(ch: Chart, args: varargs[string]): void  # New procedure declaration

# Forbidden keys for chart widget
const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.None, Key.Up,
                          Key.Down, Key.PageUp, Key.PageDown, Key.Home,
                          Key.End}

proc newChart*(px, py, w, h: int, id = "";
               title: string = "", data: ChartData = @[], 
               chartType = LineChart, border: bool = true,
               statusbar = true, enableHelp = true,
               bgColor: BackgroundColor = bgNone,
               fgColor: ForegroundColor = fgWhite,
               maxVisiblePoints = 0,
               tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): Chart =
  let padding = if border: 1 else: 0
  let statusbarSize = if statusbar: 1 else: 0
  let style = WidgetStyle(
    paddingX1: padding,
    paddingX2: padding,
    paddingY1: padding,
    paddingY2: padding,
    border: border,
    fgColor: fgColor,
    bgColor: bgColor
  )
  
  result = (Chart)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    data: data,
    chartType: chartType,
    size: h - statusbarSize - py - (padding * 2),
    statusbarSize: statusbarSize,
    enableHelp: enableHelp,
    title: title,
    statusbar: statusbar,
    tb: tb,
    style: style,
    autoScale: true,
    showGrid: true,
    showLabels: true,
    showValues: false,
    showLegend: true,
    dotChar: "●",
    gridChar: "·",
    barChar: "█",
    lineChar: "─",
    pointChar: "●",
    # Initialize scrolling properties
    maxVisiblePoints: maxVisiblePoints,
    scrollOffset: 0,
    showLeftIndicator: false,
    showRightIndicator: false,
    autoScroll: true,
    events: initTable[string, EventFn[Chart]](),
    keyEvents: initTable[Key, EventFn[Chart]]()
  )
  
  result.helpText = " [T]   toggle chart type (line/bar/dot)\n" &
                    " [G]   toggle grid\n" &
                    " [L]   toggle labels\n" &
                    " [V]   toggle values\n" &
                    " [E]   toggle legend\n" & 
                    " [←→]  scroll left/right\n" &
                    " [A]   toggle auto-scroll\n" &
                    " [?]   for help\n" &
                    " [Tab] to go next widget\n" & 
                    " [Esc] to exit this window"
 
  result.channel = newChan[WidgetBgEvent]()
  if enableHelp:
    result.on(Key.QuestionMark, help)

  result.on(Key.ShiftT, toggleChartType)
  result.on(Key.ShiftG, toggleGrid)
  result.on(Key.ShiftL, toggleLabels)
  result.on(Key.ShiftA, toggleAutoScroll)
  result.on(Key.ShiftE, toggleLegend)
  result.calculateMaxVisiblePoints()
  result.keepOriginalSize()

proc newChart*(px, py: int, w, h: WidgetSize, id = "";
               title = "", data: ChartData = @[], chartType = LineChart,
               border = true, statusbar = true, enableHelp = true,
               bgColor = bgNone, fgColor = fgWhite,
               maxVisiblePoints = 0,
               tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): Chart =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newChart(px, py, width, height, id, title, data, chartType,
                  border, statusbar, enableHelp, bgColor, fgColor, maxVisiblePoints, tb)

proc newChart*(id: string): Chart =
  var chart = Chart(
    id: id,
    style: WidgetStyle(
      paddingX1: 1,
      paddingX2: 1,
      paddingY1: 1,
      paddingY2: 1,
      border: true,
      bgColor: bgNone,
      fgColor: fgWhite
    ),
    chartType: LineChart,
    autoScale: true,
    showGrid: true,
    showLabels: true,
    showValues: false,
    showLegend: true,
    dotChar: "●",
    gridChar: "·",
    barChar: "█",
    lineChar: "─",
    pointChar: "●",
    maxVisiblePoints: 0,
    scrollOffset: 0,
    showLeftIndicator: false,
    showRightIndicator: false,
    autoScroll: true,
    events: initTable[string, EventFn[Chart]](),
    keyEvents: initTable[Key, EventFn[Chart]]()
  )

  chart.helpText = " [T]   toggle chart type (line/bar)\n" &
                   " [G]   toggle grid\n" &
                   " [L]   toggle labels\n" &
                   " [V]   toggle values\n" &
                   " [?]   for help\n" &
                   " [Tab] to go next widget\n" & 
                   " [Esc] to exit this window"
  chart.on(Key.QuestionMark, help)
  chart.on(Key.ShiftT, toggleChartType)
  chart.on(Key.ShiftG, toggleGrid)
  chart.on(Key.ShiftL, toggleLabels)
  chart.channel = newChan[WidgetBgEvent]()
  return chart

proc calculateScale(ch: Chart) =
  if ch.data.len == 0:
    ch.minValue = 0.0
    ch.maxValue = 1.0
    return
    
  if ch.autoScale:
    ch.minValue = ch.data.mapIt(it.value).min
    ch.maxValue = ch.data.mapIt(it.value).max
    # Add some padding
    let range = ch.maxValue - ch.minValue
    if range > 0:
      ch.minValue -= range * 0.1
      ch.maxValue += range * 0.1
    else:
      ch.minValue -= 1.0
      ch.maxValue += 1.0

proc normalizeValue(ch: Chart, value: float): float =
  if ch.maxValue == ch.minValue:
    return 0.5
  return (value - ch.minValue) / (ch.maxValue - ch.minValue)

proc calculateMaxVisiblePoints*(ch: Chart) =
  let availableWidth = ch.x2 - ch.x1 - 2  # Reserve 1 char each side for indicators
  ch.maxVisiblePoints = max(1, availableWidth)  # At least 1 point visible
  
  # Update scroll indicators
  ch.showLeftIndicator = ch.scrollOffset > 0
  ch.showRightIndicator = ch.scrollOffset + ch.maxVisiblePoints < ch.data.len

proc scrollLeft*(ch: Chart) =
  if ch.scrollOffset > 0:
    ch.scrollOffset -= 1
    ch.calculateMaxVisiblePoints()

proc scrollRight*(ch: Chart) =
  if ch.scrollOffset + ch.maxVisiblePoints < ch.data.len:
    ch.scrollOffset += 1
    ch.calculateMaxVisiblePoints()

proc autoScrollToEnd*(ch: Chart) =
  if ch.data.len > ch.maxVisiblePoints:
    ch.scrollOffset = ch.data.len - ch.maxVisiblePoints
  else:
    ch.scrollOffset = 0
  ch.calculateMaxVisiblePoints()

proc getVisibleData*(ch: Chart): ChartData =
  if ch.data.len == 0:
    return @[]
  
  let startIdx = ch.scrollOffset
  let endIdx = min(startIdx + ch.maxVisiblePoints, ch.data.len)
  result = ch.data[startIdx..<endIdx]

proc toggleAutoScroll(ch: Chart, args: varargs[string]) =
  ch.autoScroll = not ch.autoScroll
  if ch.autoScroll:
    ch.autoScrollToEnd()

proc renderScrollIndicators(ch: Chart) =
  # Render left scroll indicator
  if ch.showLeftIndicator:
    ch.tb.write(ch.x1, ch.y1 + (ch.y2 - ch.y1) div 2, fgYellow, ch.bg, "◀")
  
  # Render right scroll indicator  
  if ch.showRightIndicator:
    ch.tb.write(ch.x2 - 1, ch.y1 + (ch.y2 - ch.y1) div 2, fgYellow, ch.bg, "▶")

proc renderGrid(ch: Chart) =
  if not ch.showGrid: return
  
  let chartWidth = ch.x2 - ch.x1
  let chartHeight = ch.y2 - ch.y1
  
  # Horizontal grid lines
  for i in 1..<chartHeight:
    for x in ch.x1..<ch.x2:
      ch.tb.write(x, ch.y1 + i, fgWhite, ch.bg, ch.gridChar)
  
  # Vertical grid lines (every 10 positions if space allows)
  if chartWidth > 20:
    let step = max(1, chartWidth div 10)
    for i in countup(step, chartWidth - 1, step):
      for y in ch.y1..<ch.y2:
        ch.tb.write(ch.x1 + i, y, fgWhite, ch.bg, ch.gridChar)

proc renderLineChart(ch: Chart) =
  let visibleData = ch.getVisibleData()
  if visibleData.len == 0: return
  
  let chartWidth = ch.x2 - ch.x1 - (if ch.showLeftIndicator: 1 else: 0) - (if ch.showRightIndicator: 1 else: 0)
  let chartHeight = ch.y2 - ch.y1
  let startX = ch.x1 + (if ch.showLeftIndicator: 1 else: 0)
  
  if chartHeight <= 0 or chartWidth <= 0: return
  
  # Calculate points for visible data
  var points: seq[tuple[x: int, y: int]] = @[]
  for i, dataPoint in visibleData:
    let x = startX + (i * chartWidth) div max(1, visibleData.len - 1)
    let normalizedValue = ch.normalizeValue(dataPoint.value)
    let y = ch.y2 - 1 - int(normalizedValue * float(chartHeight - 1))
    points.add((x: x, y: y))
  
  # Draw lines between points
  for i in 0..<points.len - 1:
    let p1 = points[i]
    let p2 = points[i + 1]
    
    # Simple line drawing
    let steps = abs(p2.x - p1.x) + abs(p2.y - p1.y)
    if steps > 0:
      for step in 0..steps:
        let t = step.float / steps.float
        let x = int(p1.x.float + t * (p2.x - p1.x).float)
        let y = int(p1.y.float + t * (p2.y - p1.y).float)
        let endX = startX + chartWidth - (if ch.showRightIndicator: 1 else: 0)
        if x >= startX and x < endX and y >= ch.y1 and y < ch.y2:
          ch.tb.write(x, y, ch.fg, ch.bg, ch.lineChar)
  
  # Draw points
  for point in points:
    let endX = startX + chartWidth - (if ch.showRightIndicator: 1 else: 0)
    if point.x >= startX and point.x < endX and point.y >= ch.y1 and point.y < ch.y2:
      ch.tb.write(point.x, point.y, fgYellow, ch.bg, ch.pointChar)

proc renderBarChart(ch: Chart) =
  let visibleData = ch.getVisibleData()
  if visibleData.len == 0: return
  
  let chartWidth = ch.x2 - ch.x1 - (if ch.showLeftIndicator: 1 else: 0) - (if ch.showRightIndicator: 1 else: 0)
  let chartHeight = ch.y2 - ch.y1
  let startX = ch.x1 + (if ch.showLeftIndicator: 1 else: 0)
  
  if chartHeight <= 0 or chartWidth <= 0: return
  
  let barWidth = max(1, chartWidth div visibleData.len)
  
  for i, dataPoint in visibleData:
    let normalizedValue = ch.normalizeValue(dataPoint.value)
    let barHeight = int(normalizedValue * float(chartHeight))
    let x = startX + (i * chartWidth) div visibleData.len
    let endX = startX + chartWidth - (if ch.showRightIndicator: 1 else: 0)
    
    # Draw bar from bottom up
    for h in 0..<barHeight:
      let y = ch.y2 - 1 - h
      if y >= ch.y1 and y < ch.y2:
        for w in 0..<min(barWidth, endX - x):
          if x + w < endX:
            ch.tb.write(x + w, y, ch.fg, ch.bg, ch.barChar)

proc renderLabels(ch: Chart) =
  if not ch.showLabels: return
  
  let visibleData = ch.getVisibleData()
  if visibleData.len == 0: return
  
  let chartWidth = ch.x2 - ch.x1 - (if ch.showLeftIndicator: 1 else: 0) - (if ch.showRightIndicator: 1 else: 0)
  let startX = ch.x1 + (if ch.showLeftIndicator: 1 else: 0)
  
  # Render visible data point labels at the bottom
  for i, dataPoint in visibleData:
    let x = startX + (i * chartWidth) div max(1, visibleData.len)
    let labelX = max(startX, min(x, ch.x2 - dataPoint.label.len - 1))
    if ch.y2 < ch.height:
      ch.tb.write(labelX, ch.y2, ch.fg, ch.bg, dataPoint.label[0..min(dataPoint.label.len-1, 10)])

proc renderValues(ch: Chart) =
  if not ch.showValues: return
  
  let visibleData = ch.getVisibleData()
  if visibleData.len == 0: return
  
  let chartWidth = ch.x2 - ch.x1 - (if ch.showLeftIndicator: 1 else: 0) - (if ch.showRightIndicator: 1 else: 0)
  let chartHeight = ch.y2 - ch.y1
  let startX = ch.x1 + (if ch.showLeftIndicator: 1 else: 0)
  let endX = startX + chartWidth - (if ch.showRightIndicator: 1 else: 0)
  
  # Calculate legend area to avoid overlap
  let legendWidth = if ch.showLegend and ch.data.len > 0: 
                     min(ch.data.mapIt(it.label.len).max + 10, (ch.x2 - ch.x1) div 3)
                   else: 0
  let legendX = if ch.showLegend: ch.x2 - legendWidth - 1 else: ch.x2
  let legendHeight = if ch.showLegend and ch.data.len > 0:
                      min(ch.data.len + 2, (ch.y2 - ch.y1) div 2)
                    else: 0
  let legendY = ch.y1 + 1
  
  for i, dataPoint in visibleData:
    let x = startX + (i * chartWidth) div max(1, visibleData.len)
    let normalizedValue = ch.normalizeValue(dataPoint.value)
    let y = ch.y2 - 1 - int(normalizedValue * float(chartHeight - 1))
    let valueStr = dataPoint.value.formatFloat(ffDecimal, 1)
    
    # Check bounds and avoid legend overlap
    let valueY = max(ch.y1, y - 1)  # Position above the data point
    let valueX = min(x, endX - valueStr.len)  # Ensure it fits within chart area
    
    # Avoid rendering values that would overlap with legend
    let wouldOverlapLegend = ch.showLegend and 
                           valueX + valueStr.len > legendX and 
                           valueX < legendX + legendWidth and
                           valueY >= legendY and 
                           valueY < legendY + legendHeight
    
    if valueY >= ch.y1 and valueY < ch.y2 and 
       valueX >= startX and valueX + valueStr.len < endX and
       not wouldOverlapLegend:
      ch.tb.write(valueX, valueY, fgCyan, ch.bg, valueStr)

proc help(ch: Chart, args: varargs[string]) = 
  let wsize = ((ch.width - ch.posX).toFloat * 0.3).toInt()
  let hsize = ((ch.height - ch.posY).toFloat * 0.3).toInt()
  var display = newDisplay(ch.x2 - wsize, ch.y2 - hsize, 
                          ch.x2, ch.y2, title="help",
                          bgColor=bgWhite, fgColor=fgBlack,
                          tb=ch.tb, statusbar=false, 
                          enableHelp=false)
  var helpText = ch.helpText
  display.text = helpText
  display.illwillInit = true
  ch.render()
  display.onControl()
  display.clear()

proc toggleChartType(ch: Chart, args: varargs[string]) = 
  case ch.chartType:
  of LineChart: ch.chartType = BarChart
  of BarChart: ch.chartType = DottedChart
  of DottedChart: ch.chartType = LineChart

proc toggleLegend(ch: Chart, args: varargs[string]) =
  ch.showLegend = not ch.showLegend

proc toggleGrid(ch: Chart, args: varargs[string]) = 
  ch.showGrid = not ch.showGrid

proc toggleLabels(ch: Chart, args: varargs[string]) = 
  ch.showLabels = not ch.showLabels

proc renderDottedChart(ch: Chart) =
  let visibleData = ch.getVisibleData()
  if visibleData.len == 0: return
  
  let chartWidth = ch.x2 - ch.x1 - (if ch.showLeftIndicator: 1 else: 0) - (if ch.showRightIndicator: 1 else: 0)
  let chartHeight = ch.y2 - ch.y1
  let startX = ch.x1 + (if ch.showLeftIndicator: 1 else: 0)
  
  if chartHeight <= 0 or chartWidth <= 0: return
  
  # Calculate and render dots for each data point
  for i, dataPoint in visibleData:
    let x = startX + (i * chartWidth) div max(1, visibleData.len - 1)
    let normalizedValue = ch.normalizeValue(dataPoint.value)
    let y = ch.y2 - 1 - int(normalizedValue * float(chartHeight - 1))
    let endX = startX + chartWidth - (if ch.showRightIndicator: 1 else: 0)
    
    if x >= startX and x < endX and y >= ch.y1 and y < ch.y2:
      ch.tb.write(x, y, fgGreen, ch.bg, ch.dotChar)


proc renderLegend(ch: Chart) =
  if not ch.showLegend or ch.data.len == 0: return
  
  # Calculate legend dimensions and position
  let maxLabelLen = ch.data.mapIt(it.label.len).max
  let legendWidth = min(maxLabelLen + 10, (ch.x2 - ch.x1) div 3)  # Max 1/3 of chart width
  let legendHeight = min(ch.data.len + 2, (ch.y2 - ch.y1) div 2)  # Max half of chart height
  let legendX = ch.x2 - legendWidth - 1
  let legendY = ch.y1 + 1
  
  # Draw legend box border
  for x in legendX..<(legendX + legendWidth):
    ch.tb.write(x, legendY, fgWhite, ch.bg, "─")  # Top border
    ch.tb.write(x, legendY + legendHeight - 1, fgWhite, ch.bg, "─")  # Bottom border
  
  for y in legendY..<(legendY + legendHeight):
    ch.tb.write(legendX, y, fgWhite, ch.bg, "│")  # Left border
    ch.tb.write(legendX + legendWidth - 1, y, fgWhite, ch.bg, "│")  # Right border
  
  # Draw corners
  ch.tb.write(legendX, legendY, fgWhite, ch.bg, "┌")
  ch.tb.write(legendX + legendWidth - 1, legendY, fgWhite, ch.bg, "┐")
  ch.tb.write(legendX, legendY + legendHeight - 1, fgWhite, ch.bg, "└")
  ch.tb.write(legendX + legendWidth - 1, legendY + legendHeight - 1, fgWhite, ch.bg, "┘")
  
  # Fill legend background
  for y in (legendY + 1)..<(legendY + legendHeight - 1):
    for x in (legendX + 1)..<(legendX + legendWidth - 1):
      ch.tb.write(x, y, ch.fg, bgBlack, " ")
  
  # Render legend title
  ch.tb.write(legendX + 2, legendY + 1, fgYellow, bgBlack, "Legend")
  
  # Render visible data entries in legend
  let visibleData = ch.getVisibleData()
  let maxEntries = legendHeight - 3  # Reserve space for borders and title
  
  for i, dataPoint in visibleData:
    if i >= maxEntries: break
    
    let entryY = legendY + 2 + i
    let symbol = case ch.chartType:
      of LineChart: ch.pointChar
      of BarChart: ch.barChar
      of DottedChart: ch.dotChar
    
    # Render symbol and label
    ch.tb.write(legendX + 2, entryY, fgGreen, bgBlack, symbol)
    let truncatedLabel = if dataPoint.label.len > legendWidth - 6: 
                          dataPoint.label[0..<(legendWidth - 6)] else: dataPoint.label
    ch.tb.write(legendX + 4, entryY, fgWhite, bgBlack, truncatedLabel)

proc renderStatusbar(ch: Chart) =
  if ch.events.hasKey("statusbar"):
    ch.call("statusbar")
  else:
    let typeStr = case ch.chartType:
      of LineChart: "Line"
      of BarChart: "Bar" 
      of DottedChart: "Dot"
    
    let scrollInfo = if ch.data.len > ch.maxVisiblePoints: 
                      " | Showing " & $(ch.scrollOffset + 1) & "-" & 
                      $(min(ch.scrollOffset + ch.maxVisiblePoints, ch.data.len)) & 
                      " of " & $ch.data.len else: ""
    let autoScrollStr = if ch.autoScroll: " [AUTO]" else: ""
    ch.statusbarText = " " & typeStr & " | Points: " & $ch.data.len & scrollInfo & autoScrollStr & " "
    
    ch.renderCleanRect(ch.x1, ch.height, ch.statusbarText.len, ch.height)
    ch.tb.write(ch.x1, ch.height, bgBlue, fgWhite, ch.statusbarText, resetStyle)
    
    let indicators = if ch.showGrid and ch.showLabels and ch.showLegend: "[G][L][E]" 
                    elif ch.showGrid and ch.showLabels: "[G][L]"
                    elif ch.showGrid and ch.showLegend: "[G][E]"
                    elif ch.showLabels and ch.showLegend: "[L][E]"
                    elif ch.showGrid: "[G]"
                    elif ch.showLabels: "[L]"
                    elif ch.showLegend: "[E]"
                    else: ""
    
    let help = "[?]"
    if ch.enableHelp:
      ch.tb.write(ch.x2 - len(help), ch.height, bgWhite, fgBlack, help, resetStyle)
    if indicators.len > 0:
      ch.tb.write(ch.x2 - len(indicators & help), ch.height, bgWhite, fgBlack, indicators, resetStyle)

method resize*(ch: Chart) =
  let statusbarSize = if ch.statusbar: 1 else: 0
  ch.size = ch.height - statusbarSize - ch.posY - (ch.paddingY1 * 2)
  ch.calculateMaxVisiblePoints()

proc on*(ch: Chart, event: string, fn: EventFn[Chart]) =
  ch.events[event] = fn

proc on*(ch: Chart, key: Key, fn: EventFn[Chart]) {.raises: [EventKeyError].} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  ch.keyEvents[key] = fn

method call*(ch: Chart, event: string, args: varargs[string]) =
  if ch.events.hasKey(event):
    let fn = ch.events[event]
    fn(ch, args)

method call*(ch: ChartObj, event: string, args: varargs[string]) =
  if ch.events.hasKey(event):
    let chRef = ch.asRef()
    let fn = ch.events[event]
    fn(chRef, args)

proc call(ch: Chart, key: Key, args: varargs[string]) =
  if ch.keyEvents.hasKey(key):
    let fn = ch.keyEvents[key]
    fn(ch, args)

method render*(ch: Chart) =
  if not ch.illwillInit: return
  
  ch.calculateScale()
  ch.calculateMaxVisiblePoints()
  ch.clear()
  ch.renderBorder()
  ch.renderTitle()
  
  if ch.showGrid:
    ch.renderGrid()
  
  # Render scroll indicators first
  ch.renderScrollIndicators()
  
  case ch.chartType:
  of LineChart:
    ch.renderLineChart()
  of BarChart:
    ch.renderBarChart()
  of DottedChart:
    ch.renderDottedChart()
  
  if ch.showLabels:
    ch.renderLabels()
  
  # Render legend before values to establish the area to avoid
  if ch.showLegend:
    ch.renderLegend()
  
  # Render values after legend to avoid overlap
  if ch.showValues:
    ch.renderValues()
  
  if ch.statusbar:
    ch.renderStatusbar()
  
  ch.tb.display()

method poll*(ch: Chart) =
  var widgetEv: WidgetBgEvent
  if ch.channel.tryRecv(widgetEv):
    ch.call(widgetEv.event, widgetEv.args)
    ch.render()

method onUpdate*(ch: Chart, key: Key) =
  if ch.visibility == false: return
  
  ch.call("preupdate", $key) 
  
  case key
  of Key.None: discard
  of Key.Left:
    ch.scrollLeft()
  of Key.Right:
    ch.scrollRight()
  of Key.ShiftV:
    ch.showValues = not ch.showValues
  of Key.ShiftA:
    ch.toggleAutoScroll()
  of Key.ShiftE:
    ch.toggleLegend()
  of Key.Escape, Key.Tab:
    ch.focus = false
  else:
    if key in forbiddenKeyBind: discard
    elif ch.keyEvents.hasKey(key):
      ch.call(key, "")
  
  ch.render()
  ch.call("postupdate", $key)

method onControl*(ch: Chart) =
  if ch.visibility == false: return
  
  ch.focus = true
  ch.clear()
  while ch.focus:
    var key = getKeyWithTimeout(ch.rpms)
    ch.onUpdate(key)
    sleep(ch.rpms)

method wg*(ch: Chart): ref BaseWidget = ch

# Data manipulation procedures
proc setData*(ch: Chart, data: ChartData) =
  ch.data = data
  if ch.width > 0:
    ch.render()

proc addDataPoint*(ch: Chart, label: string, value: float) =
  ch.data.add(DataPoint(label: label, value: value))
  
  # Auto-scroll to show latest data if enabled
  if ch.autoScroll:
    ch.autoScrollToEnd()
  
  if ch.width > 0:
    ch.render()

proc clearData*(ch: Chart) =
  ch.data = @[]
  if ch.width > 0:
    ch.render()

proc `chartType=`*(ch: Chart, chartType: ChartType) =
  ch.chartType = chartType
  if ch.visibility:
    ch.render()

proc `autoScale=`*(ch: Chart, autoScale: bool) =
  ch.autoScale = autoScale
  if ch.visibility:
    ch.render()

proc setScale*(ch: Chart, minVal, maxVal: float) =
  ch.autoScale = false
  ch.minValue = minVal
  ch.maxValue = maxVal
  if ch.visibility:
    ch.render()