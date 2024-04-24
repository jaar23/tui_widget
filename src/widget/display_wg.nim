import illwill, base_wg, os, std/wordwrap, strutils, options, tables, label_wg
import threading/channels

# Doesn't work nice when rendering a lot of character rather than 
# alphanumeric text.
# Try to convert the source text to alphanumeric text before run it
type
  CustomRowRecal* = proc(text: string, dp: Display): seq[string]

  DisplayObj* = object of BaseWidget
    text: string = ""
    textRows: seq[string] = newSeq[string]()
    wordwrap*: bool = false
    useCustomTextRow* = false
    customRowRecal*: Option[CustomRowRecal]
    events*: Table[string, EventFn[Display]]
    keyEvents*: Table[Key, EventFn[Display]]

  Display* = ref DisplayObj

proc help(dp: Display, args: varargs[string]): void

proc on*(dp: Display, key: Key, fn: EventFn[Display]) {.raises: [EventKeyError].}

const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.None, Key.Up,
                          Key.Down, Key.PageUp, Key.PageDown, Key.Home,
                          Key.End, Key.Left, Key.Right, Key.ShiftW}


proc newDisplay*(px, py, w, h: int, id = "";
                 title: string = "", text: string = "", border: bool = true,
                 statusbar = true, wordwrap = false, enableHelp = false,
                 bgColor: BackgroundColor = bgNone,
                 fgColor: ForegroundColor = fgWhite,
                 customRowRecal: Option[CustomRowRecal] = none(CustomRowRecal),
                 tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): Display =
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
  result = (Display)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    text: text,
    size: h - statusbarSize - py - (padding * 2),
    statusbarSize: statusbarSize,
    enableHelp: enableHelp,
    title: title,
    statusbar: statusbar,
    tb: tb,
    style: style,
    wordwrap: wordwrap,
    customRowRecal: customRowRecal,
    useCustomTextRow: if customRowRecal.isSome: true else: false,
    events: initTable[string, EventFn[Display]](),
    keyEvents: initTable[Key, EventFn[Display]]()
  )
  result.helpText = " [W]   toggle wordwrap\n" &
                    " [?]   for help\n" &
                    " [Tab]  to go next widget\n" & 
                    " [Esc] to exit this window"
 
  result.channel = newChan[WidgetBgEvent]()
  if enableHelp:
    result.on(Key.QuestionMark, help)
  result.keepOriginalSize()


proc newDisplay*(px, py: int, w, h: WidgetSize, id = "";
                 title = "", text = "", border = true,
                 statusbar = true, wordwrap = false, enableHelp = false,
                 bgColor = bgNone,
                 fgColor = fgWhite,
                 customRowRecal: Option[CustomRowRecal] = none(CustomRowRecal),
                 tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): Display =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newDisplay(px, py, width, height, id, title, text, border,
                    statusbar, wordwrap, enableHelp, bgColor, fgColor,
                    customRowRecal, tb)


proc newDisplay*(id: string): Display =
  var display = Display(
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
    events: initTable[string, EventFn[Display]](),
    keyEvents: initTable[Key, EventFn[Display]]()
  )

  display.helpText = " [W]   toggle wordwrap\n" &
                     " [?]   for help\n" &
                     " [Tab]  to go next widget\n" & 
                     " [Esc] to exit this window"
  display.on(Key.QuestionMark, help)
  display.channel = newChan[WidgetBgEvent]()
  return display
 


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


proc rowReCal(dp: Display) =
  if dp.wordwrap:
    let rows = dp.text.len / toInt(dp.x2.toFloat() * 0.5)
    dp.textRows = dp.text.splitBySize(dp.x2 - dp.x1, toInt(rows) +
        dp.style.paddingX2)
  else:
    dp.textRows = textWindow(dp.text, dp.x2 - dp.x1, dp.cursor)


proc help(dp: Display, args: varargs[string]) = 
  let wsize = ((dp.width - dp.posX).toFloat * 0.3).toInt()
  let hsize = ((dp.height - dp.posY).toFloat * 0.3).toInt()
  var display = newDisplay(dp.x2 - wsize, dp.y2 - hsize, 
                          dp.x2, dp.y2, title="help",
                          bgColor=bgWhite, fgColor=fgBlack,
                          tb=dp.tb, statusbar=false, 
                          enableHelp=false)
  var helpText: string = if dp.helpText == "":
    " [Enter] to select\n" &
    " [?]     for help\n" &
    " [Tab]   to go next widget\n" & 
    " [Esc]   to exit this window"
  else: dp.helpText
  display.text = helpText
  display.illwillInit = true
  dp.render()
  display.onControl()
  display.clear()


proc renderStatusbar(dp: Display) =
  ## custom statusbar rendering uses event name 'statusbar'
  if dp.events.hasKey("statusbar"):
    dp.call("statusbar")
  else:
    dp.statusbarText = " " & $dp.rowCursor & ":" & $(max(0, dp.textRows.len() - dp.size)) & " "
    dp.renderCleanRect(dp.x1, dp.height, dp.statusbarText.len, dp.height)
    dp.tb.write(dp.x1, dp.height, bgBlue, fgWhite, dp.statusbarText, 
                resetStyle)
    
    let ww = " W "
    let q = "[?]"
    if dp.enableHelp:
      dp.tb.write(dp.x2 - len(q), dp.height, bgWhite, fgBlack,
                  q, resetStyle)
    if dp.wordwrap:
      dp.tb.write(dp.x2 - len(ww & q), dp.height, bgWhite, fgBlack,
                  ww, resetStyle)


method resize*(dp: Display) =
  let statusbarSize = if dp.statusbar: 1 else: 0
  dp.size = dp.height - statusbarSize - dp.posY - (dp.paddingY1 * 2)


method render*(dp: Display) =
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
    let rowEnd = min(dp.textRows.len - 1, rowStart + dp.size)
    #setDoubleBuffering(false)
    for row in dp.textRows[rowStart..min(rowEnd, dp.textRows.len - 1)]:
      #dp.renderCleanRow(index)
      dp.renderRow(row, index)
      inc index
  if dp.statusbar:
    dp.renderStatusbar()
  
  dp.tb.display()
  #setDoubleBuffering(true)


proc resetCursor*(dp: Display) =
  dp.rowCursor = 0
  dp.cursor = 0


proc on*(dp: Display, event: string, fn: EventFn[Display]) =
  dp.events[event] = fn


proc on*(dp: Display, key: Key, fn: EventFn[Display]) {.raises: [EventKeyError].} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  dp.keyEvents[key] = fn
    

method call*(dp: Display, event: string, args: varargs[string]) =
  let fn = dp.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(dp, args)


method call*(dp: DisplayObj, event: string, args: varargs[string]) =
  let fn = dp.events.getOrDefault(event, nil)
  if not fn.isNil:
    let dpRef = dp.asRef()
    fn(dpRef, args)
    

proc call(dp: Display, key: Key) =
  let fn = dp.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(dp)


method poll*(dp: Display) =
  var widgetEv: WidgetBgEvent
  if dp.channel.tryRecv(widgetEv):
    dp.call(widgetEv.event, widgetEv.args)
    dp.render()


method onUpdate*(dp: Display, key: Key) =
  # reset
  if dp.visibility == false: 
    dp.cursor = 0
    dp.rowCursor = 0
    return
  
  # dp.focus = true
  # if dp.useCustomTextRow: 
  #   let customFn = dp.customRowRecal.get
  #   dp.textRows = customFn(dp.text, dp)
  # else: 
  #   dp.rowReCal() 
  #dp.clear()

  # key binding action
  case key
  of Key.None: discard
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
  #sleep(dp.refreshWaitTime)


method onControl*(dp: Display) =
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
    dp.onUpdate(key)
    sleep(dp.refreshWaitTime)


method wg*(dp: Display): ref BaseWidget = dp


proc text*(dp: Display): string = dp.text


proc val(dp: Display, val: string) =
  dp.text = val
  if dp.width > 0:
    if dp.useCustomTextRow: 
      let customFn = dp.customRowRecal.get
      dp.textRows = customFn(dp.text, dp)
    else: 
      dp.rowReCal()
    dp.render()


proc `text=`*(dp: Display, text: string) =
  dp.val(text)


proc `text=`*(dp: Display, text: string, customRowRecal: proc(text: string, dp: Display): seq[string]) =
  dp.textRows = customRowRecal(text, dp)
  dp.useCustomTextRow = true
  dp.val(text)


proc `wordwrap=`*(dp: Display, wrap: bool) =
  if dp.visibility:
    dp.wordwrap = wrap
    dp.render()


proc add*(dp: Display, text: string, autoScroll=false) =
  dp.text &= text
  dp.val(dp.text)
  if autoScroll and dp.textRows.len > dp.size: 
    dp.rowCursor = min(dp.textRows.len - 1, dp.rowCursor + 1)


