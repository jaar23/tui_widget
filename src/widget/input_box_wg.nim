import illwill, os, strutils, base_wg, sequtils, encodings
import nimclipboard/libclipboard
import tables

type
  InputBox* = object of BaseWidget
    value: string = ""
    visualVal: string = ""
    visualCursor: int = 2
    mode: string = "|"
    events*: Table[string, EventFn[ref InputBox]]
    keyEvents*: Table[Key, EventFn[ref InputBox]]

  CursorDirection = enum
    Left, Right

const allowKeyBind = {Key.Up, Key.Down}

const allowFnKeys = {Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.F6,
                     Key.F7, Key.F8, Key.F9, Key.F10, Key.F11, Key.F12}
 
const allowCtrlKeys = {Key.CtrlA, Key.CtrlB, Key.CtrlC, Key.CtrlD, Key.CtrlF, 
                       Key.CtrlG, Key.CtrlH, Key.CtrlJ, Key.CtrlK, Key.CtrlL, 
                       Key.CtrlN, Key.CtrlO, Key.CtrlP, Key.CtrlQ, Key.CtrlR, 
                       Key.CtrlS, Key.CtrlT, Key.CtrlU, Key.CtrlW, Key.CtrlX, 
                       Key.CtrlY, Key.CtrlZ}

var cb = clipboard_new(nil)

cb.clipboard_clear(LCB_CLIPBOARD)


proc newInputBox*(px, py, w, h: int, title = "", val: string = "", 
                  modeChar: char = '|', border: bool = true, statusbar: bool = false,
                  fgColor: ForegroundColor = fgWhite, bgColor: BackgroundColor = bgNone,
                  tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): ref InputBox =
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
  result = (ref InputBox)(
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
    events: initTable[string, EventFn[ref InputBox]](),
    keyEvents: initTable[Key, EventFn[ref InputBox]]()
  )
  # to ensure key responsive, default to < 50  
  if result.refreshWaitTime > 50: result.refreshWaitTime = 50


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


proc clear(ib: ref InputBox) =
  ib.tb.fill(ib.posX, ib.posY, ib.width, ib.height, " ")


method render*(ib: ref InputBox) =
  if not ib.illwillInit: return
  ib.clear()
  ib.renderBorder()
  ib.renderTitle()
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
    let sizeStr = $ib.value.len
    ib.tb.fill(ib.posX + 2, ib.posY + 2, sizeStr.len, ib.posY + 2, " ")
    ib.tb.write(ib.posX + 2, ib.posY + 2, fgYellow, $ib.value.len, resetStyle)
  ib.tb.display()


proc remove*(ib : ref InputBox) =
  ib.tb.fill(ib.posX, ib.posY, ib.width, ib.posY + 1, " ")
  ib.tb.fill(ib.posX, ib.posY, ib.width, ib.posY + 2, " ")
  ib.tb.fill(ib.posX, ib.posY, ib.width, ib.posY + 3, " ")
  ib.clear()


proc rerender(ib: ref InputBox) =
  ib.tb.fill(ib.posX, ib.posY, ib.width, ib.height, " ")
  ib.render()


proc overflowWidth(ib: ref InputBox, moved = 1) =
  ib.cursor = ib.cursor + moved


proc cursorMove(ib: ref InputBox, direction: CursorDirection) =
  case direction
  of Left:
    if ib.cursor >= 1:
      ib.cursor = ib.cursor - 1
    else:
      ib.cursor = 0
    let (s, e, vcursorPos) = rtlRange(ib.value, (ib.width - ib.paddingX1 - 1), ib.cursor)
    ib.visualVal = ib.value.substr(s, e)
    ib.visualCursor = vcursorPos
  of Right:
    if ib.cursor < ib.value.len:
      ib.cursor = ib.cursor + 1
    else:
      ib.cursor = ib.value.len
    let (s, e, vcursorPos) = ltrRange(ib.value, (ib.width - ib.paddingX1 - 1), ib.cursor)
    ib.visualVal = ib.value.substr(s, e)
    ib.visualCursor = vcursorPos


proc on*(ib: ref InputBox, event: string, fn: EventFn[ref InputBox]) =
  ib.events[event] = fn


proc on*(ib: ref InputBox, key: Key, fn: EventFn[ref InputBox]) {.raises: [EventKeyError]} =
  if key in allowKeyBind or key in allowFnKeys or key in allowCtrlKeys: 
    ib.keyEvents[key] = fn
  else:
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
    


proc call*(ib: ref InputBox, event: string, args: varargs[string]) =
  let fn = ib.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(ib, args)


proc call(ib: ref InputBox, key: Key, args: varargs[string]) =
  let fn = ib.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(ib, args)


## optional callback proc function
#method onControl*(ib: ref InputBox, onEnter: Option[CallbackProcedure] = none(CallbackProcedure)) = 
method onControl*(ib: ref InputBox) = 
  const EscapeKeys = {Key.Escape, Key.Tab}
  # const FnKeys = {Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.F6,
  #                 Key.F7, Key.F8, Key.F9, Key.F10, Key.F11, Key.F12}
  # const CtrlKeys = {Key.CtrlA, Key.CtrlB, Key.CtrlC, Key.CtrlD, Key.CtrlF, 
  #                   Key.CtrlG, Key.CtrlH, Key.CtrlJ, Key.CtrlK, Key.CtrlL, 
  #                   Key.CtrlN, Key.CtrlO, Key.CtrlP, Key.CtrlQ, Key.CtrlR, 
  #                   Key.CtrlS, Key.CtrlT, Key.CtrlU, Key.CtrlW, Key.CtrlX, 
  #                   Key.CtrlY, Key.CtrlZ}
  const NumericKeys = @[Key.Zero, Key.One, Key.Two, Key.Three, Key.Four, 
                        Key.Five, Key.Six, Key.Seven, Key.Eight, Key.Nine]

  ib.focus = true
  ib.mode = ">"
  while ib.focus:
    var key = getKeyWithTimeout(ib.refreshWaitTime)
    case key
    of Key.None: discard
    of EscapeKeys:
      ib.focus = false
      ib.mode = "|"
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
      ib.value.insert("(", ib.cursor)
      ib.overflowWidth()
    of Key.RightBrace:
      ib.value.insert(")", ib.cursor)
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
    # of Key.Up, Key.Down: discard 
    #   if ib.onUp.isSome:
    #     let fn = ib.onUp.get
    #     fn(ib)
    # of Key.Down:
    #   if ib.onDown.isSome:
    #     let fn = ib.onDown.get
    #     fn(ib)
    of Key.CtrlV:
      let copiedText = $cb.clipboard_text()
      ib.value.insert(formatText(copiedText), ib.cursor)
      ib.cursor = ib.cursor + copiedText.len
    of Key.Enter:
      ib.call("enter")
      # when implementing function as a callback
      # if onEnter.isSome:
      #   let cb = onEnter.get
      #   cb(ib.value)
      # if ib.onEnter.isSome:
      #   let fn = ib.onEnter.get
      #   fn(ib.value)
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
      let (s, e, cursorPos) = rtlRange(ib.value, (ib.width - ib.paddingX1 - 1), ib.cursor)
      ib.visualVal = ib.value.substr(s, e)
      ib.visualCursor = cursorPos 
    else:
      let (s, e, cursorPos) = ltrRange(ib.value, (ib.width - ib.paddingX1 - 1), ib.cursor)
      ib.visualVal = ib.value.substr(s, e)
      ib.visualCursor = cursorPos 

    ib.render()
    sleep(ib.refreshWaitTime)


# method onControl*(ib: ref InputBox, enterEv: EventFn[ref InputBox]): void =
#   ib.on("enter", enterEv)
#   ib.onControl()
#

method wg*(ib: ref InputBox): ref BaseWidget = ib


proc val(ib: ref InputBox, val: string) =
  ib.value = formatText(val)
  ib.cursor = val.len
  ib.render()


proc `value=`*(ib: ref InputBox, val: string) = 
  ib.val(val)


proc value*(ib: ref InputBox, val: string) = 
  ib.val(val)


proc value*(ib: ref InputBox): string = ib.value


proc onEnter*(ib: ref InputBox, enterEv: EventFn[ref InputBox]) =
  ib.on("enter", enterEv)


proc `onEnter=`*(ib: ref InputBox, enterEv: EventFn[ref InputBox]) =
  ib.on("enter", enterEv)


# proc `onUp=`*(ib: ref InputBox, ev: UpEventProcedure) =
#   ib.onUp = some(ev)
#
#
# proc `onDown=`*(ib: ref InputBox, ev: DownEventProcedure) =
#   ib.onDown = some(ev)
#

