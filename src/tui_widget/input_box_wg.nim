import illwill, os, strutils, base_wg

type
  InputBox* = ref object of BaseWidget
    row*: int = 1
    size*: int
    cursor: int = 0
    value: string = ""
    visualVal: string = ""
    visualCursor: int = 2
    mode: string = "|"
    visualSkip: int = 2

  CursorDirection = enum
    Left, Right


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



proc render*(ib: var InputBox, tb: var TerminalBuffer) =
  tb.drawRect(ib.width, ib.height, ib.posX, ib.posY, doubleStyle=ib.focus)
  if ib.cursor < ib.value.len:
    tb.write(ib.posX + 1, ib.posY + 1, fgGreen, ib.mode, 
             resetStyle, ib.visualVal.substr(0, ib.visualCursor - 1),
             bgGreen, ib.visualVal.substr(ib.visualCursor, ib.visualCursor),
             resetStyle, ib.visualVal.substr(ib.visualCursor + 1, ib.visualVal.len - 1))
  else:
    tb.write(ib.posX + 1, ib.posY + 1, fgGreen, ib.mode, 
             resetStyle, ib.visualVal, bgGreen, " ", resetStyle)
  tb.display()


proc overflowWidth(ib: var InputBox, moved = 1) =
  ib.cursor = ib.cursor + moved


proc cursorMove(ib: var InputBox, direction: CursorDirection) =
  case direction
  of Left:
    echo "\ncursor: " & $ib.cursor
    echo "vcursor:" & $ib.visualCursor
    echo "value len: " & $ib.value.len
    if ib.cursor >= 1:
      ib.cursor = ib.cursor - 1
    else:
      ib.cursor = 0
    let (s, e, vcursorPos) = rtlRange(ib.value, (ib.width - ib.visualSkip - 1), ib.cursor)
    ib.visualVal = ib.value.substr(s, e)
    ib.visualCursor = vcursorPos
    echo "\n\n" & ib.visualVal
  of Right:
    echo "\ncursor: " & $ib.cursor
    echo "vcursor:" & $ib.visualCursor    
    echo "value len: " & $ib.value.len
    if ib.cursor < ib.value.len:
      ib.cursor = ib.cursor + 1
    else:
      ib.cursor = ib.value.len
    let (s, e, vcursorPos) = ltrRange(ib.value, (ib.width - ib.visualSkip - 1), ib.cursor)
    ib.visualVal = ib.value.substr(s, e)
    ib.visualCursor = vcursorPos


proc onInput*(ib: var InputBox, tb: var TerminalBuffer) = 
  ib.focus = true
  ib.mode = ">"
  while ib.focus:
    var key = getKey()
    case key
    of Key.None: discard
    of Key.Escape:
      ib.focus = false
      ib.mode = "|"
    of Key.Backspace:
      if ib.cursor > 0:
        ib.value.delete(ib.cursor - 1..ib.cursor - 1)
        ib.cursorMove(Left)
        ib.visualCursor = ib.visualCursor - 1
        tb.clear()
    of Key.CtrlE:
      ib.value = ""
      tb.clear()
    of Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.F6:
      discard
    of Key.F7, Key.F8, Key.F9, Key.F10, Key.F11, Key.F12:
      discard
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
    of Key.Tab:
      ib.value.insert("    ", ib.cursor)
      ib.overflowWidth(moved=4)
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
    of Key.One: 
      ib.value.insert("1", ib.cursor)
      ib.overflowWidth()
    of Key.Two:
      ib.value.insert("2", ib.cursor)
      ib.overflowWidth()
    of Key.Three:
      ib.value.insert("3", ib.cursor)
      ib.overflowWidth()
    of Key.Four:
      ib.value.insert("4", ib.cursor)
      ib.overflowWidth()
    of Key.Five:
      ib.value.insert("5", ib.cursor)
      ib.overflowWidth()
    of Key.Six:
      ib.value.insert("6", ib.cursor)
      ib.overflowWidth()
    of Key.Seven:
      ib.value.insert("7", ib.cursor)
      ib.overflowWidth()
    of Key.Eight:
      ib.value.insert("8", ib.cursor)
      ib.overflowWidth()
    of Key.Nine:
      ib.value.insert("9", ib.cursor)
      ib.overflowWidth()
    of Key.Zero:
      ib.value.insert("0", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftA:
      ib.value.insert("A", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftB:
      ib.value.insert("B", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftC:
      ib.value.insert("C", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftD:
      ib.value.insert("D", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftE:
      ib.value.insert("E", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftF:
      ib.value.insert("F", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftG:
      ib.value.insert("G", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftH:
      ib.value.insert("H", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftI:
      ib.value.insert("I", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftJ:
      ib.value.insert("J", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftK:
      ib.value.insert("K", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftL:
      ib.value.insert("L", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftM:
      ib.value.insert("M", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftN:
      ib.value.insert("N", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftO:
      ib.value.insert("O", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftP:
      ib.value.insert("P", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftQ:
      ib.value.insert("Q", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftR:
      ib.value.insert("R", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftS:
      ib.value.insert("S", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftT:
      ib.value.insert("T", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftU:
      ib.value.insert("U", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftV:
      ib.value.insert("V", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftW:
      ib.value.insert("W", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftX:
      ib.value.insert("X", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftY:
      ib.value.insert("Y", ib.cursor)
      ib.overflowWidth()
    of Key.ShiftZ:
      ib.value.insert("Z", ib.cursor)
      ib.overflowWidth()
    of Key.Home, Key.End, Key.PageUp, Key.PageDown, Key.Insert:
      discard
    of Key.Left:
      ib.cursorMove(Left)
      tb.clear()
    of Key.Right: 
      ib.cursorMove(Right)
      tb.clear()
    of Key.Up, Key.Down:
      discard
    of Key.Enter:
      discard
    else:
      var ch = $key
      ib.value.insert(ch.toLower(), ib.cursor)
      ib.overflowWidth() 

    if ib.value.len >= ib.width - ib.visualSkip - 1:
      # visualSkip for 2 bytes on the ui border and mode
      # 1 byte to push cursor at last
      let (s, e, cursorPos) = rtlRange(ib.value, (ib.width - ib.visualSkip - 1), ib.cursor)
      ib.visualVal = ib.value.substr(s, e)
      ib.visualCursor = cursorPos 
    else:
      let (s, e, cursorPos) = ltrRange(ib.value, (ib.width - ib.visualSkip - 1), ib.cursor)
      ib.visualVal = ib.value.substr(s, e)
      ib.visualCursor = cursorPos 

      # ib.visualVal = ib.value
      # ib.visualCursor = 2
    ib.render(tb)
    sleep(10)


proc value*(ib: var InputBox): string = ib.value
