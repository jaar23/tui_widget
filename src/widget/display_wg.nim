import illwill, base_wg, os, std/wordwrap, strutils

type
  Display = object of BaseWidget
    text*: string = ""
    textRows: seq[string] = newSeq[string]()
    rowCursor: int = 0


proc newDisplay*(px, py, w, h: int, 
                 title: string = "", text: string = "", border: bool = true, statusbar = true,
                 fgColor: ForegroundColor = fgWhite, bgColor: BackgroundColor = bgNone,
                 tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): ref Display =
  let padding = if border: 2 else: 1
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
  result = (ref Display)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    text: text,
    size: h - (padding * 2) - statusbarSize,
    statusbarSize: statusbarSize,
    title: title,
    tb: tb,
    style: style
  )


proc splitBySize(val: string, size: int, rows: int, 
                 visualSkip = 2): seq[string] =
  var wrappedWords = val.wrapWords(maxLineWidth=size - visualSkip, splitLongWords=false)
  var lines = wrappedWords.split("\n")
  return lines


proc rowReCal(dp: ref Display): seq[string] =
  let rows = dp.text.len / toInt(dp.width.toFloat() * 0.5)
  let textRows = dp.text.splitBySize(dp.widthPaddRight, toInt(rows) + dp.style.paddingX2)
  return textRows


method render*(dp: ref Display) =
  dp.renderBorder()
  if dp.title != "":
    dp.renderTitle()
  var index = 1
  let rowStart = dp.rowCursor
  let rowEnd = min(dp.textRows.len - 1, dp.rowCursor + dp.size - dp.statusbarSize)
  for row in dp.textRows[rowStart..min(rowEnd, dp.textRows.len)]:
    dp.renderCleanRow(index)
    dp.renderRow(row, index)
    inc index
  ## cursor pointer
  dp.renderCleanRect(dp.x1, dp.height, dp.x1 + 6, dp.height)
  dp.tb.write(dp.x1, dp.height, fgYellow, "rows: ", $dp.rowCursor, resetStyle)
  dp.tb.display()
 

method onControl*(dp: ref Display) =
  dp.focus = true
  let textRows = dp.rowReCal()
  dp.textRows = textRows
  while dp.focus:
    var key = getKey()
    case key
    of Key.None: 
      dp.render()
    of Key.Up:
      dp.rowCursor = max(0, dp.rowCursor - 1)
    of Key.Down:
      dp.rowCursor = min(dp.rowCursor + 1, dp.textRows.len - dp.size)
    of Key.PageUp:
      dp.rowCursor = max(0, dp.rowCursor - dp.size)
    of Key.PageDown:
      dp.rowCursor = min(dp.rowCursor + dp.size, dp.textRows.len - dp.size)
    of Key.Home:
      dp.rowCursor = 0
    of Key.End:
      dp.rowCursor = dp.textRows.len - dp.size
    of Key.Escape, Key.Tab:
      dp.focus = false
    else: discard
  dp.render()
  sleep(20)
 

method wg*(dp: ref Display): ref BaseWidget = dp


proc show*(dp: ref Display) = dp.render()


proc hide*(dp: ref Display) = dp.clear()


proc text*(dp: ref Display, text: string) = dp.text = text


proc text*(dp: ref Display): string = dp.text


proc terminalBuffer*(dp: ref Display): var TerminalBuffer =
  return dp.tb


proc `-`*(dp: ref Display) = dp.show()


proc add*(dp: ref Display, text: string) =
  dp.text = dp.text & text
  dp.textRows = dp.rowReCal()


