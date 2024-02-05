import illwill, base_wg, os, std/wordwrap, strutils

type
  Display = object of BaseWidget
    rows*: int = 1
    text*: string = ""
    textRows: seq[string] = newSeq[string]()
    cursor: int = 0
    rowCursor: int = 0
    visualSkip: int = 2
    title: string


proc newDisplay*(w, h, px, py: int, title: string = "", 
                 text: string = "",
                 tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): ref Display =
  var display = (ref Display)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    text: text,
    rows: h - 4,
    title: title,
    tb: tb
  )
  return display


proc splitBySize(val: string, size: int, rows: int, 
                 visualSkip = 2): (seq[string], int) =
  var wrappedWords = val.wrapWords(maxLineWidth=size - visualSkip, splitLongWords=false)
  var lines = wrappedWords.split("\n")
  var cursor = wrappedWords.len
  return (lines, cursor)


proc rowReCal(dp: ref Display): seq[string] =
  let rows = dp.text.len / toInt(dp.width.toFloat() * 0.5)
  let (textRows, cursor) = dp.text.splitBySize(dp.width - dp.visualSkip, toInt(
      rows) + 2)
  dp.cursor = cursor
  return textRows
  #return textRows.filter(proc(x: string): bool = x.len != 0)


proc render*(dp: ref Display, display = true) =
  if display:
    dp.tb.drawRect(dp.width, dp.height + 2, dp.posX, dp.posY,
        doubleStyle = dp.focus)
    if dp.title != "":
      dp.tb.write(dp.posX + dp.visualSkip, dp.posY, dp.title)
    var index = 1
    let rowStart = dp.rowCursor
    let rowEnd = if dp.rowCursor + dp.rows >= dp.textRows.len: dp.textRows.len -
        1 else: dp.rowCursor + dp.rows - 1
    for row in dp.textRows[rowStart..min(rowEnd, dp.textRows.len)]:
      dp.tb.fill(dp.posX + dp.visualSkip, dp.posY + index, dp.width, dp.height, " ")
      dp.tb.drawVertLine(dp.width, dp.height, dp.posY + 1, doubleStyle = true)
      dp.tb.write(dp.posX + dp.visualSkip, dp.posY + index, resetStyle, row)
      index = index + 1
    ## cursor pointer
    dp.tb.fill(dp.posX + dp.visualSkip, dp.posY + dp.rows + dp.visualSkip, dp.posX + 9,
        dp.posY + dp.rows + dp.visualSkip, " ")
    dp.tb.write(dp.posX + dp.visualSkip, dp.posY + dp.rows + dp.visualSkip, fgYellow,
        "rows: ", $dp.rowCursor, resetStyle)
    dp.tb.display()
  else:
    echo "not implement"


# TODO: scroll left right when no word wrap
method onControl*(dp: ref Display) =
  dp.focus = true
  let textRows = dp.rowReCal()
  dp.textRows = textRows
  while dp.focus:
    var key = getKey()
    case key
    of Key.None: 
      dp.render(true)
    of Key.Up:
      if dp.rowCursor == 0:
        dp.rowCursor = 0
      else:
        dp.rowCursor = dp.rowCursor - 1
    of Key.Down:
      if dp.rowCursor + dp.rows > dp.textRows.len:
        dp.rowCursor = dp.rowCursor
      else:
        dp.rowCursor = dp.rowCursor + 1
    of Key.PageUp:
      if dp.rowCursor <= 0:
        dp.rowCursor = 0
      else:
        if dp.rowCursor - 4 < 0:
          dp.rowCursor = dp.rowCursor + (dp.rowCursor - 4)
        else:
          dp.rowCursor = dp.rowCursor - 4
    of Key.PageDown:
      if dp.rowCursor + dp.rows > dp.textRows.len:
        dp.rowCursor = dp.rowCursor
      else:
        dp.rowCursor = dp.rowCursor + 4
    of Key.Home:
      dp.rowCursor = 0
    of Key.End:
      dp.rowCursor = dp.textRows.len - dp.rows
    of Key.Escape, Key.Tab:
      dp.focus = false
    else: discard
  dp.render(true)
  sleep(20)
 

proc show*(dp: ref Display) = dp.render()


proc hide*(dp: ref Display) = dp.render(false)


proc text*(dp: ref Display, text: string) = dp.text = text


proc text*(dp: ref Display): string = dp.text


proc terminalBuffer*(dp: ref Display): var TerminalBuffer =
  return dp.tb


proc merge*(dp: ref Display, wg: BaseWidget) =
  dp.tb.copyFrom(wg.tb, wg.posX, wg.posY, wg.width, wg.height, wg.posX, wg.posY, transparency=true)


proc `-`*(dp: ref Display) = dp.show()


proc add*(dp: ref Display, text: string) =
  dp.text = dp.text & text
  dp.textRows = dp.rowReCal()


