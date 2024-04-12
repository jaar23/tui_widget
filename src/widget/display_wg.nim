import illwill, base_wg, os, std/wordwrap, strutils, options, tables

# Doesn't work nice when rendering a lot of character rather than 
# alphanumeric text.
# Try to convert the source text to alphanumeric text before run it
type
  CustomRowRecal* = proc(text: string, dp: ref Display): seq[string]

  Display* = object of BaseWidget
    text: string = ""
    textRows: seq[string] = newSeq[string]()
    wordwrap*: bool = false
    useCustomTextRow* = false
    customRowRecal: Option[CustomRowRecal]
    events*: Table[string, EventFn[ref Display]]
    keyEvents*: Table[Key, EventFn[ref Display]]


const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.None, Key.Up,
                          Key.Down, Key.PageUp, Key.PageDown, Key.Home,
                          Key.End, Key.Left, Key.Right, Key.ShiftW}


proc newDisplay*(px, py, w, h: int,
                 title: string = "", text: string = "", border: bool = true,
                 statusbar = true, wordwrap = false,
                 fgColor: ForegroundColor = fgWhite,
                 bgColor: BackgroundColor = bgNone,
                 customRowRecal: Option[CustomRowRecal] = none(CustomRowRecal),
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
    style: style,
    wordwrap: wordwrap,
    customRowRecal: customRowRecal,
    useCustomTextRow: if customRowRecal.isSome: true else: false
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
      # Add 1 for newline character
      currentOffset += lineLen + 1 
    else:
      if currentOffset < offset and offset < lineLen:
        let startIndex = offset - currentOffset
        # Append the remaining part of the line
        visibleText.add(line[startIndex..^1]) 
        currentOffset = offset
      else:
        visibleText.add(line)
      if visibleText.len >= width:
        # Trim to fit within width
        formattedText.add(visibleText[0..width-1]) 
        visibleText = ""
        continue
    visibleText = alignLeft(visibleText, max(width, visibleText.len), ' ')
    if visibleText.len > 0:
      formattedText.add(visibleText[0..^1])
    else:
      formattedText.add("")
  return formattedText


proc rowReCal(dp: ref Display) =
  if dp.wordwrap:
    let rows = dp.text.len / toInt(dp.width.toFloat() * 0.5)
    dp.textRows = dp.text.splitBySize(dp.x2 - dp.x1, toInt(rows) +
        dp.style.paddingX2)
  else:
    dp.textRows = textWindow(dp.text, dp.x2 - dp.x1, dp.cursor)


method render*(dp: ref Display) =
  if not dp.illwillInit: return
  if dp.useCustomTextRow: 
    let customFn = dp.customRowRecal.get
    dp.textRows = customFn(dp.text, dp)
  else: 
    dp.rowReCal() 
  dp.clear()
  dp.renderBorder()
  dp.renderTitle()
  var index = 1
  if dp.textRows.len > 0:
    let rowStart = min(dp.rowCursor, dp.textRows.len - 1)
    let rowEnd = min(dp.textRows.len - 1, dp.rowCursor + dp.size -
        dp.statusbarSize)
    setDoubleBuffering(false)
    for row in dp.textRows[rowStart..min(rowEnd, dp.textRows.len)]:
      dp.renderCleanRow(index)
      dp.renderRow(row, index)
      inc index
    ## cursor pointer
  if dp.statusbar:
    let statusbarText = "size: " & $(dp.text.len/1024).toInt() & "kb"
    dp.renderCleanRect(dp.x1, dp.height, statusbarText.len, dp.height)
    dp.tb.write(dp.x1, dp.height, fgCyan, statusbarText, resetStyle)
  dp.tb.display()
  setDoubleBuffering(true)


proc resetCursor*(dp: ref Display) =
  dp.rowCursor = 0
  dp.cursor = 0


proc on*(dp: ref Display, event: string, fn: EventFn[ref Display]) =
  dp.events[event] = fn


proc on*(dp: ref Display, key: Key, fn: EventFn[ref Display]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  dp.keyEvents[key] = fn
    


proc call*(dp: ref Display, event: string) =
  let fn = dp.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(dp)


proc call(dp: ref Display, key: Key) =
  let fn = dp.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(dp)


method onControl*(dp: ref Display) =
  if dp.visibility == false: 
    dp.cursor = 0
    dp.rowCursor = 0
    return
  dp.focus = true
  if dp.useCustomTextRow: 
    let customFn = dp.customRowRecal.get
    dp.textRows = customFn(dp.text, dp)
  else: 
    dp.rowReCal() 
  dp.clear()
  while dp.focus:
    var key = getKeyWithTimeout(dp.refreshWaitTime)
    case key
    of Key.None: dp.render()
    of Key.Up:
      dp.rowCursor = max(0, dp.rowCursor - 1)
    of Key.Down:
      dp.rowCursor = min(dp.rowCursor + 1, max(dp.textRows.len - dp.size, 0))
    of Key.Right:
      dp.cursor += 1
      if dp.cursor >= dp.x2 - dp.x1:
        dp.cursor = dp.x2 - dp.x1 - 1
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
    of Key.ShiftW:
      dp.wordwrap = not dp.wordwrap
    else:
      if key in forbiddenKeyBind: discard
      elif dp.keyEvents.hasKey(key):
        dp.call(key)

  dp.render()
  sleep(dp.refreshWaitTime)


method wg*(dp: ref Display): ref BaseWidget = dp


proc text*(dp: ref Display): string = dp.text


proc val(dp: ref Display, val: string) =
  dp.clear()
  dp.text = val
  if dp.useCustomTextRow: 
    let customFn = dp.customRowRecal.get
    dp.textRows = customFn(dp.text, dp)
  else: 
    dp.rowReCal()
  dp.render()


proc `text=`*(dp: ref Display, text: string) =
  dp.val(text)


proc `text=`*(dp: ref Display, text: string, customRowRecal: proc(text: string, dp: ref Display): seq[string]) =
  dp.textRows = customRowRecal(text, dp)
  dp.useCustomTextRow = true
  dp.val(text)


proc `wordwrap=`*(dp: ref Display, wrap: bool) =
  if dp.visibility:
    dp.wordwrap = wrap
    dp.render()


proc add*(dp: ref Display, text: string) =
  dp.val(dp.text & text)
