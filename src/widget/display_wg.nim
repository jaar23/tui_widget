import illwill, base_wg, os, std/wordwrap, strutils

type
  Display = object of BaseWidget
    size*: int = 1
    text*: string = ""
    textRows: seq[string] = newSeq[string]()
    rowCursor: int = 0
    title: string


proc newDisplay*(w, h, px, py: int, title: string = "", 
                 text: string = "", bordered: bool = true,
                 tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): ref Display =
  let padding = if bordered: 2 else: 1
  var display = (ref Display)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    text: text,
    size: h - (padding * 2),
    title: title,
    tb: tb,
    paddingX: padding,
    paddingY: padding,
    bordered: bordered
  )
  return display


proc splitBySize(val: string, size: int, rows: int, 
                 visualSkip = 2): seq[string] =
  var wrappedWords = val.wrapWords(maxLineWidth=size - visualSkip, splitLongWords=false)
  var lines = wrappedWords.split("\n")
  return lines


proc rowReCal(dp: ref Display): seq[string] =
  let rows = dp.text.len / toInt(dp.width.toFloat() * 0.5)
  let textRows = dp.text.splitBySize(dp.width - dp.paddingX, toInt(
      rows) + dp.paddingX)
  return textRows


proc render*(dp: ref Display, display = true) =
  if display:
    if dp.bordered:
      dp.tb.drawRect(dp.width, dp.height + dp.paddingY, dp.posX, dp.posY,
          doubleStyle = dp.focus)
    if dp.title != "":
      dp.tb.write(dp.posX + dp.paddingX, dp.posY, dp.title)
    var index = 1
    let rowStart = dp.rowCursor
    let rowEnd = if dp.rowCursor + dp.size >= dp.textRows.len: dp.textRows.len -
        1 else: dp.rowCursor + dp.size - 1
    for row in dp.textRows[rowStart..min(rowEnd, dp.textRows.len)]:
      dp.tb.fill(dp.posX + dp.paddingX, dp.posY + index, dp.width - dp.paddingX, dp.height, " ")
      #dp.tb.drawVertLine(dp.width, dp.height, dp.posY + 1, doubleStyle = true)
      dp.tb.write(dp.posX + dp.paddingX, dp.posY + index, resetStyle, row)
      index = index + 1
    ## cursor pointer
    dp.tb.fill(dp.posX + dp.paddingX, dp.posY + dp.size + dp.paddingX, dp.posX + dp.size,
        dp.posY + dp.size + dp.paddingX, " ")
    dp.tb.write(dp.posX + dp.paddingX, dp.posY + dp.size + dp.paddingX, fgYellow,
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
  dp.render(true)
  sleep(20)
 

proc show*(dp: ref Display) = dp.render()


proc hide*(dp: ref Display) = dp.render(false)


proc text*(dp: ref Display, text: string) = dp.text = text


proc text*(dp: ref Display): string = dp.text


proc terminalBuffer*(dp: ref Display): var TerminalBuffer =
  return dp.tb


# proc merge*(dp: ref Display, wg: BaseWidget) =
#   dp.tb.copyFrom(wg.tb, wg.posX, wg.posY, wg.width, wg.height, wg.posX, wg.posY, transparency=true)
#

proc `-`*(dp: ref Display) = dp.show()


proc add*(dp: ref Display, text: string) =
  dp.text = dp.text & text
  dp.textRows = dp.rowReCal()


