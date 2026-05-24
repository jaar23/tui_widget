import illwill, strutils, base_wg, sequtils, encodings, unicode, algorithm
import tables, threading/channels, os, osproc, streams
import std/enumerate
import listview_wg

type
  InputBoxObj* = object of BaseWidget
    value: string = ""
    visualVal: string = ""
    visualCursor: int = 2
    mode: string = ">"
    textOverlay*: bool = false
      ## When true, render() skips the inner tb.write that paints the
      ## current value; a postDisplay hook is expected to overlay it via
      ## stdout. Used for CJK / wide-glyph input correctness.
    events*: Table[string, EventFn[InputBox]]
    keyEvents*: Table[Key, EventFn[InputBox]]
    enableAutocomplete*: bool = false
    autocompleteTrigger*: int = 3
    autocompleteList*: seq[Completion] = newSeq[Completion]()
    autocompleteWindowSize*: int = 5
    autocompleteBgColor*: BackgroundColor = bgCyan
    autocompleteFgColor*: ForegroundColor = fgWhite

  CursorDirection = enum
    Left, Right

  InputBox* = ref InputBoxObj

  IbWordToken = object
    startat: int
    endat: int
    token: string

const allowKeyBind = {Key.Up, Key.Down}

const allowFnKeys = {Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.F6,
                     Key.F7, Key.F8, Key.F9, Key.F10, Key.F11, Key.F12}
 
const allowCtrlKeys = {Key.CtrlA, Key.CtrlB, Key.CtrlC, Key.CtrlD, Key.CtrlF, 
                       Key.CtrlG, Key.CtrlH, Key.CtrlJ, Key.CtrlK, Key.CtrlL, 
                       Key.CtrlN, Key.CtrlO, Key.CtrlP, Key.CtrlQ, Key.CtrlR, 
                       Key.CtrlS, Key.CtrlT, Key.CtrlU, Key.CtrlW, Key.CtrlX, 
                       Key.CtrlV, Key.CtrlY, Key.CtrlZ}

proc formatText(val: string): string

proc on*(ib: InputBox, key: Key, fn: EventFn[InputBox]):void {.raises: [EventKeyError]} 

proc newInputBox*(px, py, w, h: int, title = "", val = "",
                  modeChar = '>', border = true, statusbar = false,
                  bgColor = bgNone, fgColor = fgWhite,
                  enableAutocomplete = false, autocompleteTrigger = 3,
                  tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): InputBox =
  var padding = if border: 1 else: 0
  padding = if modeChar != ' ': padding + 1 else: padding + 0
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
  result = InputBox(
    width: w,
    height: h,
    posX: px,
    posY: py,
    value: val,
    mode: $modeChar,
    title: title,
    tb: tb,
    style: style,
    statusbar: statusbar,
    statusbarSize: statusbarSize,
    events: initTable[string, EventFn[InputBox]](),
    keyEvents: initTable[Key, EventFn[InputBox]](),
    enableAutocomplete: enableAutocomplete,
    autocompleteTrigger: autocompleteTrigger
  )
  # to ensure key responsive, default to < 50  
  if result.rpms > 50: result.rpms = 50
  # register copy and paste events
  result.on(Key.CtrlC, proc(ib: InputBox, args: varargs[string]) =
    if ib.value.len > 0:
      base_wg.setClipboardText(ib.value)
  )
  
  result.on(Key.CtrlV, proc(ib: InputBox, args: varargs[string]) =
    let clipText = base_wg.getClipboardText()
    if clipText.len > 0:
      let formattedText = formatText(clipText)
      ib.value.insert(formattedText, ib.cursor)
      ib.cursor = ib.cursor + formattedText.len
  )
  result.channel = newChan[WidgetBgEvent]()
  result.keepOriginalSize()


proc newInputBox*(px, py: int, w, h: WidgetSize, title = "", val = "",
                  modeChar = '>', border = true, statusbar = false,
                  bgColor = bgNone,fgColor = fgWhite,
                  enableAutocomplete = false, autocompleteTrigger = 3,
                  tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): InputBox =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newInputBox(px, py, width, height, title, val, modeChar, border,
                     statusbar, bgColor, fgColor,
                     enableAutocomplete, autocompleteTrigger, tb)


proc newInputBox*(id: string): InputBox =
  var input = InputBox(
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
    events: initTable[string, EventFn[InputBox]](),
    keyEvents: initTable[Key, EventFn[InputBox]]()
  )
  # to ensure key responsive, default to < 50  
  if input.rpms > 50: input.rpms = 50
  # register copy and paste events
  input.on(Key.CtrlC, proc(ib: InputBox, args: varargs[string]) =
    if ib.value.len > 0:
      base_wg.setClipboardText(ib.value)
  )
  
  input.on(Key.CtrlV, proc(ib: InputBox, args: varargs[string]) =
    let clipText = base_wg.getClipboardText()
    if clipText.len > 0:
      let formattedText = formatText(clipText)
      ib.value.insert(formattedText, ib.cursor)
      ib.cursor = ib.cursor + formattedText.len
  )
  
  input.channel = newChan[WidgetBgEvent]()
  return input


proc rtlRange(val: string, size: int, cursor: int): (int, int, int) =
  var max = val.len
  var min = 0
  if val.len > size: 
    max = val.len
    min = max - size
  else: 
    max = val.len
    min = size - val.len
  if cursor < min:
    let diff = min - cursor
    min = min - diff
    max = max - diff
  ## cursor position within range
  var diff = max - cursor
  var cursorPos = size - diff

  return (min, max, cursorPos)


proc ltrRange(val: string, size: int, cursor: int): (int, int, int) =
  var max = val.len
  var min = 0
  if size > cursor:
    min = 0
    max = size
  else:
    max = cursor
    min = cursor - size
  if cursor >= val.len:
    max = val.len
    min = max - size
  var diff = max - cursor
  var cursorPos = size - diff
  return (min, max, cursorPos)


proc formatText(val: string): string = 
  let converted = val.convert()
  let replaced = converted.replace("\n", " ")
  return replaced


proc clear(ib: InputBox) =
  ib.tb.fill(ib.posX, ib.posY, ib.width, ib.height, " ")


proc renderStatusbar(ib: InputBox) =
  if ib.events.hasKey("statusbar"):
    ib.call("statusbar")
  else:
    let cursorStr = " " & $ib.cursor & ":" & $ib.value.len & " "
    ib.tb.fill(ib.x2 - cursorStr.len, ib.height, cursorStr.len, ib.height, " ")
    ib.tb.write(ib.x2 - cursorStr.len, ib.height, bgBlue, fgWhite, cursorStr, resetStyle)


method render*(ib: InputBox) =
  if not ib.illwillInit: return
  ib.clear()
  ib.renderBorder()
  ib.renderTitle()
  # When textOverlay is true, leave the value row blank; a postDisplay
  # hook writes the value via stdout so wide glyphs render correctly.
  if not ib.textOverlay:
    if ib.cursor < ib.value.len:
      ib.tb.write(ib.posX + 1, ib.posY + 1, ib.style.fgColor, ib.mode,
                  resetStyle, ib.visualVal.substr(0, ib.visualCursor - 1),
                  styleBlink, styleUnderscore, ib.style.bgColor,
                  ib.visualVal.substr(ib.visualCursor, ib.visualCursor),
                  resetStyle,
                  ib.visualVal.substr(ib.visualCursor + 1, ib.visualVal.len - 1))
    else:
      ib.tb.write(ib.posX + 1, ib.posY + 1, ib.style.fgColor, ib.mode,
                  resetStyle, ib.visualVal, ib.style.bgColor, styleBlink, "_", resetStyle)
  if ib.statusbar:
    ib.renderStatusbar()
  if not ib.suppressDisplay: ib.tb.display()


proc enableTextOverlay*(ib: InputBox) =
  ## Opt the input box into wide-glyph-correct rendering. The cursor is
  ## drawn at the END of the visible portion as a blinking underscore;
  ## mid-string cursor navigation through CJK content is a deeper
  ## refactor (the existing visualCursor is byte-indexed) — out of scope
  ## here. Typing flows (cursor naturally at end) work cleanly.
  ib.textOverlay = true
  ib.postDisplay = proc(wg: ref BaseWidget) =
    let ib = InputBox(wg)
    if not ib.illwillInit or not ib.textOverlay: return
    # Inner content area: one cell inside the border (left + top).
    let innerCol = ib.posX + 1 + 1   # TB cell + 1 padding
    let innerRow = ib.posY + 1 + 1
    let widthCells = max(1, ib.x2 - ib.x1)
    # Reserve one cell for the blinking cursor; clip the value tail-first
    # so the most recently typed glyphs are visible when overflowed.
    let prefix = ib.mode & " "
    let prefW  = visualWidth(prefix)
    let budget = max(1, widthCells - prefW - 1)
    var tailRunes: seq[Rune] = @[]
    var used = 0
    for r in ib.value.runes.toSeq.reversed:
      let w = runeWidth(r)
      if used + w > budget: break
      tailRunes.insert(r, 0)
      used += w
    var visible = ""
    for r in tailRunes: visible.add($r)
    let pad = max(0, budget - used)
    stdout.write("\e[", innerRow, ";", innerCol, "f",
                 prefix, visible, "\e[5;4m_\e[0m", " ".repeat(pad))


proc remove*(ib : InputBox) =
  ib.tb.fill(ib.posX, ib.posY, ib.width, ib.posY + 1, " ")
  ib.tb.fill(ib.posX, ib.posY, ib.width, ib.posY + 2, " ")
  ib.tb.fill(ib.posX, ib.posY, ib.width, ib.posY + 3, " ")
  ib.clear()


proc rerender(ib: InputBox) =
  ib.tb.fill(ib.posX, ib.posY, ib.width, ib.height, " ")
  ib.render()


proc overflowWidth(ib: InputBox, moved = 1) =
  ib.cursor = ib.cursor + moved


proc cursorMove(ib: InputBox, direction: CursorDirection) =
  case direction
  of Left:
    if ib.cursor >= 1:
      ib.cursor = ib.cursor - 1
    else:
      ib.cursor = 0
    let (s, e, vcursorPos) = rtlRange(ib.value, (ib.width - ib.posX - ib.paddingX1 - 1), ib.cursor)
    #let (s, e, vcursorPos) = rtlRange(ib.value, (ib.width - ib.paddingX1 - 1), ib.cursor)
    ib.visualVal = ib.value.substr(s, e)
    ib.visualCursor = vcursorPos
  of Right:
    if ib.cursor < ib.value.len:
      ib.cursor = ib.cursor + 1
    else:
      ib.cursor = ib.value.len
    let (s, e, vcursorPos) = ltrRange(ib.value, (ib.width - ib.posX - ib.paddingX1 - 1), ib.cursor)
    #let (s, e, vcursorPos) = ltrRange(ib.value, (ib.width - ib.paddingX1 - 1), ib.cursor)
    ib.visualVal = ib.value.substr(s, e)
    ib.visualCursor = vcursorPos


proc on*(ib: InputBox, event: string, fn: EventFn[InputBox]) =
  ib.events[event] = fn


proc on*(ib: InputBox, key: Key, fn: EventFn[InputBox]) {.raises: [EventKeyError]} =
  if key in allowKeyBind or key in allowFnKeys or key in allowCtrlKeys: 
    ib.keyEvents[key] = fn
  else:
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
    


method call*(ib: InputBox, event: string, args: varargs[string]) =
  if ib.events.hasKey(event):
    let fn = ib.events[event]
    fn(ib, args)


method call*(ib: InputBoxObj, event: string, args: varargs[string]) =
  if ib.events.hasKey(event):
    let fn = ib.events[event]
    fn(ib.asRef(), args)


proc call(ib: InputBox, key: Key, args: varargs[string]) =
  if ib.keyEvents.hasKey(key):
    let fn = ib.keyEvents[key]
    fn(ib, args)


proc recomputeVisual(ib: InputBox) =
  if ib.value.len >= ib.width - ib.paddingX1 - 1:
    let (s, e, cp) = rtlRange(ib.value, (ib.width - ib.posX - ib.paddingX2 - 1), ib.cursor)
    ib.visualVal = ib.value.substr(s, e)
    ib.visualCursor = cp
  else:
    let (s, e, cp) = ltrRange(ib.value, (ib.width - ib.posX - ib.paddingX2 - 1), ib.cursor)
    ib.visualVal = ib.value.substr(s, e)
    ib.visualCursor = cp


proc splitByToken(val: string): seq[IbWordToken] =
  result = newSeq[IbWordToken]()
  var pos = 0
  for token in val.split(' '):
    result.add(
      IbWordToken(
        startat: pos,
        endat: pos + token.len,
        token: token
      )
    )
    pos += max(1, token.len + 1)


proc autocomplete(ib: InputBox) =
  let tokens = splitByToken(ib.value)
  var currToken: IbWordToken

  for token in tokens:
    if ib.cursor >= token.startat and token.endat >= ib.cursor:
      currToken = token
      break

  if currToken.token.len >= ib.autocompleteTrigger:
    ib.call("autocomplete", currToken.token)
  else:
    ib.autocompleteList = newSeq[Completion]()

  if ib.autocompleteList.len == 0:
    return

  # Drop the suggestion list below the input row by default; flip above
  # if there isn't enough vertical room.
  var listPosY = ib.height + 1
  var listEndY = listPosY + ib.autocompleteWindowSize
  if listEndY >= consoleHeight():
    listPosY = max(0, ib.posY - ib.autocompleteWindowSize)
    listEndY = ib.posY

  var completionList = newListView(ib.posX, listPosY,
                                   ib.width, listEndY,
                                   selectionStyle = Highlight,
                                   bgColor = bgNone,
                                   fgColor = ib.autocompleteFgColor,
                                   tb = ib.tb,
                                   statusbar = false)

  var rows = newSeq[ListRow]()
  var enteredKey = ""
  var listWidth = 0
  for i, completion in enumerate(ib.autocompleteList):
    let completionText = completion.icon & " " & completion.value & " " & completion.description
    rows.add(newListRow(i, completionText, completion.value,
                        bgColor = ib.autocompleteBgColor,
                        fgColor = ib.autocompleteFgColor))
    if completionText.len > listWidth:
      listWidth = min(ib.width - ib.posX, completionText.len)
      if completionList.posX + listWidth >= ib.width:
        completionList.posX = max(ib.posX, ib.width - listWidth - 1)
  completionList.width = completionList.posX + listWidth

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
      if ib.cursor > 0:
        ib.value.delete(ib.cursor - 1 .. ib.cursor - 1)
        ib.cursor = ib.cursor - 1
    elif key[0] == "Delete":
      enteredKey = ""
      if ib.value.len > 0 and ib.cursor < ib.value.len:
        ib.value.delete(ib.cursor .. ib.cursor)
    elif key[0] == "Enter" or key[0] == "Left" or key[0] == "Right" or
      key[0] == "Insert" or key[0] == "Home" or key[0] == "End" or key[0] == "Tab":
      enteredKey = ""
    else: enteredKey = key[0].toLower()

  let enterEv = proc(lv: ListView, args: varargs[string]) =
    let selected = lv.selected.value
    let s = currToken.startat
    var e = max(ib.cursor, currToken.endat)
    if e > ib.value.len: e = ib.value.len
    if e > s:
      ib.value.delete(s .. e - 1)
    ib.cursor = s
    ib.value.insert(selected & " ", ib.cursor)
    ib.cursor = ib.cursor + selected.len + 1
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
    ib.value.insert(enteredKey, ib.cursor)
    ib.cursor = ib.cursor + enteredKey.len
    ib.autocompleteList = newSeq[Completion]()

  ib.recomputeVisual()


method onUpdate*(ib: InputBox, key: Key) =
  const EscapeKeys = {Key.Escape, Key.Tab}
  const NumericKeys = @[Key.Zero, Key.One, Key.Two, Key.Three, Key.Four, 
                        Key.Five, Key.Six, Key.Seven, Key.Eight, Key.Nine]
  ib.focus = true
  ib.call("preupdate", $key)
  case key
  of Key.None: discard
  of EscapeKeys:
    ib.focus = false
    ib.mode = "|"
    ib.rerender()
  of Key.Backspace:
    if ib.cursor > 0:
      ib.value.delete(ib.cursor - 1..ib.cursor - 1)
      ib.cursorMove(Left)
      ib.visualCursor = ib.visualCursor - 1
      ib.clear()
  of Key.Delete:
    if ib.value.len > 0:
      ib.value.delete(ib.cursor .. ib.cursor)
      if ib.cursor == ib.value.len: ib.value &= " "
  of Key.CtrlE:
    ib.value = ""
    ib.cursor = 0
    ib.clear()
  of Key.ShiftA..Key.ShiftZ:
    let tmpKey = $key
    let alphabet = toSeq(tmpKey.items()).pop()
    ib.value.insert($alphabet.toUpperAscii(), ib.cursor)
    ib.overflowWidth()
  of Key.Zero..Key.Nine:
    let keyPos = NumericKeys.find(key)
    if keyPos > -1:
      ib.value.insert($keyPos, ib.cursor)
      ib.overflowWidth()
  of Key.Comma:
    ib.value.insert(",", ib.cursor)
    ib.overflowWidth()
  of Key.Colon:
    ib.value.insert(":", ib.cursor)
    ib.overflowWidth()
  of Key.Semicolon:
    ib.value.insert(";", ib.cursor)
    ib.overflowWidth()
  of Key.Underscore:
    ib.value.insert("_", ib.cursor)
    ib.overflowWidth()
  of Key.Dot:
    ib.value.insert(".", ib.cursor)
    ib.overflowWidth()
  of Key.Ampersand:
    ib.value.insert("&", ib.cursor)
    ib.overflowWidth()
  of Key.DoubleQuote:
    ib.value.insert("\"", ib.cursor)
    ib.overflowWidth()
  of Key.SingleQuote:
    ib.value.insert("'", ib.cursor)
    ib.overflowWidth()
  of Key.QuestionMark:
    ib.value.insert("?", ib.cursor)
    ib.overflowWidth()
  of Key.Space:
    ib.value.insert(" ", ib.cursor)
    ib.overflowWidth()
  of Key.Pipe:
    ib.value.insert("|", ib.cursor)
    ib.overflowWidth()
  of Key.Slash:
    ib.value.insert("/", ib.cursor)
    ib.overflowWidth()
  of Key.Equals:
    ib.value.insert("=", ib.cursor)
    ib.overflowWidth()
  of Key.Plus:
    ib.value.insert("+", ib.cursor)
    ib.overflowWidth()
  of Key.Minus:
    ib.value.insert("-", ib.cursor)
    ib.overflowWidth()
  of Key.Asterisk:
    ib.value.insert("*", ib.cursor)
    ib.overflowWidth()
  of Key.BackSlash:
    ib.value.insert("\\", ib.cursor)
    ib.overflowWidth()
  of Key.GreaterThan:
    ib.value.insert(">", ib.cursor)
    ib.overflowWidth()
  of Key.LessThan:
    ib.value.insert("<", ib.cursor)
    ib.overflowWidth()
  of Key.LeftBracket:
    ib.value.insert("[", ib.cursor)
    ib.overflowWidth()
  of Key.RightBracket:
    ib.value.insert("]", ib.cursor)
    ib.overflowWidth()
  of Key.LeftBrace:
    ib.value.insert("{", ib.cursor)
    ib.overflowWidth()
  of Key.RightBrace:
    ib.value.insert("}", ib.cursor)
    ib.overflowWidth()
  of Key.Percent:
    ib.value.insert("%", ib.cursor)
    ib.overflowWidth()
  of Key.Hash:
    ib.value.insert("#", ib.cursor)
    ib.overflowWidth()
  of Key.Dollar:
    ib.value.insert("$", ib.cursor)
    ib.overflowWidth()
  of Key.ExclamationMark:
    ib.value.insert("!", ib.cursor)
    ib.overflowWidth()
  of Key.At:
    ib.value.insert("@", ib.cursor)
    ib.overflowWidth()
  of Key.Caret:
    ib.value.insert("^", ib.cursor)
    ib.overflowWidth()
  of Key.GraveAccent:
    ib.value.insert("~", ib.cursor)
    ib.overflowWidth()
  of Key.Tilde:
    ib.value.insert("`", ib.cursor)
    ib.overflowWidth()
  of Key.Home: 
    ib.cursor = 0
    ib.rerender()
  of Key.End: 
    ib.cursor = ib.value.len
    ib.rerender()
  of Key.PageUp, Key.PageDown, Key.Insert:
    discard
  of Key.Left:
    ib.cursorMove(Left)
    ib.rerender()
  of Key.Right: 
    ib.cursorMove(Right)
    ib.rerender()
  of Key.LeftParen:
    ib.value.insert("(", ib.cursor)
    ib.overflowWidth()
  of Key.RightParen:
    ib.value.insert(")", ib.cursor)
    ib.overflowWidth()
  of Key.Enter:
    ib.call("enter")
  of allowKeyBind:
    if ib.keyEvents.hasKey(key):
      ib.call(key)
  of allowFnKeys:
    if ib.keyEvents.hasKey(key):
      ib.call(key)
  of allowCtrlKeys:
    if ib.keyEvents.hasKey(key):
      ib.call(key)
  else:
    var ch = $key
    ib.value.insert(ch.toLower(), ib.cursor)
    ib.overflowWidth() 

  if ib.value.len >= ib.width - ib.paddingX1 - 1:
    # visualSkip for 2 bytes on the ui border and mode
    # 1 byte to push cursor at last
    let (s, e, cursorPos) = rtlRange(ib.value, (ib.width - ib.posX - ib.paddingX2 - 1), ib.cursor)
    #let (s, e, cursorPos) = rtlRange(ib.value, (ib.width - ib.paddingX1 - 1), ib.cursor)
    ib.visualVal = ib.value.substr(s, e)
    ib.visualCursor = cursorPos
  else:
    let (s, e, cursorPos) = ltrRange(ib.value, (ib.width - ib.posX - ib.paddingX2 - 1), ib.cursor)
    #let (s, e, cursorPos) = ltrRange(ib.value, (ib.width - ib.paddingX1 - 1), ib.cursor)
    ib.visualVal = ib.value.substr(s, e)
    ib.visualCursor = cursorPos

  if ib.enableAutocomplete: ib.autocomplete()

  ib.render()
  ib.call("postupdate", $key)


method onControl*(ib: InputBox) = 
  ib.focus = true
  ib.mode = ">"
  while ib.focus:
    var key = getKeyWithTimeout(ib.rpms)
    ib.onUpdate(key)
 

method onMouseEvent*(ib: InputBox, mouseInfo: MouseInfo) =
  if not ib.onMouse.isNil:
    ib.onMouse(ib, mouseInfo)

method wg*(ib: InputBox): ref BaseWidget = ib


proc val(ib: InputBox, val: string) =
  ib.value = formatText(val)
  ib.cursor = val.len
  ib.render()


proc `value=`*(ib: InputBox, val: string) = 
  ib.val(val)


proc value*(ib: InputBox, val: string) = 
  ib.val(val)


proc value*(ib: InputBox): string = ib.value


proc onEnter*(ib: InputBox, enterEv: EventFn[InputBox]) =
  ib.on("enter", enterEv)


proc `onEnter=`*(ib: InputBox, enterEv: EventFn[InputBox]) =
  ib.on("enter", enterEv)


