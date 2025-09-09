import illwill, base_wg, os, strutils, tables, math, sequtils, display_wg, random
import threading/channels

type
  HeatmapData* = seq[seq[float]]
  
  ColorScheme* = enum
    RedScale, BlueScale, GreenScale, GrayScale, Rainbow
  
  Heatmap* = ref HeatmapObj

  HeatmapObj* = object of BaseWidget
    data*: HeatmapData
    rowLabels*: seq[string]
    colLabels*: seq[string]
    colorScheme*: ColorScheme
    maxValue*: float
    minValue*: float
    autoScale*: bool
    showGrid*: bool
    showLabels*: bool
    showValues*: bool
    showColorbar*: bool
    cellWidth*: int
    cellHeight*: int
    colorbarWidth*: int
    scrollOffsetX*: int
    scrollOffsetY*: int
    maxVisibleCols*: int
    maxVisibleRows*: int
    showScrollIndicators*: bool
    events*: Table[string, EventFn[Heatmap]]
    keyEvents*: Table[Key, EventFn[Heatmap]]

proc help(hm: Heatmap, args: varargs[string]): void
proc on*(hm: Heatmap, key: Key, fn: EventFn[Heatmap]) {.raises: [EventKeyError].}
proc toggleGrid(hm: Heatmap, args: varargs[string]): void
proc toggleLabels(hm: Heatmap, args: varargs[string]): void
proc toggleValues(hm: Heatmap, args: varargs[string]): void
proc toggleColorbar(hm: Heatmap, args: varargs[string]): void
proc cycleColorScheme(hm: Heatmap, args: varargs[string]): void
proc calculateMaxVisible*(hm: Heatmap): void

# Forbidden keys for heatmap widget
const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.None, Key.Up,
                          Key.Down, Key.Left, Key.Right, Key.PageUp, 
                          Key.PageDown, Key.Home, Key.End}

proc newHeatmap*(px, py, w, h: int, id = "";
                 title: string = "", data: HeatmapData = @[], 
                 rowLabels: seq[string] = @[], colLabels: seq[string] = @[],
                 colorScheme = RedScale, border: bool = true,
                 statusbar = true, enableHelp = true,
                 bgColor: BackgroundColor = bgNone,
                 fgColor: ForegroundColor = fgWhite,
                 cellWidth = 3, cellHeight = 1,
                 tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): Heatmap =
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
  
  result = (Heatmap)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    data: data,
    rowLabels: rowLabels,
    colLabels: colLabels,
    colorScheme: colorScheme,
    size: h - statusbarSize - py - (padding * 2),
    statusbarSize: statusbarSize,
    enableHelp: enableHelp,
    title: title,
    statusbar: statusbar,
    tb: tb,
    style: style,
    autoScale: true,
    showGrid: false,
    showLabels: true,
    showValues: false,
    showColorbar: true,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    colorbarWidth: 15,
    scrollOffsetX: 0,
    scrollOffsetY: 0,
    maxVisibleCols: 0,
    maxVisibleRows: 0,
    showScrollIndicators: false,
    events: initTable[string, EventFn[Heatmap]](),
    keyEvents: initTable[Key, EventFn[Heatmap]]()
  )
  
  result.helpText = " [C]   cycle color scheme\n" &
                    " [G]   toggle grid\n" &
                    " [L]   toggle labels\n" &
                    " [V]   toggle values\n" &
                    " [B]   toggle colorbar\n" & 
                    " [←→↑↓] scroll\n" &
                    " [?]   for help\n" &
                    " [Tab] to go next widget\n" & 
                    " [Esc] to exit this window"
 
  result.channel = newChan[WidgetBgEvent]()
  if enableHelp:
    result.on(Key.QuestionMark, help)

  result.on(Key.ShiftC, cycleColorScheme)
  result.on(Key.ShiftG, toggleGrid)
  result.on(Key.ShiftL, toggleLabels)
  result.on(Key.ShiftV, toggleValues)
  result.on(Key.ShiftB, toggleColorbar)
  result.calculateMaxVisible()
  result.keepOriginalSize()

proc newHeatmap*(px, py: int, w, h: WidgetSize, id = "";
                 title = "", data: HeatmapData = @[], 
                 rowLabels: seq[string] = @[], colLabels: seq[string] = @[],
                 colorScheme = RedScale, border = true, statusbar = true, 
                 enableHelp = true, bgColor = bgNone, fgColor = fgWhite,
                 cellWidth = 3, cellHeight = 1,
                 tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): Heatmap =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newHeatmap(px, py, width, height, id, title, data, rowLabels, colLabels,
                    colorScheme, border, statusbar, enableHelp, bgColor, fgColor, 
                    cellWidth, cellHeight, tb)

proc newHeatmap*(id: string): Heatmap =
  var heatmap = Heatmap(
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
    colorScheme: RedScale,
    autoScale: true,
    showGrid: false,
    showLabels: true,
    showValues: false,
    showColorbar: true,
    cellWidth: 3,
    cellHeight: 1,
    colorbarWidth: 15,
    scrollOffsetX: 0,
    scrollOffsetY: 0,
    maxVisibleCols: 0,
    maxVisibleRows: 0,
    showScrollIndicators: false,
    events: initTable[string, EventFn[Heatmap]](),
    keyEvents: initTable[Key, EventFn[Heatmap]]()
  )

  heatmap.helpText = " [C]   cycle color scheme\n" &
                     " [G]   toggle grid\n" &
                     " [L]   toggle labels\n" &
                     " [V]   toggle values\n" &
                     " [B]   toggle colorbar\n" &
                     " [?]   for help\n" &
                     " [Tab] to go next widget\n" & 
                     " [Esc] to exit this window"
  heatmap.on(Key.QuestionMark, help)
  heatmap.on(Key.ShiftC, cycleColorScheme)
  heatmap.on(Key.ShiftG, toggleGrid)
  heatmap.on(Key.ShiftL, toggleLabels)
  heatmap.on(Key.ShiftV, toggleValues)
  heatmap.on(Key.ShiftB, toggleColorbar)
  heatmap.channel = newChan[WidgetBgEvent]()
  return heatmap

proc calculateScale(hm: Heatmap) =
  if hm.data.len == 0:
    hm.minValue = 0.0
    hm.maxValue = 1.0
    return
    
  if hm.autoScale:
    hm.minValue = hm.data.mapIt(it.min).min
    hm.maxValue = hm.data.mapIt(it.max).max
    # Add some padding
    let range = hm.maxValue - hm.minValue
    if range > 0:
      hm.minValue -= range * 0.05
      hm.maxValue += range * 0.05
    else:
      hm.minValue -= 0.5
      hm.maxValue += 0.5

proc normalizeValue(hm: Heatmap, value: float): float =
  if hm.maxValue == hm.minValue:
    return 0.5
  return (value - hm.minValue) / (hm.maxValue - hm.minValue)

proc calculateMaxVisible*(hm: Heatmap) =
  let availableWidth = hm.x2 - hm.x1 - (if hm.showLabels: 10 else: 0) - (if hm.showColorbar: hm.colorbarWidth else: 0)
  let availableHeight = hm.y2 - hm.y1 - (if hm.showLabels: 2 else: 0)
  
  hm.maxVisibleCols = max(1, availableWidth div hm.cellWidth)
  hm.maxVisibleRows = max(1, availableHeight div hm.cellHeight)
  
  # Update scroll indicators
  let totalCols = if hm.data.len > 0: hm.data[0].len else: 0
  let totalRows = hm.data.len
  hm.showScrollIndicators = (hm.scrollOffsetX + hm.maxVisibleCols < totalCols) or
                           (hm.scrollOffsetY + hm.maxVisibleRows < totalRows) or
                           hm.scrollOffsetX > 0 or hm.scrollOffsetY > 0

proc scrollLeft*(hm: Heatmap) =
  if hm.scrollOffsetX > 0:
    hm.scrollOffsetX -= 1
    hm.calculateMaxVisible()

proc scrollRight*(hm: Heatmap) =
  let totalCols = if hm.data.len > 0: hm.data[0].len else: 0
  if hm.scrollOffsetX + hm.maxVisibleCols < totalCols:
    hm.scrollOffsetX += 1
    hm.calculateMaxVisible()

proc scrollUp*(hm: Heatmap) =
  if hm.scrollOffsetY > 0:
    hm.scrollOffsetY -= 1
    hm.calculateMaxVisible()

proc scrollDown*(hm: Heatmap) =
  if hm.scrollOffsetY + hm.maxVisibleRows < hm.data.len:
    hm.scrollOffsetY += 1
    hm.calculateMaxVisible()

proc getColorForValue(hm: Heatmap, value: float): (ForegroundColor, BackgroundColor) =
  let normalized = hm.normalizeValue(value)
  let intensity = int(normalized * 7.0)  # 0-7 range for different shades
  
  case hm.colorScheme:
  of RedScale:
    case intensity:
    of 0: (fgWhite, bgBlack)
    of 1: (fgWhite, bgRed)
    of 2..3: (fgBlack, bgRed)
    of 4..5: (fgWhite, bgRed)
    else: (fgYellow, bgRed)
  of BlueScale:
    case intensity:
    of 0: (fgWhite, bgBlack)
    of 1: (fgWhite, bgBlue)
    of 2..3: (fgBlack, bgBlue)
    of 4..5: (fgWhite, bgBlue)
    else: (fgCyan, bgBlue)
  of GreenScale:
    case intensity:
    of 0: (fgWhite, bgBlack)
    of 1: (fgWhite, bgGreen)
    of 2..3: (fgBlack, bgGreen)
    of 4..5: (fgWhite, bgGreen)
    else: (fgYellow, bgGreen)
  of GrayScale:
    case intensity:
    of 0: (fgBlack, bgBlack)
    of 1..2: (fgWhite, bgBlack)
    of 3..4: (fgBlack, bgWhite)
    of 5..6: (fgWhite, bgWhite)
    else: (fgWhite, bgWhite)
  of Rainbow:
    case intensity:
    of 0: (fgWhite, bgBlue)
    of 1: (fgWhite, bgCyan)
    of 2: (fgBlack, bgGreen)
    of 3: (fgBlack, bgYellow)
    of 4: (fgBlack, bgYellow)
    of 5: (fgWhite, bgRed)
    of 6: (fgWhite, bgMagenta)
    else: (fgYellow, bgRed)

proc renderHeatmapCells(hm: Heatmap) =
  if hm.data.len == 0: return
  
  let startX = hm.x1 + (if hm.showLabels: 10 else: 0)
  let startY = hm.y1 + (if hm.showLabels: 1 else: 0)
  
  let endRow = min(hm.scrollOffsetY + hm.maxVisibleRows, hm.data.len)
  let endCol = min(hm.scrollOffsetX + hm.maxVisibleCols, 
                   if hm.data.len > 0: hm.data[0].len else: 0)
  
  for row in hm.scrollOffsetY..<endRow:
    for col in hm.scrollOffsetX..<endCol:
      if row < hm.data.len and col < hm.data[row].len:
        let value = hm.data[row][col]
        let (fg, bg) = hm.getColorForValue(value)
        
        let cellX = startX + (col - hm.scrollOffsetX) * hm.cellWidth
        let cellY = startY + (row - hm.scrollOffsetY) * hm.cellHeight
        
        # Fill cell
        for h in 0..<hm.cellHeight:
          for w in 0..<hm.cellWidth:
            let x = cellX + w
            let y = cellY + h
            if x < hm.x2 - (if hm.showColorbar: hm.colorbarWidth else: 0) and y < hm.y2:
              if hm.showValues and h == 0 and w == 0:
                let valueStr = value.formatFloat(ffDecimal, 1)
                if valueStr.len <= hm.cellWidth:
                  hm.tb.write(x, y, fg, bg, valueStr[0..<min(valueStr.len, hm.cellWidth)])
                else:
                  hm.tb.write(x, y, fg, bg, " ")
              else:
                hm.tb.write(x, y, fg, bg, " ")
        
        # Draw grid if enabled
        if hm.showGrid:
          # Right border
          if cellX + hm.cellWidth < hm.x2 - (if hm.showColorbar: hm.colorbarWidth else: 0):
            for h in 0..<hm.cellHeight:
              hm.tb.write(cellX + hm.cellWidth, cellY + h, fgWhite, hm.bg, "│")
          # Bottom border
          if cellY + hm.cellHeight < hm.y2:
            for w in 0..<hm.cellWidth:
              hm.tb.write(cellX + w, cellY + hm.cellHeight, fgWhite, hm.bg, "─")

proc renderLabels(hm: Heatmap) =
  if not hm.showLabels: return
  
  let startX = hm.x1 + (if hm.showLabels: 10 else: 0)
  let startY = hm.y1 + (if hm.showLabels: 1 else: 0)
  
  # Row labels
  let endRow = min(hm.scrollOffsetY + hm.maxVisibleRows, hm.data.len)
  for row in hm.scrollOffsetY..<endRow:
    let labelY = startY + (row - hm.scrollOffsetY) * hm.cellHeight
    if labelY < hm.y2:
      let label = if row < hm.rowLabels.len: hm.rowLabels[row] else: $row
      let truncatedLabel = if label.len > 8: label[0..<8] else: label
      hm.tb.write(hm.x1, labelY, hm.fg, hm.bg, truncatedLabel)
  
  # Column labels
  let endCol = min(hm.scrollOffsetX + hm.maxVisibleCols, 
                   if hm.data.len > 0: hm.data[0].len else: 0)
  for col in hm.scrollOffsetX..<endCol:
    let labelX = startX + (col - hm.scrollOffsetX) * hm.cellWidth
    if labelX < hm.x2 - (if hm.showColorbar: hm.colorbarWidth else: 0):
      let label = if col < hm.colLabels.len: hm.colLabels[col] else: $col
      let truncatedLabel = if label.len > hm.cellWidth: label[0..<hm.cellWidth] else: label
      hm.tb.write(labelX, hm.y1, hm.fg, hm.bg, truncatedLabel)

proc renderColorbar(hm: Heatmap) =
  if not hm.showColorbar: return
  
  let colorbarX = hm.x2 - hm.colorbarWidth
  let colorbarY = hm.y1 + 2
  let colorbarHeight = hm.y2 - colorbarY - 2
  
  if colorbarHeight <= 0: return
  
  # Draw colorbar border
  for y in colorbarY..<(colorbarY + colorbarHeight):
    hm.tb.write(colorbarX, y, fgWhite, hm.bg, "│")
    hm.tb.write(colorbarX + 8, y, fgWhite, hm.bg, "│")
  
  # Draw color gradient
  for i in 0..<colorbarHeight:
    let value = hm.minValue + (hm.maxValue - hm.minValue) * (1.0 - i.float / colorbarHeight.float)
    let (fg, bg) = hm.getColorForValue(value)
    
    for x in (colorbarX + 1)..<(colorbarX + 8):
      hm.tb.write(x, colorbarY + i, fg, bg, " ")
  
  # Draw scale labels
  let maxStr = hm.maxValue.formatFloat(ffDecimal, 1)
  let minStr = hm.minValue.formatFloat(ffDecimal, 1)
  hm.tb.write(colorbarX + 9, colorbarY, hm.fg, hm.bg, maxStr)
  hm.tb.write(colorbarX + 9, colorbarY + colorbarHeight - 1, hm.fg, hm.bg, minStr)

proc renderScrollIndicators(hm: Heatmap) =
  if not hm.showScrollIndicators: return
  
  # Left/Right scroll indicators
  if hm.scrollOffsetX > 0:
    hm.tb.write(hm.x1, hm.y1 + (hm.y2 - hm.y1) div 2, fgYellow, hm.bg, "◀")
  
  let totalCols = if hm.data.len > 0: hm.data[0].len else: 0
  if hm.scrollOffsetX + hm.maxVisibleCols < totalCols:
    let rightX = hm.x2 - (if hm.showColorbar: hm.colorbarWidth + 1 else: 1)
    hm.tb.write(rightX, hm.y1 + (hm.y2 - hm.y1) div 2, fgYellow, hm.bg, "▶")
  
  # Up/Down scroll indicators
  if hm.scrollOffsetY > 0:
    hm.tb.write(hm.x1 + (hm.x2 - hm.x1) div 2, hm.y1, fgYellow, hm.bg, "▲")
  
  if hm.scrollOffsetY + hm.maxVisibleRows < hm.data.len:
    hm.tb.write(hm.x1 + (hm.x2 - hm.x1) div 2, hm.y2 - 1, fgYellow, hm.bg, "▼")

proc help(hm: Heatmap, args: varargs[string]) = 
  let wsize = ((hm.width - hm.posX).toFloat * 0.3).toInt()
  let hsize = ((hm.height - hm.posY).toFloat * 0.3).toInt()
  var display = newDisplay(hm.x2 - wsize, hm.y2 - hsize, 
                          hm.x2, hm.y2, title="help",
                          bgColor=bgWhite, fgColor=fgBlack,
                          tb=hm.tb, statusbar=false, 
                          enableHelp=false)
  var helpText = hm.helpText
  display.text = helpText
  display.illwillInit = true
  hm.render()
  display.onControl()
  display.clear()

proc cycleColorScheme(hm: Heatmap, args: varargs[string]) = 
  case hm.colorScheme:
  of RedScale: hm.colorScheme = BlueScale
  of BlueScale: hm.colorScheme = GreenScale
  of GreenScale: hm.colorScheme = GrayScale
  of GrayScale: hm.colorScheme = Rainbow
  of Rainbow: hm.colorScheme = RedScale

proc toggleGrid(hm: Heatmap, args: varargs[string]) = 
  hm.showGrid = not hm.showGrid

proc toggleLabels(hm: Heatmap, args: varargs[string]) = 
  hm.showLabels = not hm.showLabels
  hm.calculateMaxVisible()

proc toggleValues(hm: Heatmap, args: varargs[string]) = 
  hm.showValues = not hm.showValues

proc toggleColorbar(hm: Heatmap, args: varargs[string]) = 
  hm.showColorbar = not hm.showColorbar
  hm.calculateMaxVisible()

proc renderStatusbar(hm: Heatmap) =
  if hm.events.hasKey("statusbar"):
    hm.call("statusbar")
  else:
    let schemeStr = case hm.colorScheme:
      of RedScale: "Red"
      of BlueScale: "Blue"
      of GreenScale: "Green"
      of GrayScale: "Gray"
      of Rainbow: "Rainbow"
    
    let totalCols = if hm.data.len > 0: hm.data[0].len else: 0
    let scrollInfo = " | View: " & $(hm.scrollOffsetY + 1) & "-" & 
                     $(min(hm.scrollOffsetY + hm.maxVisibleRows, hm.data.len)) &
                     " x " & $(hm.scrollOffsetX + 1) & "-" &
                     $(min(hm.scrollOffsetX + hm.maxVisibleCols, totalCols))
    
    hm.statusbarText = " " & schemeStr & " | Size: " & $hm.data.len & "x" & $totalCols & scrollInfo & " "
    
    hm.renderCleanRect(hm.x1, hm.height, hm.statusbarText.len, hm.height)
    hm.tb.write(hm.x1, hm.height, bgBlue, fgWhite, hm.statusbarText, resetStyle)
    
    let indicators = if hm.showGrid and hm.showLabels and hm.showColorbar and hm.showValues: "[G][L][B][V]" 
                    elif hm.showGrid and hm.showLabels and hm.showColorbar: "[G][L][B]"
                    elif hm.showGrid and hm.showLabels and hm.showValues: "[G][L][V]"
                    elif hm.showLabels and hm.showColorbar and hm.showValues: "[L][B][V]"
                    elif hm.showGrid and hm.showLabels: "[G][L]"
                    elif hm.showGrid and hm.showColorbar: "[G][B]"
                    elif hm.showLabels and hm.showColorbar: "[L][B]"
                    elif hm.showGrid: "[G]"
                    elif hm.showLabels: "[L]"
                    elif hm.showColorbar: "[B]"
                    elif hm.showValues: "[V]"
                    else: ""
    
    let help = "[?]"
    if hm.enableHelp:
      hm.tb.write(hm.x2 - len(help), hm.height, bgWhite, fgBlack, help, resetStyle)
    if indicators.len > 0:
      hm.tb.write(hm.x2 - len(indicators & help), hm.height, bgWhite, fgBlack, indicators, resetStyle)

method resize*(hm: Heatmap) =
  let statusbarSize = if hm.statusbar: 1 else: 0
  hm.size = hm.height - statusbarSize - hm.posY - (hm.paddingY1 * 2)
  hm.calculateMaxVisible()

proc on*(hm: Heatmap, event: string, fn: EventFn[Heatmap]) =
  hm.events[event] = fn

proc on*(hm: Heatmap, key: Key, fn: EventFn[Heatmap]) {.raises: [EventKeyError].} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  hm.keyEvents[key] = fn

method call*(hm: Heatmap, event: string, args: varargs[string]) =
  if hm.events.hasKey(event):
    let fn = hm.events[event]
    fn(hm, args)

method call*(hm: HeatmapObj, event: string, args: varargs[string]) =
  if hm.events.hasKey(event):
    let hmRef = hm.asRef()
    let fn = hm.events[event]
    fn(hmRef, args)

proc call(hm: Heatmap, key: Key, args: varargs[string]) =
  if hm.keyEvents.hasKey(key):
    let fn = hm.keyEvents[key]
    fn(hm, args)

method render*(hm: Heatmap) =
  if not hm.illwillInit: return
  
  hm.calculateScale()
  hm.calculateMaxVisible()
  hm.clear()
  hm.renderBorder()
  hm.renderTitle()
  
  hm.renderHeatmapCells()
  
  if hm.showLabels:
    hm.renderLabels()
  
  if hm.showColorbar:
    hm.renderColorbar()
  
  hm.renderScrollIndicators()
  
  if hm.statusbar:
    hm.renderStatusbar()
  
  hm.tb.display()

method poll*(hm: Heatmap) =
  var widgetEv: WidgetBgEvent
  if hm.channel.tryRecv(widgetEv):
    hm.call(widgetEv.event, widgetEv.args)
    hm.render()

method onUpdate*(hm: Heatmap, key: Key) =
  if hm.visibility == false: return
  
  hm.call("preupdate", $key) 
  
  case key
  of Key.None: discard
  of Key.Left:
    hm.scrollLeft()
  of Key.Right:
    hm.scrollRight()
  of Key.Up:
    hm.scrollUp()
  of Key.Down:
    hm.scrollDown()
  of Key.Escape, Key.Tab:
    hm.focus = false
  else:
    if key in forbiddenKeyBind: discard
    elif hm.keyEvents.hasKey(key):
      hm.call(key, "")
  
  hm.render()
  hm.call("postupdate", $key)

method onControl*(hm: Heatmap) =
  if hm.visibility == false: return
  
  hm.focus = true
  hm.clear()
  while hm.focus:
    var key = getKeyWithTimeout(hm.rpms)
    hm.onUpdate(key)
    sleep(hm.rpms)

method wg*(hm: Heatmap): ref BaseWidget = hm

# Data manipulation procedures
proc setData*(hm: Heatmap, data: HeatmapData) =
  hm.data = data
  if hm.width > 0:
    hm.render()

proc setData*(hm: Heatmap, data: HeatmapData, rowLabels, colLabels: seq[string]) =
  hm.data = data
  hm.rowLabels = rowLabels
  hm.colLabels = colLabels
  if hm.width > 0:
    hm.render()

proc clearData*(hm: Heatmap) =
  hm.data = @[]
  hm.rowLabels = @[]
  hm.colLabels = @[]
  if hm.width > 0:
    hm.render()

proc `colorScheme=`*(hm: Heatmap, colorScheme: ColorScheme) =
  hm.colorScheme = colorScheme
  if hm.visibility:
    hm.render()

proc `autoScale=`*(hm: Heatmap, autoScale: bool) =
  hm.autoScale = autoScale
  if hm.visibility:
    hm.render()

proc `showGrid=`*(hm: Heatmap, showGrid: bool) =
  hm.showGrid = showGrid
  if hm.visibility:
    hm.render()

proc `showLabels=`*(hm: Heatmap, showLabels: bool) =
  hm.showLabels = showLabels
  hm.calculateMaxVisible()
  if hm.visibility:
    hm.render()

proc `showValues=`*(hm: Heatmap, showValues: bool) =
  hm.showValues = showValues
  if hm.visibility:
    hm.render()

proc `showColorbar=`*(hm: Heatmap, showColorbar: bool) =
  hm.showColorbar = showColorbar
  hm.calculateMaxVisible()
  if hm.visibility:
    hm.render()

proc `cellWidth=`*(hm: Heatmap, width: int) =
  hm.cellWidth = max(1, width)
  hm.calculateMaxVisible()
  if hm.visibility:
    hm.render()

proc `cellHeight=`*(hm: Heatmap, height: int) =
  hm.cellHeight = max(1, height)
  hm.calculateMaxVisible()
  if hm.visibility:
    hm.render()

proc setScale*(hm: Heatmap, minValue, maxValue: float) =
  hm.minValue = minValue
  hm.maxValue = maxValue
  hm.autoScale = false
  if hm.visibility:
    hm.render()

# Navigation helpers
proc scrollToPosition*(hm: Heatmap, row, col: int) =
  let totalRows = hm.data.len
  let totalCols = if hm.data.len > 0: hm.data[0].len else: 0
  
  # Clamp to valid ranges
  let targetRow = max(0, min(row, totalRows - hm.maxVisibleRows))
  let targetCol = max(0, min(col, totalCols - hm.maxVisibleCols))
  
  hm.scrollOffsetY = targetRow
  hm.scrollOffsetX = targetCol
  hm.calculateMaxVisible()
  if hm.visibility:
    hm.render()

proc scrollHome*(hm: Heatmap) =
  hm.scrollOffsetX = 0
  hm.scrollOffsetY = 0
  hm.calculateMaxVisible()
  if hm.visibility:
    hm.render()

proc scrollEnd*(hm: Heatmap) =
  let totalRows = hm.data.len
  let totalCols = if hm.data.len > 0: hm.data[0].len else: 0
  
  hm.scrollOffsetY = max(0, totalRows - hm.maxVisibleRows)
  hm.scrollOffsetX = max(0, totalCols - hm.maxVisibleCols)
  hm.calculateMaxVisible()
  if hm.visibility:
    hm.render()

# Enhanced data creation helpers
proc createRandomHeatmapData*(rows, cols: int, minVal = 0.0, maxVal = 100.0): HeatmapData =
  result = newSeq[seq[float]](rows)
  for i in 0..<rows:
    result[i] = newSeq[float](cols)
    for j in 0..<cols:
      result[i][j] = minVal + (maxVal - minVal) * rand(1.0)

proc createGradientHeatmapData*(rows, cols: int): HeatmapData =
  result = newSeq[seq[float]](rows)
  for i in 0..<rows:
    result[i] = newSeq[float](cols)
    for j in 0..<cols:
      # Create a gradient from top-left to bottom-right
      let value = (i.float + j.float) / (rows.float + cols.float - 2.0)
      result[i][j] = value * 100.0

# Example data creation
proc createSampleData*(): (HeatmapData, seq[string], seq[string]) =
  let boroughs = @["BRONX", "BROOKLYN", "MANHATTAN", "QUEENS", "STATEN ISLAND"]
  let years = @["2010", "2011", "2012", "2013", "2014", "2015", "2016", "2017"]
  
  var data = newSeq[seq[float]](boroughs.len)
  for i in 0..<boroughs.len:
    data[i] = newSeq[float](years.len)
    for j in 0..<years.len:
      # Create sample data similar to the image
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