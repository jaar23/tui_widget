import illwill, base_wg, os, sequtils, strutils, deques, times,
       input_box_wg, display_wg, listview_wg
import std/enumerate
import tables, threading/channels, std/math

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

  TextAreaObj* = object of BaseWidget
    textRows: seq[string] = newSeq[string]()
    rowStartPos*: seq[int] = newSeq[int]()
    value: string = ""
    rows: int = 0
    cols: int = 0
    cursorBg: BackgroundColor = bgBlue
    cursorFg: ForegroundColor = fgWhite
    cursorStyle: CursorStyle = Block
    vimode: ViMode = Normal
    enableViMode: bool = false
    scrollY: int = 0
    viHistory: Deque[ViHistory]
    history*: seq[string]
    historyCursor*: int
    maxHistory*: int
    viStyle*: ViStyle
    viSelection: ViSelection
    events*: Table[string, EventFn[TextArea]]
    editKeyEvents*: Table[Key, EventFn[TextArea]]
    normalKeyEvents*: Table[Key, EventFn[TextArea]]
    visualKeyEvents*: Table[Key, EventFn[TextArea]]
    enableAutocomplete*: bool = false
    autocompleteTrigger*: int = 3
    autocompleteList*: seq[Completion] =  newSeq[Completion]()
    autocompleteWindowSize*: int = 5
    autocompleteBgColor*: BackgroundColor = bgCyan
    autocompleteFgColor*: ForegroundColor = fgWhite

  WordToken* = object
    startat*: int
    endat*: int
    token*: string

  TextArea* = ref TextAreaObj

  UndoAction = object
    cursor: int
    content: string
    actionType: string

const cursorStyleArr: array[CursorStyle, string] = ["█", "|", "_"]

proc on*(t: TextArea, event: string, fn: EventFn[TextArea]): void {.raises: [EventKeyError]}

proc on*(t: TextArea, key: Key, fn: EventFn[TextArea], vimode: ViMode = Insert): void {.raises: [EventKeyError].}

proc help(t: TextArea, args: varargs[string]): void

proc newViStyle(nbg: BackgroundColor = bgBlue, tg: BackgroundColor = bgCyan,
                vbg: BackgroundColor = bgYellow,
                nfg: ForegroundColor = fgWhite, ifg: ForegroundColor = fgWhite,
                vfg: ForegroundColor = fgWhite,
                calBg: BackgroundColor = bgWhite,
                calFg: ForegroundColor = fgBlack): ViStyle =
  result = ViStyle(
    normalBg: nbg,
    insertBg: tg,
    visualBg: vbg,
    normalFg: nfg,
    insertFg: ifg,
    visualFg: vfg,
    cursorAtLineBg: calBg,
    cursorAtLineFg: calFg
  )


proc newTextArea*(px, py, w, h: int, title = ""; val = " ";
                  border = true; statusbar = false; enableHelp=false;
                  bgColor = bgNone; fgColor = fgWhite;
                  cursorBg = bgBlue; cursorFg = fgWhite; cursorStyle = Block,
                  enableViMode = false; vimode: ViMode = Normal;
                  viStyle: ViStyle = newViStyle();
                  enableAutocomplete = false; autocompleteTrigger = 3;
                  tb = newTerminalBuffer(w+2, h+py)): TextArea =
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
  var textArea = TextArea(
    width: w,
    height: h,
    posX: px,
    posY: py,
    value: if val == " ": " " else: val & " ",
    cols: w - px - padding,
    rows: h - py - (padding * 2),
    size: h - statusbarSize - py,
    style: style,
    title: title,
    tb: tb,
    cursorBg: cursorBg,
    cursorFg: cursorFg,
    cursorStyle: cursorStyle,
    statusbar: statusbar,
    statusbarSize: statusbarSize,
    enableHelp: enableHelp,
    vimode: vimode,
    enableViMode: enableViMode,
    viHistory: initDeque[ViHistory](),
    viStyle: viStyle,
    scrollY: 0,
    historyCursor: 0,
    maxHistory: 100,
    viSelection: (startat: 0, endat: 0, direction: Right),
    events: initTable[string, EventFn[TextArea]](),
    editKeyEvents: initTable[Key, EventFn[TextArea]](),
    normalKeyEvents: initTable[Key, EventFn[TextArea]](),
    visualKeyEvents: initTable[Key, EventFn[TextArea]](),
    enableAutocomplete: enableAutocomplete,
    autocompleteTrigger: autocompleteTrigger,
    blocking: true
  )
  # to ensure key responsive, default < 50ms
  if textArea.rpms > 50: textArea.rpms = 50
  textArea.channel = newChan[WidgetBgEvent]()
  if enableHelp:
    textArea.normalKeyEvents[Key.QuestionMark] = help
    textArea.visualKeyEvents[Key.QuestionMark] = help
  textArea.keepOriginalSize()
  # register copy and paste events
  textArea.on(Key.CtrlC, proc(t: TextArea, args: varargs[string]) =
    if t.value.len > 0:
      base_wg.setClipboardText(t.value)
  )

  textArea.on(Key.CtrlV, proc(t: TextArea, args: varargs[string]) =
    let clipText = base_wg.getClipboardText()
    if clipText.len > 0:
      t.value.insert(clipText, t.cursor)
      t.cursor = t.cursor + clipText.len
  )
  return textArea


proc newTextArea*(px, py: int, w, h: WidgetSize, title = ""; val = " ";
                  border = true; statusbar = false; enableHelp=false;
                  bgColor = bgNone; fgColor = fgWhite;
                  cursorBg = bgBlue; cursorFg = fgWhite; cursorStyle = Block,
                  enableViMode = false; vimode: ViMode = Normal;
                  viStyle: ViStyle = newViStyle();
                  enableAutocomplete = false; autocompleteTrigger = 3;
                  tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): TextArea =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newTextArea(px, py, width, height, title, val, border, statusbar, enableHelp,
                     bgColor, fgColor, cursorBg, cursorFg, cursorStyle, enableViMode,
                     viMode, viStyle, enableAutocomplete, autocompleteTrigger, tb)


proc newTextArea*(id: string): TextArea =
  var textarea = TextArea(
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
    value: " ",
    cursorBg: bgBlue,
    cursorFg: fgWhite,
    cursorStyle: Block,
    scrollY: 0,
    historyCursor: 0,
    maxHistory: 100,
    viHistory: initDeque[ViHistory](),
    viStyle: newViStyle(),
    viSelection: (startat: 0, endat: 0, direction: Right),
    events: initTable[string, EventFn[TextArea]](),
    editKeyEvents: initTable[Key, EventFn[TextArea]](),
    normalKeyEvents: initTable[Key, EventFn[TextArea]](),
    visualKeyEvents: initTable[Key, EventFn[TextArea]](),
    blocking: true
  )
  # to ensure key responsive, default < 50ms
  if textarea.rpms > 50: textarea.rpms = 50
  textarea.channel = newChan[WidgetBgEvent]()
  textarea.normalKeyEvents[Key.QuestionMark] = help
  textarea.visualKeyEvents[Key.QuestionMark] = help
  # register copy and paste events
  textarea.on(Key.CtrlC, proc(t: TextArea, args: varargs[string]) =
    if t.value.len > 0:
      base_wg.setClipboardText(t.value)
  )

  textarea.on(Key.CtrlV, proc(t: TextArea, args: varargs[string]) =
    let clipText = base_wg.getClipboardText()
    if clipText.len > 0:
      t.value.insert(clipText, t.cursor)
      t.cursor = t.cursor + clipText.len
  )
  return textarea


# ---------------------------------------------------------------------------
# Core text model: newline-based storage
# value stores actual '\n' for line breaks; always ends with a space sentinel.
# rowStartPos[i] = byte offset in value where visual row i begins.
# ---------------------------------------------------------------------------

func rowReCal(t: TextArea) =
  ## Rebuild textRows and rowStartPos from value.
  ## Logical lines are split by '\n'; long lines are soft-wrapped at cols width.
  t.textRows = newSeq[string]()
  t.rowStartPos = newSeq[int]()
  if t.value.len == 0 or t.cols <= 0:
    t.textRows.add("")
    t.rowStartPos.add(0)
    return
  var vi = 0
  var lineStart = 0
  while vi <= t.value.len:
    if vi == t.value.len or t.value[vi] == '\n':
      let line = t.value[lineStart ..< vi]
      if line.len == 0:
        t.textRows.add("")
        t.rowStartPos.add(lineStart)
      else:
        var pos = 0
        while pos < line.len:
          let chunkEnd = min(pos + t.cols, line.len)
          t.textRows.add(line[pos ..< chunkEnd])
          t.rowStartPos.add(lineStart + pos)
          pos += t.cols
      lineStart = vi + 1
    inc vi
  if t.textRows.len == 0:
    t.textRows.add("")
    t.rowStartPos.add(0)


proc computeVisualRow(t: TextArea): int =
  ## Return visual row index for current cursor position using rowStartPos.
  if t.rowStartPos.len == 0: return 0
  for i in countdown(t.rowStartPos.len - 1, 0):
    if t.rowStartPos[i] <= t.cursor:
      return i
  return 0


proc recordHistory(t: TextArea) =
  ## Save current state to history
  if t.history.len == 0 or t.history[t.historyCursor] != t.value:
    # Remove any redo states if we're not at the end of history
    if t.historyCursor < t.history.len - 1:
      t.history = t.history[0..t.historyCursor]

    # Add current state
    t.history.add(t.value)
    t.historyCursor = t.history.len - 1

    # Limit history size
    if t.history.len > t.maxHistory:
      t.history = t.history[1..^1]
      t.historyCursor -= 1

proc undo*(t: TextArea) =
  ## Revert to previous state
  if t.historyCursor > 0:
    t.historyCursor -= 1
    t.value = t.history[t.historyCursor]
    t.rowReCal()
    t.cursor = min(t.cursor, t.value.len - 1)
    t.rowCursor = t.computeVisualRow()

proc redo*(t: TextArea) =
  ## Redo last undone action
  if t.historyCursor < t.history.len - 1:
    t.historyCursor += 1
    t.value = t.history[t.historyCursor]
    t.rowReCal()
    t.cursor = min(t.cursor, t.value.len - 1)
    t.rowCursor = t.computeVisualRow()


func enter(t: TextArea) =
  t.recordHistory()
  t.value.insert("\n", t.cursor)
  t.cursor += 1
  t.rowReCal()
  t.rowCursor = t.computeVisualRow()
  let visibleRows = t.size - t.statusbarSize
  if t.rowCursor >= t.scrollY + visibleRows:
    t.scrollY = t.rowCursor - visibleRows + 1


func moveToBegin(t: TextArea) =
  if t.rowCursor < t.rowStartPos.len:
    t.cursor = t.rowStartPos[t.rowCursor]


func moveToEnd(t: TextArea) =
  if t.rowCursor < t.textRows.len:
    let rowLen = t.textRows[t.rowCursor].len
    t.cursor = t.rowStartPos[t.rowCursor] + rowLen
    t.cursor = min(t.cursor, t.value.len - 1)


func moveToNextWord(t: TextArea) =
  let charsRange = {'.', ',', ';', '"', '\'', '[', ']',
                    '\\', '/', '-', '+', '_', '=', '?',
                    '(', ')', '*', '&', '^', '%', '$',
                    '#', '@', '!', '`', '~', '|'}
  var space = false
  for p in t.cursor ..< t.value.len:
    if t.value[p].isAlphaNumeric() and not space:
      continue
    elif t.value[p].isAlphaNumeric() and space:
      t.cursor = p
      space = false
      break
    if t.value[p] in {' ', '\n'}:
      space = true
      continue
    if t.value[p] in charsRange and p != t.cursor:
      t.cursor = p
      space = false
      break
    else: continue

  t.rowReCal()
  t.rowCursor = t.computeVisualRow()
  let visibleRows = t.size - t.statusbarSize
  if t.rowCursor >= t.scrollY + visibleRows:
    t.scrollY = t.rowCursor - visibleRows + 1
  elif t.rowCursor < t.scrollY:
    t.scrollY = t.rowCursor


func moveToPrevWord(t: TextArea) =
  let charsRange = {'.', ',', ';', '"', '\'', '[', ']',
                    '\\', '/', '-', '+', '_', '=', '?',
                    '(', ')', '*', '&', '^', '%', '$',
                    '#', '@', '!', '`', '~', '|'}
  var space = false
  for p in countdown(t.cursor, 0):
    if t.value[p].isAlphaNumeric() and not space:
      continue
    elif t.value[p].isAlphaNumeric() and space:
      t.cursor = p
      space = false
      break
    if t.value[p] in {' ', '\n'}:
      space = true
      continue
    if t.value[p] in charsRange and p != t.cursor:
      t.cursor = p
      space = false
      break
    else: continue

  t.rowReCal()
  t.rowCursor = t.computeVisualRow()
  if t.rowCursor < t.scrollY:
    t.scrollY = t.rowCursor


func moveToEndOfWord(t: TextArea) =
  let charsRange = {'.', ',', ';', '"', '\'', '[', ']',
                    '\\', '/', '-', '+', '_', '=', '?',
                    '(', ')', '*', '&', '^', '%', '$',
                    '#', '@', '!', '`', '~', '|', ' ', '\n'}

  for p in t.cursor ..< t.value.len:
    if p == t.value.len - 1 or t.value[p + 1] in charsRange:
      t.cursor = p
      break

  t.rowReCal()
  t.rowCursor = t.computeVisualRow()
  let visibleRows = t.size - t.statusbarSize
  if t.rowCursor >= t.scrollY + visibleRows:
    t.scrollY = t.rowCursor - visibleRows + 1


func moveUp(t: TextArea) =
  if t.rowCursor == 0: return
  let colOffset = t.cursor - t.rowStartPos[t.rowCursor]
  t.rowCursor = max(0, t.rowCursor - 1)
  let prevRowLen = t.textRows[t.rowCursor].len
  t.cursor = t.rowStartPos[t.rowCursor] + min(colOffset, prevRowLen)
  if t.rowCursor < t.scrollY:
    t.scrollY = t.rowCursor


func moveDown(t: TextArea) =
  if t.rowCursor >= t.textRows.len - 1: return
  let colOffset = t.cursor - t.rowStartPos[t.rowCursor]
  t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)
  let nextRowLen = t.textRows[t.rowCursor].len
  t.cursor = t.rowStartPos[t.rowCursor] + min(colOffset, nextRowLen)
  let visibleRows = t.size - t.statusbarSize
  if t.rowCursor >= t.scrollY + visibleRows:
    t.scrollY = t.rowCursor - visibleRows + 1


func moveRight(t: TextArea) =
  if t.cursor < t.value.len - 1:
    t.cursor += 1
  t.rowCursor = t.computeVisualRow()
  let visibleRows = t.size - t.statusbarSize
  if t.rowCursor >= t.scrollY + visibleRows:
    t.scrollY = t.rowCursor - visibleRows + 1


func moveLeft(t: TextArea) =
  if t.cursor > 0:
    t.cursor -= 1
  t.rowCursor = t.computeVisualRow()
  if t.rowCursor < t.scrollY:
    t.scrollY = t.rowCursor


func cursorMove(t: TextArea, moved: int) =
  t.cursor = t.cursor + moved
  if t.cursor > t.value.len - 1: t.cursor = t.value.len - 1
  if t.cursor < 0: t.cursor = 0
  t.rowReCal()
  t.rowCursor = t.computeVisualRow()
  let visibleRows = t.size - t.statusbarSize
  if t.rowCursor >= t.scrollY + visibleRows:
    t.scrollY = t.rowCursor - visibleRows + 1
  elif t.rowCursor < t.scrollY:
    t.scrollY = t.rowCursor


func backspace(t: TextArea) =
  t.recordHistory()
  if t.cursor <= 0: return
  t.value.delete(t.cursor - 1 .. t.cursor - 1)
  t.cursor -= 1
  if t.value.len == 0: t.value = " "
  t.rowReCal()
  t.rowCursor = t.computeVisualRow()
  if t.rowCursor < t.scrollY:
    t.scrollY = t.rowCursor


proc addToHistory(t: TextArea, action: string, cursor: int, content: string) =
  t.viHistory.addLast((cursor: cursor, content: content))
  while t.viHistory.len > 100:
    discard t.viHistory.popFirst()


func insert(t: TextArea, value: string, pos: int) =
  t.recordHistory()
  t.addToHistory("insert", pos, value)
  t.value.insert(value, pos)


func select(t: TextArea) =
  t.viSelection.startat = t.cursor
  t.viSelection.endat = t.cursor

func selectMoveLeft(t: TextArea, key: Key) =
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


func selectMoveRight(t: TextArea, key: Key) =
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


func delAtCursor(t: TextArea) =
  if t.value.len > 1 and t.cursor < t.value.len - 1:
    t.value.delete(t.cursor .. t.cursor)
  if t.value.len == 0: t.value = " "


func delAtStartEndCursor(t: TextArea, startat, endat: int) =
  try:
    if t.value.len > 1:
      let safeEnd = min(endat, t.value.len - 2)
      if startat <= safeEnd:
        t.value.delete(startat .. safeEnd)
    if t.value.len == 0: t.value = " "
    t.cursor = min(startat, t.value.len - 1)
  except:
    t.statusbarText = "failed to delete selected string"


func delLine(t: TextArea) =
  try:
    # find start of current logical line
    var lineStart = t.cursor
    while lineStart > 0 and t.value[lineStart - 1] != '\n':
      lineStart -= 1
    # find end of logical line (including the '\n' if present)
    var lineEnd = t.cursor
    while lineEnd < t.value.len - 1 and t.value[lineEnd] != '\n':
      lineEnd += 1
    if lineEnd < t.value.len - 1:
      inc lineEnd  # include the '\n'
    t.viHistory.addLast((cursor: lineStart, content: t.value[lineStart ..< lineEnd]))
    if lineEnd > lineStart:
      t.value.delete(lineStart ..< lineEnd)
    if t.value.len == 0: t.value = " "
    t.cursor = min(lineStart, t.value.len - 1)
    t.rowReCal()
    t.rowCursor = t.computeVisualRow()
  except:
    t.statusbarText = "failed to delete line"


proc putAtCursor(t: TextArea, content: string) =
  t.value.insert(content, t.cursor)
  t.cursor = t.cursor + content.len
  t.rowReCal()


proc putAtCursor(t: TextArea, content: string, cursor: int,
                 updateCursor = true) =
  try:
    t.value.insert(content, cursor)
    if updateCursor: t.cursor = cursor
    t.rowReCal()
  except:
    t.statusbarText = "failed to put text at cursor"
  return


func cursorAtLine(t: TextArea): (int, int) =
  if t.rowCursor < t.rowStartPos.len:
    let col = t.cursor - t.rowStartPos[t.rowCursor]
    return (t.rowCursor, col)
  return (t.rowCursor, 0)


proc on*(t: TextArea, event: string, fn: EventFn[TextArea]) =
  t.events[event] = fn


proc onNormalMode(t: TextArea, key: Key, fn: EventFn[TextArea]) =
  const forbiddenKeys = {Key.I, Key.Insert, Key.V, Key.ShiftA, Key.Delete,
                        Key.Left, Key.Right, Key.Backspace, Key.H,
                        Key.L, Key.Up, Key.K, Key.Down, Key.J, Key.Home,
                        Key.Caret, Key.End, Key.Dollar, Key.W, Key.B,
                        Key.X, Key.P, Key.U, Key.D, Key.ShiftG, Key.G,
                        Key.Colon, Key.Escape, Key.Tab}
  if key in forbiddenKeys:
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  else:
    t.normalKeyEvents[key] = fn


proc onEditMode(t: TextArea, key: Key, fn: EventFn[TextArea]) =
  const allowFnKeys = {Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.F6,
                       Key.F7, Key.F8, Key.F9, Key.F10, Key.F11, Key.F12}

  const allowCtrlKeys = {Key.CtrlA, Key.CtrlB, Key.CtrlC, Key.CtrlD, Key.CtrlF,
                         Key.CtrlG, Key.CtrlH, Key.CtrlJ, Key.CtrlK, Key.CtrlL,
                         Key.CtrlN, Key.CtrlO, Key.CtrlP, Key.CtrlQ, Key.CtrlR,
                         Key.CtrlS, Key.CtrlT, Key.CtrlU, Key.CtrlW, Key.CtrlX,
                         Key.CtrlY, Key.CtrlZ, Key.CtrlV}

  if key in allowFnKeys or key in allowCtrlKeys:
    t.editKeyEvents[key] = fn
  else:
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")


proc onVisualMode(t: TextArea, key: Key, fn: EventFn[TextArea]) =
  const forbiddenKeys = {Key.Escape, Key.Tab, Key.V, Key.Y, Key.P,
                        Key.Left, Key.Right, Key.Backspace, Key.H,
                        Key.L, Key.Up, Key.K, Key.Down, Key.J, Key.Home,
                        Key.Caret, Key.End, Key.Dollar, Key.W, Key.B,
                        Key.X, Key.P, Key.U, Key.D}
  if key in forbiddenKeys:
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  else:
    t.visualKeyEvents[key] = fn


proc on*(t: TextArea, key: Key, fn: EventFn[TextArea],
    vimode: ViMode = Insert) {.raises: [EventKeyError].} =
  if t.enableViMode:
    if vimode == Normal:
      t.onNormalMode(key, fn)
    elif vimode == Insert:
      t.onEditMode(key, fn)
    elif vimode == Visual:
      t.onVisualMode(key, fn)
  else:
    t.onEditMode(key, fn)


proc call*(t: TextArea, event: string, args: varargs[string]) =
  if t.events.hasKey(event):
    let fn = t.events[event]
    fn(t, args)


proc call(t: TextArea, key: Key, args: varargs[string]) =
  if t.enableViMode:
    if t.vimode == Normal:
      if t.normalKeyEvents.hasKey(key):
        let fn = t.normalKeyEvents[key]
        fn(t, args)
    elif t.vimode == Insert:
      if t.editKeyEvents.hasKey(key):
        let fn = t.editKeyEvents[key]
        fn(t, args)
    elif t.vimode == Visual:
      if t.visualKeyEvents.hasKey(key):
        let fn = t.visualKeyEvents[key]
        fn(t, args)
  else:
    if t.editKeyEvents.hasKey(key):
      let fn = t.editKeyEvents[key]
      fn(t, args)


proc help(t: TextArea, args: varargs[string]) =
  let wsize = ((t.width - t.posX).toFloat * 0.3).toInt()
  let hsize = ((t.height - t.posY).toFloat * 0.3).toInt()
  var display = newDisplay(t.x2 - wsize, t.y2 - hsize,
                          t.x2, t.y2, title="help",
                          bgColor=bgWhite, fgColor=fgBlack,
                          tb=t.tb, statusbar=false,
                          enableHelp=false)
  var helpText: string = "\n"
  if t.enableViMode and t.vimode == Normal:
    helpText = " [i] [Insert]    switch to insert mode\n" &
               " [v]             switch to visual mode\n" &
               " [A]             append at end of line\n" &
               " [Delete]        delete at cursor \n" &
               " [Tab]           go to next widget\n" &
               " [Left] [<-] [h] move backward\n" &
               " [Right] [l]     move forward\n" &
               " [Up] [k]        move upward\n" &
               " [Down] [j]      move downward\n" &
               " [Home] [^]      goto beginning of line\n" &
               " [End] [$]       goto end of line\n" &
               " [w]             goto next word\n" &
               " [b]             goto previous word\n" &
               " [x]             cut text at cursor\n" &
               " [p]             paste last history at cursor\n" &
               " [u]             undo last change\n" &
               " [dd]            delete whole line\n" &
               " [Esc]           back to normal mode\n" &
               " [?]             open help menu\n"
  elif t.enableViMode and t.vimode == Visual:
    helpText = " [Delete]        delete at cursor \n" &
               " [Tab]           go to next widget\n" &
               " [Left] [<-] [h] move backward\n" &
               " [Right] [l]     move forward\n" &
               " [Up] [k]        move upward\n" &
               " [Down] [j]      move downward\n" &
               " [Home] [^]      goto beginning of line\n" &
               " [End] [$]       goto end of line\n" &
               " [w]             goto next word\n" &
               " [b]             goto previous word\n" &
               " [x]             cut text at cursor\n" &
               " [y]             copy/yank selected text\n" &
               " [d]             delete selected text\n" &
               " [Esc]           back to normal mode\n" &
               " [?]             open help menu\n"

  display.text = helpText
  display.illwillInit = true
  display.onControl()
  display.clear()


method resize*(t: TextArea) =
  let padding = if t.border: 1 else: 0
  let statusbarSize = if t.statusbar: 1 else: 0
  t.cols = t.width - t.posX - padding
  t.rows = t.height - t.posY - (padding * 2)
  t.size = t.height - statusbarSize - t.posY
  t.rowReCal()


method render*(t: TextArea) =
  if not t.illwillInit: return

  t.clear()
  t.renderBorder()
  t.renderTitle()
  t.rowReCal()

  var index = 1
  if t.textRows.len > 0:
    let rowStart = max(0, min(t.scrollY, t.textRows.len - 1))
    let visibleRows = t.size - t.statusbarSize
    let rowEnd = min(t.textRows.len - 1, rowStart + visibleRows - 1)

    for rowNum in rowStart .. min(rowEnd, t.textRows.len - 1):
      let row = t.textRows[rowNum]
      let rowValStart = t.rowStartPos[rowNum]

      for i, c in enumerate(row.items()):
        let vi = rowValStart + i
        if t.enableViMode and t.vimode == Visual:
          if vi >= t.viSelection.startat and vi <= t.viSelection.endat:
            t.tb.write(t.x1 + i, t.posY + index, bgWhite, fgBlack, $c, resetStyle)
          else:
            t.tb.write(t.x1 + i, t.posY + index, $c, resetStyle)
        else:
          if vi == t.cursor:
            let ch = if c == ' ': cursorStyleArr[t.cursorStyle] else: $c
            if t.cursorStyle == Ibeam:
              t.tb.write(t.x1 + i, t.posY + index, styleBlink,
                         t.cursorBg, t.cursorFg, ch, resetStyle)
            else:
              t.tb.write(t.x1 + i, t.posY + index, styleBlink,
                         styleUnderscore, t.cursorBg, t.cursorFg, ch, resetStyle)
          else:
            t.tb.write(t.x1 + i, t.posY + index, $c, t.bg, t.fg)

      # cursor at end-of-row (after last visible char, e.g. before '\n')
      if not (t.enableViMode and t.vimode == Visual):
        let endPos = rowValStart + row.len
        if endPos == t.cursor and endPos <= t.value.len - 1:
          t.tb.write(t.x1 + row.len, t.posY + index, styleBlink,
                     t.cursorBg, t.cursorFg, cursorStyleArr[t.cursorStyle], resetStyle)

      inc index

  if t.statusbar:
    if not t.enableViMode:
      if t.events.hasKey("statusbar"):
        t.call("statusbar")
      else:
        var statusbarText = " " & $t.cursor & ":" & $(t.value.len - 1)
        let borderSize = if t.border: 2 else: 1
        statusbarText = statusbarText & " ".repeat(t.width - statusbarText.len() - borderSize)
        t.renderCleanRect(t.x1, t.height - 1, statusbarText.len, t.height - 1)
        t.tb.write(t.x1, t.height - 1, fgCyan, statusbarText, resetStyle)

    else:
      var bgColor = t.viStyle.normalBg
      var fgColor = t.viStyle.normalFg

      if t.vimode == Insert:
        bgColor = t.viStyle.insertBg
        fgColor = t.viStyle.insertFg
      elif t.vimode == Visual:
        bgColor = t.viStyle.visualBg
        fgColor = t.viStyle.visualFg

      t.tb.write(t.x1, t.height - 1, bgColor, fgColor, center(toUpper($t.vimode),
          len($t.vimode) + 4), resetStyle)

      let (r, c) = if t.vimode == Visual: (t.viSelection.startat,
          t.viSelection.endat) else: t.cursorAtLine()

      var statusbarText = if t.statusbarText != "": t.statusbarText
        else: " " & $r & ":" & $c
      let borderSize = if t.border: 2 else: 1
      statusbarText = statusbarText & " ".repeat(max(0, t.width - statusbarText.len() - borderSize - len($t.vimode) - 4))
      t.tb.write(t.x1 + len($t.vimode) + 4, t.height - 1, t.viStyle.cursorAtLineBg,
                t.viStyle.cursorAtLineFg, statusbarText, resetStyle)

      if t.enableHelp:
        let q = "[?]"
        t.tb.write(t.x2 - q.len, t.height - 1, bgWhite, fgBlack, q, resetStyle)

  if not t.suppressDisplay: t.tb.display()


proc resetCursor*(t: TextArea) =
  t.rowCursor = 0
  t.cursor = 0
  t.statusbarText = ""


proc commandEvent*(t: TextArea) =
  var input = newInputBox(t.x1 + 9, t.y2,
                          t.x1 + 9 + 12, t.y2,
                         tb = t.tb, border = true)
  let enterEv = proc(ib: InputBox, x: varargs[string]) =
    if t.events.hasKey(ib.value()):
      t.call(ib.value())
    input.focus = false

  input.illwillInit = true
  input.on("enter", enterEv)
  input.onControl()


proc splitByToken*(s: string): seq[WordToken] =
  let tokens = s.strip().split(" ")
  var pos = 0
  result = newSeq[WordToken]()
  for token in tokens:
    result.add(
      WordToken(
        startat: pos,
        endat: pos + token.len,
        token: token
      )
    )
    pos += max(1, token.len + 1)


proc autocomplete(t: TextArea) =
  # auto-complete may trigger a second render
  # pass in current word token by cursor !
  let tokens = splitByToken(t.value)
  var currToken: WordToken

  for token in tokens:
    if t.cursor >= token.startat and token.endat >= t.cursor:
      currToken = token
      break

  if currToken.token.len >= t.autocompleteTrigger:
    t.call("autocomplete", currToken.token)
  else: t.autocompleteList = newSeq[Completion]()

  if t.autocompleteList.len == 0:
    return

  let x1 = if t.rowCursor == 0: t.cursor + 1 else: (t.cursor - t.rowStartPos[t.rowCursor]) + 1
  let x2 = max((t.x2 / 2).toInt, t.x2)
  var completionList = newListView(t.x1 + x1, t.y1 + t.rowCursor,
                                x2, t.y1 + t.rowCursor + t.autocompleteWindowSize,
                                selectionStyle=Highlight, bgColor=bgNone,
                                fgColor=t.autocompleteFgColor,
                                tb=t.tb, statusbar=false)

  var rows = newSeq[ListRow]()
  var enteredKey = ""
  var listWidth = 0
  for i, completion in enumerate(t.autocompleteList):
    let completionText = completion.icon & " " & completion.value & " " & completion.description
    rows.add(newListRow(i, completionText, completion.value,
                        bgColor=t.autocompleteBgColor, fgColor=t.autocompleteFgColor))
    if completionText.len > listWidth:
      listWidth = min(t.x2 - t.x1, completionText.len)
      if completionList.x1 + listWidth >= t.x2:
        completionList.posX = t.x2 - listWidth - 1
        completionList.posY += 1
        completionList.height += 1
      if completionList.y2 > t.y2:
        completionList.height = t.y2
        completionList.posY = t.y2 - t.autocompleteWindowSize
  completionList.width = completionList.x1 + listWidth

  let esc = proc(lv: ListView, args: varargs[string]) = lv.focus = false

  let captureKey = proc(lv: ListView, key: varargs[string]) =
    var numbers = initTable[string, string]()
    numbers["Zero"] = "0"
    numbers["One"] = "1"
    numbers["Two"] = "2"
    numbers["Three"] = "3"
    numbers["Four"] = "4"
    numbers["Five"] = "5"
    numbers["Six"] = "6"
    numbers["Seven"] = "7"
    numbers["Eight"] = "8"
    numbers["Nine"] = "9"

    var specialChars = initTable[string, string]()
    specialChars["Space"] = " "
    specialChars["ExclamationMark"] = "!"
    specialChars["DoubleQuote"] = "\""
    specialChars["Hash"] = "#"
    specialChars["Dollar"] = "$"
    specialChars["Percent"] = "%"
    specialChars["Ampersand"] = "&"
    specialChars["SingleQuote"] = "'"
    specialChars["LeftParen"] = "("
    specialChars["RightParen"] = ")"
    specialChars["Asterisk"] = "*"
    specialChars["Plus"] = "+"
    specialChars["Comma"] = ","
    specialChars["Minus"] = "-"
    specialChars["Dot"] = "."
    specialChars["Slash"] = "/"
    specialChars["Colon"] = ":"
    specialChars["Semicolon"] = ";"
    specialChars["LessThan"] = "<"
    specialChars["Equals"] = "="
    specialChars["GreaterThan"] = ">"
    specialChars["QuestionMark"] = "?"
    specialChars["At"] = "@"
    specialChars["LeftBracket"] = "["
    specialChars["BackSlash"] = "\\"
    specialChars["RightBracket"] = "]"
    specialChars["Caret"] = "^"
    specialChars["Underscore"] = "_"
    specialChars["GraveAccent"] = "~"
    specialChars["LeftBrace"] = "{"
    specialChars["Pipe"] = "|"
    specialChars["RightBrace"] = "}"
    specialChars["Tilde"] = "`"

    if key[0] == "Escape": enteredKey = ""
    elif numbers.hasKey(key[0]): enteredKey = numbers[key[0]]
    elif specialChars.hasKey(key[0]): enteredKey = specialChars[key[0]]
    elif key[0].startsWith("Shift"): enteredKey = key[0].replace("Shift", "")
    elif key[0] == "Backspace":
      enteredKey = ""
      t.backspace()
    elif key[0] == "Delete":
      enteredKey = ""
      if t.value.len > 0:
        t.value.delete(t.cursor .. t.cursor)
        if t.cursor == t.value.len: t.value &= " "
    elif key[0] == "Enter" or key[0] == "Left" or key[0] == "Right" or
      key[0] == "Insert" or key[0] == "Home" or key[0] == "End" or key[0] == "Tab":
      enteredKey = ""
    else: enteredKey = key[0].toLower()

  let enterEv = proc(lv: ListView, args: varargs[string]) =
    let selected = lv.selected.value
    for pos in currToken.startat..max(t.cursor, currToken.endat):
      if pos < t.value.len and t.value[pos] != '\n':
        t.value[pos] = ' '

    t.cursor = currToken.startat

    for s in selected.items():
      t.insert($s, t.cursor)
      t.cursorMove(1)
    t.insert(" ", t.cursor)
    t.cursorMove(1)

    lv.focus = false

  let escapeList = {Key.Space..Key.Backspace}
  let escapeList2 = {Key.Right..Key.End}
  for k in escapeList:
    completionList.on(k, esc)
  for k in escapeList2:
    completionList.on(k, esc)

  completionList.on(Key.Escape, esc)
  completionList.on("postupdate", captureKey)
  completionList.on("enter", enterEv)
  completionList.rows = rows
  completionList.illwillInit = true
  completionList.render()
  completionList.onControl()

  if enteredKey != "":
    t.insert(enteredKey, t.cursor)
    t.cursorMove(1)
    t.autocompleteList = newSeq[Completion]()


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


proc normalMode(t: TextArea) =
  ## Enhanced vi keybinding support
  ##
  ## .. code-block::
  ##   i, Insert   = switch to insert mode
  ##   I           = insert at beginning of line
  ##   v           = switch to visual mode
  ##   V           = switch to visual line mode
  ##   A           = append at end of line
  ##   o           = open new line below
  ##   O           = open new line above
  ##   r           = replace single character
  ##   R           = replace mode
  ##   s           = substitute character
  ##   S           = substitute line
  ##   c           = change command
  ##   C           = change to end of line
  ##   y           = yank command
  ##   Y           = yank line
  ##   Delete      = delete at cursor
  ##   Tab         = exit widget
  ##   Left, <-, H = move backward
  ##   Right, L    = move forward
  ##   Up, K       = move upward
  ##   Down, J     = move downward
  ##   Home, ^     = goto beginning of line
  ##   End, $      = goto end of line
  ##   0           = goto column 0
  ##   w           = goto next word
  ##   b           = goto previous word
  ##   e           = goto end of current word
  ##   x           = cut text at cursor
  ##   p           = paste last history at cursor
  ##   u           = undo last change
  ##   dd          = delete whole line
  ##   Escape      = back to normal mode
  while true:
    let keys = getKeysWithTimeout()
    let key = identifyKey(keys)

    case key
    of Key.I, Key.Insert:
      t.vimode = Insert
      t.render()
      break
    of Key.ShiftI:
      t.vimode = Insert
      t.moveToBegin()
      t.render()
      break
    of Key.V:
      t.vimode = Visual
      t.select()
      t.render()
      break
    of Key.ShiftA:
      t.vimode = Insert
      t.moveToEnd()
      inc t.cursor
      t.cursor = min(t.cursor, t.value.len - 1)
      t.render()
      break
    of Key.O:
      t.vimode = Insert
      t.moveToEnd()
      t.enter()
      t.render()
      break
    of Key.ShiftO:
      t.vimode = Insert
      t.moveToBegin()
      t.value.insert("\n", t.cursor)
      # cursor stays at same position (now first char of new line above)
      t.rowReCal()
      t.rowCursor = t.computeVisualRow()
      t.render()
      break
    of Key.R:
      t.statusbarText = " REPLACE "
      t.render()
      while true:
        let replaceKey = getKeyWithTimeout(1000)
        if replaceKey == Key.Escape:
          break
        elif replaceKey >= Key.A and replaceKey <= Key.Z:
          if t.cursor < t.value.len - 1:
            t.addToHistory("replace", t.cursor, $t.value[t.cursor])
            t.value[t.cursor] = chr(replaceKey.ord + 32)
            t.moveRight()
          break
        elif replaceKey >= Key.Zero and replaceKey <= Key.Nine:
          if t.cursor < t.value.len - 1:
            t.addToHistory("replace", t.cursor, $t.value[t.cursor])
            let numKeys = [Key.Zero, Key.One, Key.Two, Key.Three, Key.Four,
                          Key.Five, Key.Six, Key.Seven, Key.Eight, Key.Nine]
            let keyPos = numKeys.find(replaceKey)
            t.value[t.cursor] = chr(48 + keyPos)
            t.moveRight()
          break
        elif replaceKey == Key.Space:
          if t.cursor < t.value.len - 1:
            t.addToHistory("replace", t.cursor, $t.value[t.cursor])
            t.value[t.cursor] = ' '
            t.moveRight()
          break
      t.statusbarText = ""
      break
    of Key.S:
      t.vimode = Insert
      if t.cursor < t.value.len:
        t.addToHistory("substitute", t.cursor, $t.value[t.cursor])
        t.delAtCursor()
      t.render()
      break
    of Key.ShiftS:
      t.vimode = Insert
      t.moveToBegin()
      let startPos = t.cursor
      t.moveToEnd()
      let endPos = t.cursor
      if startPos <= endPos:
        t.addToHistory("substitute_line", startPos, t.value[startPos..endPos])
        t.delAtStartEndCursor(startPos, endPos)
      t.render()
      break
    of Key.C:
      t.statusbarText = " C "
      t.render()
      while true:
        let key2 = getKeyWithTimeout(1000)
        case key2
        of Key.C:
          t.vimode = Insert
          t.moveToBegin()
          let startPos = t.cursor
          t.moveToEnd()
          let endPos = t.cursor
          if startPos <= endPos:
            t.addToHistory("change_line", startPos, t.value[startPos..endPos])
            t.delAtStartEndCursor(startPos, endPos)
          break
        of Key.W:
          t.vimode = Insert
          let startPos = t.cursor
          t.moveToNextWord()
          let endPos = t.cursor - 1
          if startPos <= endPos:
            t.addToHistory("change_word", startPos, t.value[startPos..endPos])
            t.delAtStartEndCursor(startPos, endPos)
          break
        of Key.Escape:
          break
        else:
          discard
        sleep(t.rpms)
      t.statusbarText = ""
      if t.vimode == Insert:
        t.render()
        break
    of Key.ShiftC:
      t.vimode = Insert
      let startPos = t.cursor
      t.moveToEnd()
      let endPos = t.cursor
      if startPos <= endPos:
        t.addToHistory("change_to_end", startPos, t.value[startPos..endPos])
        t.delAtStartEndCursor(startPos, endPos)
      t.render()
      break
    of Key.Y:
      t.statusbarText = " Y "
      t.render()
      while true:
        let key2 = getKeyWithTimeout(1000)
        case key2
        of Key.Y:
          t.moveToBegin()
          let startPos = t.cursor
          t.moveToEnd()
          let endPos = t.cursor
          if startPos <= endPos:
            let content = t.value[startPos..endPos]
            t.addToHistory("yank_line", startPos, content)
          break
        of Key.W:
          let startPos = t.cursor
          t.moveToNextWord()
          let endPos = t.cursor - 1
          if startPos <= endPos:
            let content = t.value[startPos..endPos]
            t.addToHistory("yank_word", startPos, content)
          t.cursor = startPos
          break
        of Key.Escape:
          break
        else:
          discard
        sleep(t.rpms)
      t.statusbarText = ""
      break
    of Key.ShiftY:
      t.moveToBegin()
      let startPos = t.cursor
      t.moveToEnd()
      let endPos = t.cursor
      if startPos <= endPos:
        let content = t.value[startPos..endPos]
        t.addToHistory("yank_line", startPos, content)
      break
    of Key.Delete:
      t.delAtCursor()
    of Key.Tab:
      t.focus = false
      t.render()
      break
    of Key.Left, Key.Backspace, Key.H:
      t.moveLeft()
    of Key.Right, Key.L:
      t.moveRight()
    of Key.Up, Key.K:
      t.moveUp()
    of Key.Down, Key.J:
      t.moveDown()
    of Key.Home, Key.Caret:
      t.moveToBegin()
    of Key.End, Key.Dollar:
      t.moveToEnd()
    of Key.Zero:
      t.moveToBegin()
    of Key.W:
      t.moveToNextWord()
      t.render()
    of Key.B:
      t.moveToPrevWord()
      t.render()
    of Key.E:
      t.moveToEndOfWord()
      t.render()
    of Key.X:
      if t.cursor < t.value.len:
        t.addToHistory("cut", t.cursor, $t.value[t.cursor])
        t.delAtCursor()
    of Key.P:
      if t.cursor < t.value.len and t.viHistory.len > 0:
        let last = t.viHistory.popLast()
        t.putAtCursor(last.content)
        t.viHistory.addLast((cursor: t.cursor, content: last.content))
    of Key.U:
      t.undo()
      t.render()
    of Key.CtrlR:
      t.redo()
      t.render()
    of Key.D:
      t.statusbarText = " D "
      t.render()
      while true:
        var key2 = getKeyWithTimeout(1000)
        case key2
        of Key.D:
          t.delLine()
          break
        of Key.W:
          let startPos = t.cursor
          t.moveToNextWord()
          let endPos = t.cursor - 1
          if startPos <= endPos:
            t.addToHistory("delete_word", startPos, t.value[startPos..endPos])
            t.delAtStartEndCursor(startPos, endPos)
          break
        of Key.Escape:
          break
        else:
          discard
        sleep(t.rpms)
      let (r, c) = t.cursorAtLine()
      t.statusbarText = $r & ":" & $c
      t.render()
    of Key.ShiftG:
      t.cursor = t.value.len - 1
      t.rowReCal()
      t.rowCursor = t.computeVisualRow()
      t.render()
    of Key.G:
      t.statusbarText = " G "
      t.render()
      while true:
        var key2 = getKeyWithTimeout(1000)
        case key2
        of Key.G:
          t.cursor = 0
          t.rowCursor = 0
          t.scrollY = 0
          break
        of Key.Escape:
          break
        else:
          discard
        sleep(t.rpms)
      let (r, c) = t.cursorAtLine()
      t.statusbarText = $r & ":" & $c
      t.render()
    of Key.Colon:
      t.statusbarText = " :"
      t.render()
      t.commandEvent()
      let (r, c) = t.cursorAtLine()
      t.statusbarText = $r & ":" & $c
      t.render()
    else:
      if t.normalKeyEvents.hasKey(key):
        t.call(key)
      t.vimode = Normal
      t.statusbarText = ""
      t.render()

proc visualMode(t: TextArea) =
  ## Enhanced visual mode with line selection support
  ##
  ## .. code-block::
  ##   V           = switch to visual line mode
  ##   v           = switch back to visual mode
  ##   Delete      = delete selected text
  ##   d           = delete selected text
  ##   x           = cut selected text
  ##   y           = copy/yank selected text
  ##   c           = change selected text
  ##   Tab         = exit widget
  ##   Left, <-, H = move backward
  ##   Right, L    = move forward
  ##   Up, K       = move upward
  ##   Down, J     = move downward
  ##   Home, ^     = goto beginning of line
  ##   End, $      = goto end of line
  ##   0           = goto column 0
  ##   w           = goto next word
  ##   b           = goto previous word
  ##   e           = goto end of word
  ##   Escape      = back to normal mode
  var isLineMode = false

  while true:
    var key = getKeyWithTimeout(t.rpms)

    case key
    of Key.Escape:
      t.vimode = Normal
      t.render()
      break
    of Key.ShiftV:
      if not isLineMode:
        isLineMode = true
        t.moveToBegin()
        t.viSelection.startat = t.cursor
        t.moveToEnd()
        t.viSelection.endat = t.cursor
        t.statusbarText = " -- VISUAL LINE --"
      else:
        isLineMode = false
        t.statusbarText = " -- VISUAL --"
    of Key.V:
      if isLineMode:
        isLineMode = false
        t.statusbarText = " -- VISUAL --"
    of Key.Tab:
      t.focus = false
      t.render()
      break
    of Key.X, Key.D, Key.Delete:
      if t.cursor < t.value.len:
        let content = t.value[t.viSelection.startat..t.viSelection.endat]
        t.addToHistory("visual_delete", t.viSelection.startat, content)
        t.delAtStartEndCursor(t.viSelection.startat, t.viSelection.endat)
        t.vimode = Normal
        break
    of Key.C:
      if t.cursor < t.value.len:
        let content = t.value[t.viSelection.startat..t.viSelection.endat]
        t.addToHistory("visual_change", t.viSelection.startat, content)
        t.delAtStartEndCursor(t.viSelection.startat, t.viSelection.endat)
        t.vimode = Insert
        t.render()
        break
    of Key.Y:
      if t.cursor < t.value.len:
        let content = t.value[t.viSelection.startat..t.viSelection.endat]
        let cursor = if t.viSelection.direction == Left: t.cursor - content.len
          else: t.cursor + content.len
        t.addToHistory("visual_yank", cursor, content)
        t.vimode = Normal
        break
    of Key.Left, Key.Backspace, Key.H:
      if isLineMode:
        t.moveUp()
        t.moveToBegin()
        t.viSelection.startat = min(t.viSelection.startat, t.cursor)
      else:
        t.selectMoveLeft(key)
    of Key.Right, Key.L:
      if isLineMode:
        t.moveDown()
        t.moveToEnd()
        t.viSelection.endat = max(t.viSelection.endat, t.cursor)
      else:
        t.selectMoveRight(key)
    of Key.Up, Key.K:
      if isLineMode:
        t.moveUp()
        t.moveToBegin()
        t.viSelection.startat = min(t.viSelection.startat, t.cursor)
      else:
        t.selectMoveLeft(key)
    of Key.Down, Key.J:
      if isLineMode:
        t.moveDown()
        t.moveToEnd()
        t.viSelection.endat = max(t.viSelection.endat, t.cursor)
      else:
        t.selectMoveRight(key)
    of Key.Home, Key.Caret:
      if isLineMode:
        t.moveToBegin()
        t.viSelection.startat = t.cursor
      else:
        t.selectMoveLeft(key)
    of Key.End, Key.Dollar:
      if isLineMode:
        t.moveToEnd()
        t.viSelection.endat = t.cursor
      else:
        t.selectMoveRight(key)
    of Key.Zero:
      if isLineMode:
        t.moveToBegin()
        t.viSelection.startat = t.cursor
      else:
        t.selectMoveLeft(key)
    of Key.W:
      if isLineMode:
        t.moveToNextWord()
        t.viSelection.endat = max(t.viSelection.endat, t.cursor)
      else:
        t.selectMoveRight(key)
    of Key.B:
      if isLineMode:
        t.moveToPrevWord()
        t.viSelection.startat = min(t.viSelection.startat, t.cursor)
      else:
        t.selectMoveLeft(key)
    of Key.E:
      if isLineMode:
        t.moveToEndOfWord()
        t.viSelection.endat = max(t.viSelection.endat, t.cursor)
      else:
        t.selectMoveRight(key)
    else:
      if t.visualKeyEvents.hasKey(key):
        t.call(key)
      if not isLineMode:
        t.statusbarText = " -- VISUAL --"
      t.render()

    t.render()
    sleep(t.rpms)

method onUpdate*(t: TextArea, key: Key) =
  const FnKeys = {Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.F6,
                  Key.F7, Key.F8, Key.F9, Key.F10, Key.F11, Key.F12}
  const CtrlKeys = {Key.CtrlA, Key.CtrlB, Key.CtrlC, Key.CtrlD, Key.CtrlF,
                    Key.CtrlG, Key.CtrlH, Key.CtrlJ, Key.CtrlK, Key.CtrlL,
                    Key.CtrlN, Key.CtrlO, Key.CtrlP, Key.CtrlQ, Key.CtrlR,
                    Key.CtrlS, Key.CtrlT, Key.CtrlU, Key.CtrlW, Key.CtrlX,
                    Key.CtrlY, Key.CtrlZ}
  const NumericKeys = @[Key.Zero, Key.One, Key.Two, Key.Three, Key.Four,
                        Key.Five, Key.Six, Key.Seven, Key.Eight, Key.Nine]
  t.call("preupdate", $key)
  case key
  of Key.None:
    t.render()
    return
  of Key.Escape:
    if t.enableViMode:
      t.normalMode()
      return
    else: t.focus = false
  of Key.Tab:
    if t.enableViMode and t.vimode == Insert:
      t.insert(" ", t.cursor)
      t.insert(" ", t.cursor)
      t.insert(" ", t.cursor)
      t.insert(" ", t.cursor)
      t.cursorMove(4)
    else:
      t.focus = false
  of Key.Backspace:
    t.backspace()
  of Key.Delete:
    if t.value.len > 1 and t.cursor < t.value.len - 1:
      t.value.delete(t.cursor .. t.cursor)
      if t.value.len == 0: t.value = " "
      t.rowReCal()
      t.rowCursor = t.computeVisualRow()
  of Key.CtrlE:
    t.value = " "
    t.resetCursor()
    t.clear()
  of Key.ShiftA..Key.ShiftZ:
    let tmpKey = $key
    let alphabet = toSeq(tmpKey.items()).pop()
    t.insert($alphabet.toUpperAscii(), t.cursor)
    t.cursorMove(1)
  of Key.Zero..Key.Nine:
    let keyPos = NumericKeys.find(key)
    if keyPos > -1:
      t.insert($keyPos, t.cursor)
    t.cursorMove(1)
  of Key.Comma:
    t.insert(",", t.cursor)
    t.cursorMove(1)
  of Key.Colon:
    t.insert(":", t.cursor)
    t.cursorMove(1)
  of Key.Semicolon:
    t.insert(";", t.cursor)
    t.cursorMove(1)
  of Key.Underscore:
    t.insert("_", t.cursor)
    t.cursorMove(1)
  of Key.Dot:
    t.insert(".", t.cursor)
    t.cursorMove(1)
  of Key.Ampersand:
    t.insert("&", t.cursor)
    t.cursorMove(1)
  of Key.DoubleQuote:
    t.insert("\"", t.cursor)
    t.cursorMove(1)
  of Key.SingleQuote:
    t.insert("'", t.cursor)
    t.cursorMove(1)
  of Key.QuestionMark:
    t.insert("?", t.cursor)
    t.cursorMove(1)
  of Key.Space:
    t.insert(" ", t.cursor)
    t.cursorMove(1)
  of Key.Pipe:
    t.insert("|", t.cursor)
    t.cursorMove(1)
  of Key.Slash:
    t.insert("/", t.cursor)
    t.cursorMove(1)
  of Key.Equals:
    t.insert("=", t.cursor)
    t.cursorMove(1)
  of Key.Plus:
    t.insert("+", t.cursor)
    t.cursorMove(1)
  of Key.Minus:
    t.insert("-", t.cursor)
    t.cursorMove(1)
  of Key.Asterisk:
    t.insert("*", t.cursor)
    t.cursorMove(1)
  of Key.BackSlash:
    t.insert("\\", t.cursor)
    t.cursorMove(1)
  of Key.GreaterThan:
    t.insert(">", t.cursor)
    t.cursorMove(1)
  of Key.LessThan:
    t.insert("<", t.cursor)
    t.cursorMove(1)
  of Key.LeftBracket:
    t.insert("[", t.cursor)
    t.cursorMove(1)
  of Key.RightBracket:
    t.insert("]", t.cursor)
    t.cursorMove(1)
  of Key.LeftBrace:
    t.insert("{", t.cursor)
    t.cursorMove(1)
  of Key.RightBrace:
    t.insert("}", t.cursor)
    t.cursorMove(1)
  of Key.LeftParen:
    t.insert("(", t.cursor)
    t.cursorMove(1)
  of Key.RightParen:
    t.insert(")", t.cursor)
    t.cursorMove(1)
  of Key.Percent:
    t.insert("%", t.cursor)
    t.cursorMove(1)
  of Key.Hash:
    t.insert("#", t.cursor)
    t.cursorMove(1)
  of Key.Dollar:
    t.insert("$", t.cursor)
    t.cursorMove(1)
  of Key.ExclamationMark:
    t.insert("!", t.cursor)
    t.cursorMove(1)
  of Key.At:
    t.insert("@", t.cursor)
    t.cursorMove(1)
  of Key.Caret:
    t.insert("^", t.cursor)
    t.cursorMove(1)
  of Key.GraveAccent:
    t.insert("~", t.cursor)
    t.cursorMove(1)
  of Key.Tilde:
    t.insert("`", t.cursor)
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
    t.moveUp()
  of Key.Down:
    t.moveDown()
  of Key.Enter:
    t.enter()
    t.render()
  of FnKeys, CtrlKeys:
    if t.editKeyEvents.hasKey(key):
      t.call(key)
  else:
    var ch = $key
    t.insert(ch.toLower(), t.cursor)
    t.cursorMove(1)

  t.render()
  sleep(t.rpms)

  if t.enableAutocomplete: t.autocomplete()
  t.call("postupdate", $key)


proc editMode(t: TextArea) =
  while t.focus:
    var key = getKeyWithTimeout(t.rpms)
    if t.enableViMode and t.vimode == Normal and key in {Key.I, Key.ShiftI, Key.Insert}:
      t.vimode = Insert
      t.render()
    elif t.enableViMode and t.vimode == Normal and key in {Key.V, Key.ShiftV}:
      t.vimode = Visual
      t.select()
      continue
    elif t.enableViMode and t.vimode == Normal: break
    elif t.enableViMode and t.vimode == Visual: break
    else: t.onUpdate(key)


method onControl*(t: TextArea) =
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
    sleep(t.rpms)


method onMouseEvent*(t: TextArea, mouseInfo: MouseInfo) =
  if mouseInfo.scroll:
    if mouseInfo.scrollDir == ScrollDirection.sdUp:
      t.moveUp()
      t.render()
    elif mouseInfo.scrollDir == ScrollDirection.sdDown:
      t.moveDown()
      t.render()
  if not t.onMouse.isNil:
    t.onMouse(t, mouseInfo)

method wg*(t: TextArea): ref BaseWidget = t


proc value*(t: TextArea): string =
  result = t.value
  while result.len > 0 and result[^1] in {' ', '\n'}:
    result.setLen(result.len - 1)


proc val(t: TextArea, val: string) =
  t.clear()
  t.value = val & " "
  t.cursor = 0
  t.rowCursor = 0
  t.scrollY = 0
  t.rowReCal()


proc `value=`*(t: TextArea, val: string) =
  t.val(val)

proc value*(t: TextArea, val: string) =
  t.val(val)
