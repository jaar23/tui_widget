import illwill, os, strutils, base_wg, options, sequtils, encodings
import nimclipboard/libclipboard

type
  InputBox = object of BaseWidget
    cursor: int = 0
    value: string = ""
    visualVal: string = ""
    visualCursor: int = 2
    mode: string = "|"
    onEnter: Option[EnterEventProcedure]

  CursorDirection = enum
    Left, Right


var cb = clipboard_new(nil)

cb.clipboard_clear(LCB_CLIPBOARD)


proc newInputBox*(px, py, w, h: int, title = "", val: string = "", 
                  modeChar: char = '|', border: bool = true, statusbar: bool = false,
                  fgColor: ForegroundColor = fgWhite, bgColor: BackgroundColor = bgNone,
                  tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): ref InputBox =
  let padding = if border: 2 else: 1
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
    statusbarSize: statusbarSize
  )


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
  ib.clear()
  ib.renderBorder()
  if ib.title != "":
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



## optional callback proc function
#method onControl*(ib: ref InputBox, onEnter: Option[CallbackProcedure] = none(CallbackProcedure)) = 
method onControl*(ib: ref InputBox) = 
  const EscapeKeys = {Key.Escape, Key.Tab}
  const FnKeys = {Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.F6,
                  Key.F7, Key.F8, Key.F9, Key.F10, Key.F11, Key.F12}
  const CtrlKeys = {Key.CtrlA, Key.CtrlB, Key.CtrlC, Key.CtrlD, Key.CtrlF, 
                    Key.CtrlG, Key.CtrlH, Key.CtrlJ, Key.CtrlK, Key.CtrlL, 
                    Key.CtrlN, Key.CtrlO, Key.CtrlP, Key.CtrlQ, Key.CtrlR, 
                    Key.CtrlS, Key.CtrlT, Key.CtrlU, Key.CtrlW, Key.CtrlX, 
                    Key.CtrlY, Key.CtrlZ}
  const NumericKeys = @[Key.Zero, Key.One, Key.Two, Key.Three, Key.Four, 
                        Key.Five, Key.Six, Key.Seven, Key.Eight, Key.Nine]

  ib.focus = true
  ib.mode = ">"
  while ib.focus:
    var key = getKey()
    case key
    of Key.None, FnKeys, CtrlKeys: discard
    of EscapeKeys:
      ib.focus = false
      ib.mode = "|"
    of Key.Backspace, Key.Delete:
      if ib.cursor > 0:
        ib.value.delete(ib.cursor - 1..ib.cursor - 1)
        ib.cursorMove(Left)
        ib.visualCursor = ib.visualCursor - 1
        ib.clear()
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
    of Key.Up, Key.Down:
      discard
    of Key.CtrlV:
      let copiedText = $cb.clipboard_text()
      ib.value.insert(formatText(copiedText), ib.cursor)
      ib.cursor = ib.cursor + copiedText.len
    of Key.Enter:
      # when implementing function as a callback
      # if onEnter.isSome:
      #   let cb = onEnter.get
      #   cb(ib.value)
      if ib.onEnter.isSome:
        let fn = ib.onEnter.get
        fn(ib.value)
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
    sleep(20)


method onControl*(ib: ref InputBox, cb: Option[CallbackProcedure]): void =
  ib.onEnter = cb
  ib.onControl()


method wg*(ib: ref InputBox): ref BaseWidget = ib


proc value*(ib: ref InputBox, val: string) = ib.value = val


proc value*(ib: ref InputBox): string = ib.value


proc show*(ib: ref InputBox) = ib.render()


proc hide*(ib: ref InputBox) = ib.clear

proc terminalBuffer*(ib: ref InputBox): var TerminalBuffer =
  return ib.tb


proc onEnter*(ib: ref InputBox, cb: Option[EnterEventProcedure]) =
  ib.onEnter = cb


proc `- `*(ib: ref InputBox) = ib.show()


proc showStatusBar*(ib: ref InputBox): void = ib.statusbar = true


proc hideSize*(ib: ref InputBox): void = ib.statusbar = false

