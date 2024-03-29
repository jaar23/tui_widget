import illwill, base_wg, os, std/wordwrap, strutils

type
  Display = object of BaseWidget
    text: string = ""
    textRows: seq[string] = newSeq[string]()
    rowCursor: int = 0
    cursor: int = 0
    longestStrSize: int = 0


proc newDisplay*(px, py, w, h: int,
                 title: string = "", text: string = "", border: bool = true,
                 statusbar = true, fgColor: ForegroundColor = fgWhite,
                 bgColor: BackgroundColor = bgNone,
                 tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): ref Display =
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
  result = (ref Display)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    text: text,
    size: h - statusbarSize - py,
    statusbarSize: statusbarSize,
    title: title,
    statusbar: statusbar,
    tb: tb,
    style: style
  )


proc splitBySize(val: string, size: int, rows: int,
                 visualSkip = 2): seq[string] =
  if val.len() > size:
    var wrappedWords = val.wrapWords(maxLineWidth = size - visualSkip,
        splitLongWords = false)
    var lines = wrappedWords.split("\n")
    return lines
  else:
    var lines = val.split("\n")
    return lines


proc textWindow(text: string, width: int, offset: int): seq[string] =
  var formattedText = newSeq[string]()
  let lines = text.splitLines()
  for line in lines:
    if line == "": continue
    var visibleText = ""
    var currentOffset = 0
    let lineLen = line.len
    if currentOffset + lineLen <= offset:
      currentOffset += lineLen + 1 # Add 1 for newline character
    else:
      if currentOffset < offset and offset < lineLen:
        let startIndex = offset - currentOffset
        visibleText.add(line[startIndex..^1]) # Append the remaining part of the line
        currentOffset = offset
      else:
        #if line.len > 0:
        visibleText.add(line)
        # currentOffset += lineLen + 1 # Add 1 for newline character
      if visibleText.len >= width:
        formattedText.add(visibleText[0..width-1]) # Trim to fit within width
        # formattedText.add("\n")
        visibleText = ""
        continue
    if visibleText.len > 0:
      formattedText.add(visibleText[0..^1])
    else:
      formattedText.add("")
  
  # remove unwanted empty space from original text
  # if formattedText.len > lines.len:
  #   for i in lines.len:
  #     if formattedText.contains(lines[i]):
  #       continue
  #     else:
  #       formattedText.delete()
  return formattedText


proc rowReCal(dp: ref Display) =
  let rows = dp.text.len / toInt(dp.width.toFloat() * 0.5)
  # let textRows = dp.text.splitBySize(dp.widthPaddRight, toInt(rows) + dp.style.paddingX2)
  dp.textRows = textWindow(dp.text, dp.x2 - dp.x1, dp.cursor)
  # for line in dp.textRows:
  #   if dp.longestStrSize < line.len:
  #     dp.longestStrSize = line.len
  # return textRows


method render*(dp: ref Display) =
  dp.rowReCal()
  dp.clear()
  dp.renderBorder()
  dp.renderTitle()
  var index = 1
  if dp.textRows.len > 0:
    let rowStart = min(dp.rowCursor, dp.textRows.len - 1)
    # let textRows = textWindow(dp.text, dp.x2 - dp.x1, dp.cursor)
    # let rowEnd = min(textRows.len - 1, dp.rowCursor + dp.size - dp.statusbarSize)
    #echo textRows
    let rowEnd = min(dp.textRows.len - 1, dp.rowCursor + dp.size -
        dp.statusbarSize)
    for row in dp.textRows[rowStart..min(rowEnd, dp.textRows.len)]:
    # for row in textRows[rowStart..min(rowEnd, textRows.len)]:
      dp.renderCleanRow(index)
      dp.renderRow(row, index)
      inc index
    ## cursor pointer
  if dp.statusbar:
    dp.renderCleanRect(dp.x1, dp.height, dp.x1 + 6, dp.height)
    dp.tb.write(dp.x1, dp.height, fgYellow, "rows: ", $dp.rowCursor, "|",
        $dp.cursor, resetStyle)
  dp.tb.display()


method onControl*(dp: ref Display) =
  dp.focus = true
  dp.rowReCal()
  while dp.focus:
    var key = getKey()
    case key
    of Key.None:
      dp.render()
    of Key.Up:
      dp.rowCursor = max(0, dp.rowCursor - 1)
    of Key.Down:
      dp.rowCursor = min(dp.rowCursor + 1, max(dp.textRows.len - dp.size, 0))
    of Key.Right:
      dp.cursor += 1
      if dp.cursor >= dp.x2 - dp.x1:
        dp.cursor = dp.x2 - dp.x1 - 1
      # if dp.cursor >= dp.longestStrSize:
      #   dp.cursor = dp.longestStrSize  1
    of Key.Left:
      dp.cursor = max(0, (dp.cursor - 1))
    of Key.PageUp:
      dp.rowCursor = max(0, dp.rowCursor - dp.size)
    of Key.PageDown:
      dp.rowCursor = min(dp.rowCursor + dp.size, max(dp.textRows.len - dp.size, 0))
    of Key.Home:
      dp.rowCursor = 0
    of Key.End:
      dp.rowCursor = max(dp.textRows.len - dp.size, 0)
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
  dp.rowReCal()


proc `text=`*(dp: ref Display, text: string) =
  dp.clear()
  dp.text = text
  dp.rowReCal()
  dp.render()

