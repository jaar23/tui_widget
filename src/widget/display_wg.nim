import illwill, base_wg, os, std/wordwrap, strutils

type
  Display = ref object of BaseWidget
    rows*: int = 1
    text*: string = ""
    textRows: seq[string] = newSeq[string]()
    cursor: int = 0
    rowCursor: int = 0
    visualSkip: int = 2
    title: string


proc newDisplay*(w, h, px, py: int, title: string = "", text: string = "",
                tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): Display =
  var display = Display(
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


proc splitBySize(val: string, size: int, rows: int, visualSkip = 2): (seq[string], int) =
  var wrappedWords = val.wrapWords(maxLineWidth=size - visualSkip, splitLongWords=false)
  var lines = wrappedWords.split("\n")
  var cursor = wrappedWords.len
  #var textArr = toSeq(wrappedWords.items)
  #var cursor = 0
  #var lines = newSeq[string]()
  # for n in 0..rows:
  #   var line = ""
  #   var wordCnt = 0
  #   for t in textArr[cursor..textArr.len - 1]:
  #     wordCnt = wordCnt + 1
  #     if @["\n", "\L"].contains($t):
  #       break
  #     line = line & $t
  #     # if wordCnt == size:
  #     #   break
  #   if line.len > 0:
  #     lines.add(line)
  #   cursor = cursor + wordCnt
  return (lines, cursor)


proc rowReCal(dp: var Display): seq[string] =
  let rows = dp.text.len / toInt(dp.width.toFloat() * 0.5)
  let (textRows, cursor) = dp.text.splitBySize(dp.width - dp.visualSkip, toInt(
      rows) + 2)
  dp.cursor = cursor
  return textRows
  #return textRows.filter(proc(x: string): bool = x.len != 0)


proc render*(dp: var Display, standalone = false) =
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
  if standalone:
    dp.tb.display()


method onControl*(dp: var Display) =
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
 

proc show*(dp: var Display) = dp.render(true)


proc hide*(dp: var Display) = dp.render()


proc text*(dp: var Display, text: string) = dp.text = text


proc text*(dp: var Display): string = dp.text


proc terminalBuffer*(dp: var Display): var TerminalBuffer =
  return dp.tb


proc merge*(dp: var Display, wg: BaseWidget) =
  dp.tb.copyFrom(wg.tb, wg.posX, wg.posY, wg.width, wg.height, wg.posX, wg.posY, transparency=true)


proc `-`*(dp: var Display) = dp.show()


proc add*(dp: var Display, text: string) =
  dp.text = dp.text & text
  dp.textRows = dp.rowReCal()


