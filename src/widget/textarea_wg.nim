import illwill, base_wg, os, sequtils, strutils, deques, times
import std/wordwrap, std/enumerate
import nimclipboard/libclipboard
import tables


type
  ViHistory = tuple[cursor: int, content: string]
  
  ViSelectDirection = enum
    Left, Right
  
  ViSelection = tuple[startat: int, endat: int, direction: ViSelectDirection]

  ViStyle* = object
    normalBg*: BackgroundColor
    insertBg*: BackgroundColor
    visualBg*: BackgroundColor
    normalFg*: ForegroundColor
    insertFg*: ForegroundColor
    visualFg*: ForegroundColor
    cursorAtLineBg*: BackgroundColor
    cursorAtLineFg*: ForegroundColor
  

  TextArea* = object of BaseWidget
    textRows: seq[string] = newSeq[string]()
    value: string = ""
    rows: int = 0
    cols: int = 0
    cursorBg: BackgroundColor = bgBlue
    cursorFg: ForegroundColor = fgWhite
    cursorStyle: CursorStyle = Block
    vimode: ViMode = Normal
    enableViMode: bool = false
    viHistory: Deque[ViHistory]
    viStyle*: ViStyle
    viSelection: ViSelection
    events*: Table[string, EventFn[ref TextArea]]
    keyEvents*: Table[Key, EventFn[ref TextArea]]


var cb = clipboard_new(nil)

cb.clipboard_clear(LCB_CLIPBOARD)

let CursorStyleArr: array[CursorStyle, string] = ["█", "|", "_"]


proc newViStyle(nbg: BackgroundColor = bgBlue, ibg: BackgroundColor = bgCyan,
                vbg: BackgroundColor = bgYellow,
                nfg: ForegroundColor = fgWhite, ifg: ForegroundColor = fgWhite, 
                vfg: ForegroundColor = fgWhite,
                calBg: BackgroundColor = bgWhite, calFg: ForegroundColor = fgBlack): ViStyle =
  result = ViStyle(
    normalBg: nbg,
    insertBg: ibg,
    visualBg: vbg,
    normalFg: nfg,
    insertFg: ifg,
    visualFg: vfg,
    cursorAtLineBg: calBg,
    cursorAtLineFg: calFg
  )


proc newTextArea*(px, py, w, h: int, title=""; val=" ";
                  border = true; statusbar = false; 
                  fgColor = fgWhite; bgColor = bgNone;
                  cursorFg = fgWhite; cursorBg = bgBlue; cursorStyle = Block,
                  enableViMode = false; vimode: ViMode = Normal;
                  viStyle: ViStyle = newViStyle();
                  tb = newTerminalBuffer(w+2, h+py)): ref TextArea =
  ## works like a HTML textarea
  ## x1---------------x2
  ## |
  ## |
  ## y1---------------y2
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
  var textArea = (ref TextArea)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    value: val,
    cols: w - px - padding,
    rows: h - py - (padding * 2),
    size: h - statusbarSize - py, 
    style: style,
    title: title,
    tb: tb,
    cursorBg: curSorBg,
    cursorFg: cursorFg,
    cursorStyle: cursorStyle,
    statusbar: statusbar,
    statusbarSize: statusbarSize,
    vimode: vimode,
    enableViMode: enableViMode,
    viHistory: initDeque[ViHistory](),
    viStyle: viStyle,
    viSelection: (startat: 0, endat: 0, direction: Right)
  )
  # to ensure key responsive, default < 50ms
  if textArea.refreshWaitTime > 50: textArea.refreshWaitTime = 50
  return textArea


func splitBySize(val: string, size: int, rows: int): seq[string] =
  result = newSeq[string]()
  if val.len > size:
    let wrappedWords = val.wrapWords(size, 
                                     seps={'\t', '\v', '\r', '\n', '\f'})
    result = wrappedWords.split("\n")
    if result[result.len - 1] != " ": result[result.len - 1] &= " "
  else:
    result.add(val)


func rowReCal(t: ref TextArea) =
  t.textRows = splitBySize(t.value, t.cols, t.rows)


func cursorMove(t: ref TextArea, moved: int) =
  t.cursor = t.cursor + moved
  if t.cursor > t.value.len: t.cursor = t.value.len - 1
  if t.cursor < 0: t.cursor = 0
  if t.cursor > t.cols:
    t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)
  elif t.cursor < t.cols * max(t.rowCursor, 1):
    t.rowCursor = max(0, t.rowCursor - 1)

func enter(t: ref TextArea) =
  # find out remaining space until next line
  var rem = t.cursor - ((t.rowCursor + 1) * t.cols)
  # make rem positive
  rem = if rem < 0: rem * -1 else: rem
  # insert remaining space to push cursor to next line
  t.value.insert(repeat(' ', rem), t.cursor)
  t.cursor += rem
  t.rowReCal()
  t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)


func moveUp(t: ref TextArea) =
  t.cursor = max(0, t.cursor - t.cols)
  if t.cursor < t.cols * max(t.rowCursor, 1):
    t.rowCursor = max(0, t.rowCursor - 1)


func moveDown(t: ref TextArea) =
  t.cursor = min(t.value.len - 1, t.cursor + t.cols)
  if t.cursor > t.cols * max(t.rowCursor, 1):
    t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)


func moveLeft(t: ref TextArea) =
  t.cursor = max(0, t.cursor - 1)
  if t.cursor < t.cols * t.rowCursor:
    t.rowCursor = max(0, t.rowCursor - 1)


func moveRight(t: ref TextArea) =
  t.cursor = min(t.value.len - 1, t.cursor + 1)
  if t.cursor > t.cols * (t.rowCursor + 1):
    t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)


func moveToBegin(t: ref TextArea) =
  let beginCursor = t.rowCursor * t.cols
  t.cursor = max(0, beginCursor)


func moveToEnd(t: ref TextArea) =
  let endCursor = ((t.rowCursor + 1) * t.cols) - 1
  t.cursor = min(t.value.len - 1, endCursor)
  for p in countdown(t.cursor, 0):
    if t.value[p] == ' ': dec t.cursor
    else: break


func moveToNextWord(t: ref TextArea) =
  var charsRange = {'.', ',', ';', '"', '\'', '[', ']', 
                    '\\', '/', '-', '+', '_', '=', '?',
                    '(', ')', '*', '&', '^', '%', '$',
                    '#', '@', '!', '`', '~', '|'}
  var space = false
  for p in t.cursor ..< t.value.len:
    # handling a-z, A-Z and spaces
    if t.value[p].isAlphaNumeric() and not space:
      continue
    elif t.value[p].isAlphaNumeric() and space:
      t.cursor = p
      space = false
      break
    # skip spaces
    if t.value[p] == ' ':
      space = true
      continue
    # handling special chars
    if t.value[p] in charsRange and p != t.cursor:
      t.cursor = p
      space = false
      break
    else: continue
  if t.cursor > t.cols * (t.rowCursor + 1):
    t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)



func moveToPrevWord(t: ref TextArea) =
  var charsRange = {'.', ',', ';', '"', '\'', '[', ']', 
                    '\\', '/', '-', '+', '_', '=', '?',
                    '(', ')', '*', '&', '^', '%', '$',
                    '#', '@', '!', '`', '~', '|'}
  var space = false
  for p in countdown(t.cursor, 0):
    # handling a-z, A-Z and spaces
    if t.value[p].isAlphaNumeric() and not space:
      continue
    elif t.value[p].isAlphaNumeric() and space: 
      t.cursor = p 
      space = false
      break
    # skip spaces
    if t.value[p] == ' ': 
      space = true
      continue
    # handling special chars 
    if t.value[p] in charsRange and p != t.cursor:
      t.cursor = p
      space = false
      break
    else: continue
  if t.cursor < t.cols * t.rowCursor: 
    t.rowCursor = max(0, t.rowCursor - 1)



func select(t: ref TextArea) =
  t.viSelection.startat = t.cursor
  t.viSelection.endat = t.cursor


func selectMoveLeft(t: ref TextArea, key: Key) =
  if key in {Key.Left, Key.H}:
    t.moveLeft()
  elif key in {Key.Home, Key.Caret}:
    t.moveToBegin()
  elif key in {Key.UP, Key.K}:
    t.moveUp()
  elif key == Key.B:
    t.moveToPrevWord()

  if t.viSelection.startat <= t.cursor:
    t.viSelection.endat = t.cursor
    t.viSelection.direction = Right
  else:
    t.viSelection.startat = t.cursor
    t.viSelection.direction = Left


func selectMoveRight(t: ref TextArea, key: Key) =
  if key in {Key.Right, Key.L}:  
    t.moveRight()
  elif key in {Key.End, Key.Dollar}:
    t.moveToEnd()
  elif key in {Key.Down, Key.J}:
    t.moveDown()
  elif key == Key.W:
    t.moveToNextWord()

  if t.viSelection.endat >= t.cursor:
    t.viSelection.startat = t.cursor
    t.viSelection.direction = Left
  else:
    t.viSelection.endat = t.cursor
    t.viSelection.direction = Right


func delAtCursor(t: ref TextArea) =
  if t.value.len > 0:
    t.value.delete(t.cursor .. t.cursor)
  if t.cursor == t.value.len: t.value &= " "


func delAtStartEndCursor(t: ref TextArea, startat, endat: int) =
  try:
    if t.value.len > 0:
      let endat2 = if endat == t.value.len - 1: endat - 1 else: endat
      t.value.delete(startat .. endat2)
    # keep last cursor at space if needed
    if t.value[^1] != ' ': t.value &= " "
    elif t.value.len < 1: t.value = " "
    # ensure cursor positios
    if t.cursor >= t.value.len: t.cursor = t.value.len - 1
  except:
    t.statusbarText = "failed to delete selected string"


func delLine(t: ref TextArea) =
  try:
    if t.value.len > 0:
      t.moveToEnd()
      let endCursor = t.cursor
      t.moveToBegin()
      let startCursor = t.cursor
      t.viHistory.addLast((cursor: t.cursor, content: t.value[startCursor..endCursor]))
      t.value.delete(startCursor..endCursor)
      t.moveToPrevWord()
      t.rowCursor = max(0, t.rowCursor - 1)
  except:
    t.statusbarText = "failed to delete line"


func putAtCursor(t: ref TextArea, content: string) =
  t.value.insert(content, t.cursor)
  t.cursor = t.cursor + content.len
  t.rowReCal()


func putAtCursor(t: ref TextArea, content: string, cursor: int, 
                 updateCursor = true) =
  try:
    t.value.insert(content, cursor)
    if updateCursor: t.cursor = cursor + content.len
    t.rowReCal()
  except:
    t.statusbarText = "failed to put text at cursor"
  return


func cursorAtLine(t: ref TextArea): (int, int) =
  let r = t.rowCursor * t.cols 
  let lineCursor = t.cursor - r
  return (t.rowCursor + 1, lineCursor) 



method render*(t: ref TextArea) = 
  if not t.illwillInit: return
  
  t.clear()
  t.renderBorder()
  t.renderTitle()
  t.rowReCal()

  var index = 1
  if t.textRows.len > 0:
    let rowStart = if t.rowCursor < t.size: 0 else: min(t.rowCursor - t.size + 1, t.textRows.len - 1)
    let rowEnd = min(t.textRows.len - 1, rowStart + (min(t.size - t.statusbarSize, t.rows)))
    var vcursor = if rowStart > 0: rowStart * t.cols else: 0

    for row in t.textRows[rowStart .. min(rowEnd, t.textRows.len)]:
      t.renderCleanRow(index)
      for i, c in enumerate(row.items()):
        if t.enableViMode and t.vimode == Visual:
          var bgColor = bgWhite
          var fgColor = fgBlack
          if vcursor >= t.viSelection.startat and vcursor <= t.viSelection.endat:
            t.tb.write(t.x1 + i, t.posY + index, bgColor, fgColor, $c, resetStyle)
          else:
            t.tb.write(t.x1 + i, t.posY + index, $c, resetStyle)
        else:
          if vcursor == t.cursor:
            let ch = if c == ' ': CursorStyleArr[t.cursorStyle] else: $c
            if t.cursorStyle == Ibeam:
              t.tb.write(t.x1 + i, t.posY + index, styleBlink, 
                         t.cursorBg, t.cursorFg, ch, resetStyle)
            else:
              t.tb.write(t.x1 + i, t.posY + index, styleBlink, 
                         styleUnderscore, t.cursorBg, t.cursorFg, ch, resetStyle)
          else:
            t.tb.write(t.x1 + i, t.posY + index, $c, resetStyle)
        inc vcursor 
      inc index

  if t.statusbar:
    # for debug
    # let cval = if t.value.len > 0: $t.value[t.cursor] else: " "
    # let statusbarText = $t.cursor & "|" & $t.rowCursor & "|" & cval & "|len:" & $t.value.len
    if not t.enableViMode:
      let statusbarText = " size: " & $(t.value.len - 1) & " character(s)"
      t.renderCleanRect(t.x1, t.height, statusbarText.len, t.height)
      t.tb.write(t.x1, t.height, fgCyan, statusbarText, resetStyle)

    else:
      # vi mode style for statusbar
      var bgColor = t.viStyle.normalBg
      var fgColor = t.viStyle.normalFg
      
      if t.vimode == Insert:
        bgColor = t.viStyle.insertBg
        fgColor = t.viStyle.insertFg
      elif t.vimode == Visual:
        bgColor = t.viStyle.visualBg
        fgColor = t.viStyle.visualFg

      t.tb.write(t.x1, t.height, bgColor, fgColor, center(toUpper($t.vimode), len($t.vimode) + 4), resetStyle)
      
      let (r, c) = if t.vimode == Visual: (t.viSelection.startat, t.viSelection.endat) else: t.cursorAtLine()
    
      let statusbarText = if t.statusbarText != "": t.statusbarText 
        else: " " & $r & ":" & $c
 
      t.tb.write(t.x1 + len($t.vimode) + 4, t.height, t.viStyle.cursorAtLineBg, 
                t.viStyle.cursorAtLineFg, statusbarText, resetStyle)

  t.tb.display()


proc resetCursor*(t: ref TextArea) =
  t.rowCursor = 0
  t.cursor = 0
  t.statusbarText = ""


proc commandEvent*(t: ref TextArea) =
  return


proc getKeysWithTimeout(timeout = 1000): seq[Key] =
  let numOfKey = 2
  var captured = 0
  var keyCapture = newSeq[Key]()
  let waitTime = timeout * 1000
  let startTime = now().nanosecond()
  let endTime = startTime + waitTime
  while true and now().nanosecond() < endTime:
    if captured == numOfKey: break
    let key = getKey()
    keyCapture.add(key)
    inc captured

  return keyCapture


proc identifyKey(keys: seq[Key]): Key = 
  if keys.len < 2: 
    return Key.None 
  else:
    if keys[1] == Key.None: return keys[0]
    if keys[0] == keys[1]: 
      return keys[0]
    else:
      return Key.None
    

proc normalMode(t: ref TextArea) =
  ## minimal supported of vi keybinding
  ##
  ## .. code-block::
  ##   i, Insert   = switch to insert mode 
  ##   v           = switch to visual mode
  ##   A           = append at end of line
  ##   Delete      = delete at cursor
  ##   Tab         = exit widget
  ##   Left, <-, H = move backward
  ##   Right, L    = move forward
  ##   Up, K       = move upward
  ##   Down, J     = move downward
  ##   Home, ^     = goto beginning of line
  ##   End, $      = goto end of line
  ##   w           = goto next word
  ##   b           = goto previous word
  ##   x           = cut text at cursor
  ##   p           = paste last history at cursor
  ##   u           = undo last change
  ##   dd          = delete whole line
  ##   Escape      = back to normal mode
  while true:
    let keys = getKeysWithTimeout()
    let key = identifyKey(keys)
    if key in {Key.I, Key.Insert}:
      t.vimode = Insert
      t.render()
      break
    elif key in {Key.V}:
      t.vimode = Visual
      t.select()
      t.render()
      break
    elif key == Key.ShiftA:
      t.vimode = Insert
      t.moveToEnd()
      inc t.cursor
      t.render()
      break
    elif key == Key.Delete:
      t.delAtCursor() 
    elif key == Key.Tab:
      t.focus = false
      t.render()
      break
    elif key in {Key.Left, Key.Backspace, Key.H}:
      t.moveLeft()
    elif key in {Key.Right, Key.L}: 
      t.moveRight()
    elif key in {Key.Up, Key.K}: 
      t.rowCursor = max(t.rowCursor - 1, 0)
      t.moveUp()
    elif key in {Key.Down, Key.J}: 
      t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)
      t.moveDown()
    elif key in {Key.Home, Key.Caret}:
      t.moveToBegin()
    elif key in {Key.End, Key.Dollar}:
      t.moveToEnd()
    elif key == Key.W:
      t.moveToNextWord()
      t.render()
    elif key == Key.B:
      t.moveToPrevWord()
      t.render()
    elif key == Key.X:
      if t.cursor < t.value.len:
        t.viHistory.addLast((cursor: t.cursor, content: $t.value[t.cursor]))
        t.delAtCursor()
    elif key == Key.P:
      if t.cursor < t.value.len and t.viHistory.len > 0:
        let last = t.viHistory.popLast()
        t.putAtCursor(last.content)
        t.viHistory.addLast(last)
    elif key == Key.U:
      # experiments, need more fix
      if t.cursor < t.value.len and t.viHistory.len > 0:
        let prevBuff = t.viHistory.popLast()
        t.putAtCursor(prevBuff.content, prevBuff.cursor, updateCursor=true)
    elif key == Key.D:
      t.statusbarText = " D "
      t.render()
      while true:
        var key2 = getKeyWithTimeout(1000)
        case key2
        of Key.D:
          t.delLine()
          break
        of Key.Escape: break
        else: discard
        sleep(t.refreshWaitTime)
      let (r, c) =t.cursorAtLine()
      t.statusbarText = $r & ":" & $c
      t.render()
    elif key == Key.ShiftG:
      t.cursor = t.value.len - 1
      t.rowCursor = t.textRows.len - 1
      t.render()
    elif key == Key.G:
      t.statusbarText = " G "
      t.render()
      while true:
        var key2 = getKeyWithTimeout(1000)
        case key2
        of Key.G:
          t.cursor = 0
          t.rowCursor = 0
          break
        of Key.Escape: break
        else: discard
        sleep(t.refreshWaitTime)
      let (r, c) =t.cursorAtLine()
      t.statusbarText = $r & ":" & $c
      t.render()
    elif key == Key.Colon:
      # custom command event
      t.statusbarText = " :" 
      t.render()
      t.commandEvent()
      let (r, c) = t.cursorAtLine()
      t.statusbarText = $r & ":" & $c
      t.render()
    else:
      t.vimode = Normal
      t.statusbarText = ""
      t.render()
    #sleep(t.refreshWaitTime)



# proc normalMode(t: ref TextArea) =
#   ## minimal supported of vi keybinding
#   ##
#   ## .. code-block::
#   ##   i, Insert   = switch to insert mode 
#   ##   v           = switch to visual mode
#   ##   A           = append at end of line
#   ##   Delete      = delete at cursor
#   ##   Tab         = exit widget
#   ##   Left, <-, H = move backward
#   ##   Right, L    = move forward
#   ##   Up, K       = move upward
#   ##   Down, J     = move downward
#   ##   Home, ^     = goto beginning of line
#   ##   End, $      = goto end of line
#   ##   w           = goto next word
#   ##   b           = goto previous word
#   ##   x           = cut text at cursor
#   ##   p           = paste last history at cursor
#   ##   u           = undo last change
#   ##   dd          = delete whole line
#   ##   Escape      = back to normal mode
#   # TODO: capture ctrl + v events to prevent conflicts with I
#   var keychunks = ""
#   while true:
#     var key = getKeyWithTimeout(t.refreshWaitTime)
#     if key in {Key.I, Key.Insert}:
#       t.vimode = Insert
#       t.render()
#       break
#     elif key in {Key.V}:
#       t.vimode = Visual
#       t.select()
#       t.render()
#       break
#     elif key == Key.ShiftA:
#       t.vimode = Insert
#       t.moveToEnd()
#       inc t.cursor
#       t.render()
#       break
#     elif key == Key.Delete:
#       t.delAtCursor() 
#     elif key == Key.Tab:
#       t.focus = false
#       t.render()
#       break
#     elif key in {Key.Left, Key.Backspace, Key.H}:
#       t.moveLeft()
#     elif key in {Key.Right, Key.L}: 
#       t.moveRight()
#     elif key in {Key.Up, Key.K}: 
#       t.rowCursor = max(t.rowCursor - 1, 0)
#       t.moveUp()
#     elif key in {Key.Down, Key.J}: 
#       t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)
#       t.moveDown()
#     elif key in {Key.Home, Key.Caret}:
#       t.moveToBegin()
#     elif key in {Key.End, Key.Dollar}:
#       t.moveToEnd()
#     elif key == Key.W:
#       t.moveToNextWord()
#       t.render()
#     elif key == Key.B:
#       t.moveToPrevWord()
#       t.render()
#     elif key == Key.X:
#       if t.cursor < t.value.len:
#         t.viHistory.addLast((cursor: t.cursor, content: $t.value[t.cursor]))
#         t.delAtCursor()
#     elif key == Key.P:
#       if t.cursor < t.value.len and t.viHistory.len > 0:
#         let last = t.viHistory.popLast()
#         t.putAtCursor(last.content)
#         t.viHistory.addLast(last)
#     elif key == Key.U:
#       # experiments, need more fix
#       if t.cursor < t.value.len and t.viHistory.len > 0:
#         let prevBuff = t.viHistory.popLast()
#         t.putAtCursor(prevBuff.content, prevBuff.cursor, updateCursor=true)
#     elif key == Key.D:
#       t.statusbarText = " D "
#       t.render()
#       while true:
#         var key2 = getKeyWithTimeout(1000)
#         case key2
#         of Key.D:
#           t.delLine()
#           break
#         of Key.Escape: break
#         else: discard
#         sleep(t.refreshWaitTime)
#       let (r, c) =t.cursorAtLine()
#       t.statusbarText = $r & ":" & $c
#       t.render()
#     elif key == Key.ShiftG:
#       t.cursor = t.value.len - 1
#       t.rowCursor = t.textRows.len - 1
#       t.render()
#     elif key == Key.G:
#       t.statusbarText = " G "
#       t.render()
#       while true:
#         var key2 = getKeyWithTimeout(1000)
#         case key2
#         of Key.G:
#           t.cursor = 0
#           t.rowCursor = 0
#           break
#         of Key.Escape: break
#         else: discard
#         sleep(t.refreshWaitTime)
#       let (r, c) =t.cursorAtLine()
#       t.statusbarText = $r & ":" & $c
#       t.render()
#     elif key == Key.Colon:
#       # custom command event
#       t.statusbarText = " :" 
#       t.render()
#       t.commandEvent()
#       let (r, c) =t.cursorAtLine()
#       t.statusbarText = $r & ":" & $c
#       t.render()
#     else:
#       t.vimode = Normal
#       t.statusbarText = ""
#       t.render()
#     sleep(t.refreshWaitTime)


proc visualMode(t: ref TextArea) =
  while true:
    var key = getKeyWithTimeout(t.refreshWaitTime)
    # some terminal return ctrl+v with I (105)
    # to prevent this happen in visual mode
    # I key is disabled
    # if key in {Key.I, Key.Insert}:
    #   t.vimode = Insert
    #   t.render()
    #   break
    if key in {Key.Escape}:
      t.vimode = Normal
      t.render()
      break
    elif key == Key.Tab:
      t.focus = false
      t.render()
      break
    elif key in {Key.X, Key.D, Key.Delete}:
      if t.cursor < t.value.len:
        let content = t.value[t.viSelection.startat..t.viSelection.endat]
        t.viHistory.addLast((cursor: t.cursor, content: content))
        t.delAtStartEndCursor(t.viSelection.startat, t.viSelection.endat)
        t.vimode = Normal
        break
    elif key == Key.Y:
      if t.cursor < t.value.len:
        let content = t.value[t.viSelection.startat..t.viSelection.endat]
        let cursor = if t.viSelection.direction == Left: t.cursor - content.len 
          else: t.cursor + content.len
        t.viHistory.addLast((cursor: cursor, content: content))
        t.vimode = Normal
        break
    elif key in {Key.Left, Key.Backspace, Key.H}:
      t.selectMoveLeft(key)
    elif key in {Key.Right, Key.L}: 
      t.selectMoveRight(key)
    elif key in {Key.Up, Key.K}: 
      t.selectMoveLeft(key)
    elif key in {Key.Down, Key.J}: 
      t.selectMoveRight(key)
    elif key in {Key.Home, Key.Caret}:
      t.selectMoveLeft(key)
    elif key in {Key.End, Key.Dollar}:
      t.selectMoveRight(key)
    elif key == Key.W:
      t.selectMoveRight(key)
    elif key == Key.B:
      t.selectMoveLeft(key)
    else:
      t.vimode = Visual
      t.render()
    sleep(t.refreshWaitTime)



proc editMode(t: ref TextArea) =
  const FnKeys = {Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.F6,
                  Key.F7, Key.F8, Key.F9, Key.F10, Key.F11, Key.F12}
  const CtrlKeys = {Key.CtrlA, Key.CtrlB, Key.CtrlC, Key.CtrlD, Key.CtrlF, 
                    Key.CtrlG, Key.CtrlH, Key.CtrlJ, Key.CtrlK, Key.CtrlL, 
                    Key.CtrlN, Key.CtrlO, Key.CtrlP, Key.CtrlQ, Key.CtrlR, 
                    Key.CtrlS, Key.CtrlT, Key.CtrlU, Key.CtrlW, Key.CtrlX, 
                    Key.CtrlY, Key.CtrlZ}
  const NumericKeys = @[Key.Zero, Key.One, Key.Two, Key.Three, Key.Four, 
                        Key.Five, Key.Six, Key.Seven, Key.Eight, Key.Nine]
  while t.focus:
    var key = getKeyWithTimeout(t.refreshWaitTime)
    if t.enableViMode and t.vimode == Normal and key in {Key.I, Key.ShiftI, Key.Insert}:
      t.vimode = Insert
      t.render()
    elif t.enableViMode and t.vimode == Normal and key in {Key.V, Key.ShiftV}:
      t.vimode = Visual
      continue
    elif t.enableViMode and t.vimode == Normal: continue
    else:
      case key
      of Key.None, FnKeys, CtrlKeys: continue
      of Key.Escape:
        if t.enableViMode: 
          t.normalMode()
          break
        else: t.focus = false
      of Key.Tab: t.focus = false
      of Key.Backspace:
        if t.cursor > 0:
          t.value.delete(t.cursor - 1..t.cursor - 1)
          t.cursorMove(-1)
      of Key.Delete:
        if t.value.len > 0:
          t.value.delete(t.cursor .. t.cursor)
          if t.cursor == t.value.len: t.value &= " "
      of Key.CtrlE:
        t.value = " "
        t.cursor = 0
        t.clear()
      of Key.ShiftA..Key.ShiftZ:
        let tmpKey = $key
        let alphabet = toSeq(tmpKey.items()).pop()
        t.value.insert($alphabet.toUpperAscii(), t.cursor)
        t.cursorMove(1)
      of Key.Zero..Key.Nine:
        let keyPos = NumericKeys.find(key)
        if keyPos > -1:
          t.value.insert($keyPos, t.cursor)
        t.cursorMove(1)
      of Key.Comma:
        t.value.insert(",", t.cursor)
        t.cursorMove(1)
      of Key.Colon:
        t.value.insert(":", t.cursor)
        t.cursorMove(1)
      of Key.Semicolon:
        t.value.insert(";", t.cursor)
        t.cursorMove(1)
      of Key.Underscore:
        t.value.insert("_", t.cursor)
        t.cursorMove(1)
      of Key.Dot:
        t.value.insert(".", t.cursor)
        t.cursorMove(1)
      of Key.Ampersand:
        t.value.insert("&", t.cursor)
        t.cursorMove(1)
      of Key.DoubleQuote:
        t.value.insert("\"", t.cursor)
        t.cursorMove(1)
      of Key.SingleQuote:
        t.value.insert("'", t.cursor)
        t.cursorMove(1)
      of Key.QuestionMark:
        t.value.insert("?", t.cursor)
        t.cursorMove(1)
      of Key.Space:
        t.value.insert(" ", t.cursor)
        t.cursorMove(1)
      of Key.Pipe:
        t.value.insert("|", t.cursor)
        t.cursorMove(1)
      of Key.Slash:
        t.value.insert("/", t.cursor)
        t.cursorMove(1)
      of Key.Equals:
        t.value.insert("=", t.cursor)
        t.cursorMove(1)
      of Key.Plus:
        t.value.insert("+", t.cursor)
        t.cursorMove(1)
      of Key.Minus:
        t.value.insert("-", t.cursor)
        t.cursorMove(1)
      of Key.Asterisk:
        t.value.insert("*", t.cursor)
        t.cursorMove(1)
      of Key.BackSlash:
        t.value.insert("\\", t.cursor)
        t.cursorMove(1)
      of Key.GreaterThan:
        t.value.insert(">", t.cursor)
        t.cursorMove(1)
      of Key.LessThan:
        t.value.insert("<", t.cursor)
        t.cursorMove(1)
      of Key.LeftBracket:
        t.value.insert("[", t.cursor)
        t.cursorMove(1)
      of Key.RightBracket:
        t.value.insert("]", t.cursor)
        t.cursorMove(1)
      of Key.LeftBrace:
        t.value.insert("{", t.cursor)
        t.cursorMove(1)
      of Key.RightBrace:
        t.value.insert("}", t.cursor)
        t.cursorMove(1)
      of Key.LeftParen:
        t.value.insert("(", t.cursor)
        t.cursorMove(1)
      of Key.RightParen:
        t.value.insert(")", t.cursor)
        t.cursorMove(1)
      of Key.Percent:
        t.value.insert("%", t.cursor)
        t.cursorMove(1)
      of Key.Hash:
        t.value.insert("#", t.cursor)
        t.cursorMove(1)
      of Key.Dollar:
        t.value.insert("$", t.cursor)
        t.cursorMove(1)
      of Key.ExclamationMark:
        t.value.insert("!", t.cursor)
        t.cursorMove(1)
      of Key.At:
        t.value.insert("@", t.cursor)
        t.cursorMove(1)
      of Key.Caret:
        t.value.insert("^", t.cursor)
        t.cursorMove(1)
      of Key.GraveAccent:
        t.value.insert("~", t.cursor)
        t.cursorMove(1)
      of Key.Tilde:
        t.value.insert("`", t.cursor)
        t.cursorMove(1)
      of Key.Home:
        t.moveToBegin()
      of Key.End:
        t.moveToEnd()
      of Key.PageUp, Key.PageDown, Key.Insert:
        discard
      of Key.Left:
        t.moveLeft()
      of Key.Right: 
        t.moveRight()
      of Key.Up: 
        t.rowCursor = max(t.rowCursor - 1, 0)
        t.moveUp()
      of Key.Down: 
        t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)
        t.moveDown()
      of Key.CtrlV:
        let copiedText = $cb.clipboard_text()
        t.value.insert(copiedText, t.cursor)
        t.cursor = t.cursor + copiedText.len
        t.rowReCal()
      of Key.Enter: 
        t.enter()
        t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)
      else:
        var ch = $key
        t.value.insert(ch.toLower(), t.cursor)
        t.cursorMove(1)
      t.render()
      sleep(t.refreshWaitTime)


method onControl*(t: ref TextArea) =
  t.focus = true
  while t.focus:
    if t.enableViMode and t.vimode == Insert:
      t.editMode()
    elif t.enableViMode and t.vimode == Normal:
      t.normalMode()
    elif t.enableViMode and t.vimode == Visual:
      t.visualMode()
      t.select()
    else:
      t.editMode()
    t.render()
    sleep(t.refreshWaitTime)
  

method wg*(t: ref TextArea): ref BaseWidget = t


proc value*(t: ref TextArea): string = 
  return t.value[0 ..< t.value.len - 1]


proc val(t: ref TextArea, val: string) =
  t.clear()
  t.value = val & " "
  t.rowReCal()
  t.cursor = t.value.len - 1
  t.rowCursor = t.textRows.len - 1
  t.rowCursor = min(t.textRows.len - 1, t.rows - 1)
  t.render()


proc `value=`*(t: ref TextArea, val: string) =
  t.val(val)

proc value*(t: ref TextArea, val: string) =
  t.val(val) 

