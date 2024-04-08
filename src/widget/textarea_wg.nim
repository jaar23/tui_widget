import illwill, base_wg, os, sequtils, strutils
import std/wordwrap, std/enumerate
import nimclipboard/libclipboard


type
  TextArea* = object of BaseWidget
    textRows: seq[string] = newSeq[string]()
    value: string = ""
    rows: int = 0
    cols: int = 0


var cb = clipboard_new(nil)

cb.clipboard_clear(LCB_CLIPBOARD)

proc newTextArea*(px, py, w, h: int, title=""; val=" ";
                  border = true; statusbar = false; 
                  fgColor = fgWhite; bgColor = bgNone; 
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
  #var buff = initTextBuffer(rows, cols)
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
    statusbar: statusbar,
    statusbarSize: statusbarSize
  )
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

func onEnter(t: ref TextArea) =
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


method render*(t: ref TextArea) =
  t.clear()
  t.renderBorder()
  t.renderTitle()
  t.rowReCal() 
  #echo $t.textRows
  var index = 1
  if t.textRows.len > 0:
    let rowStart = if t.rowCursor < t.size: 0 else: min(t.rowCursor - t.size + 1, t.textRows.len - 1)
    let rowEnd = min(t.textRows.len - 1, rowStart + (min(t.size - t.statusbarSize, t.rows)))
    var vcursor = if rowStart > 0: rowStart * t.cols else: 0
    for row in t.textRows[rowStart .. min(rowEnd, t.textRows.len)]:
      t.renderCleanRow(index)
      for i, c in enumerate(row.items()):
        if vcursor == t.cursor:
          let ch = if c == ' ': '_' else: c
          t.tb.write(t.x1 + i, t.posY + index, styleBlink, 
                     styleUnderscore, bgBlue, $ch, resetStyle)
        else:
          t.tb.write(t.x1 + i, t.posY + index, $c, resetStyle)
        inc vcursor 
      inc index
  if t.statusbar:
    let statusbarText = "size: " & $t.value.len & " character(s)"
    # for debug
    # let cval = if t.value.len > 0: $t.value[t.cursor] else: " "
    # let statusbarText = $t.cursor & "|" & $t.rowCursor & "|" & cval & "|len:" & $t.value.len
    t.renderCleanRect(t.x1, t.height, statusbarText.len, t.height)
    t.tb.write(t.x1, t.height, fgCyan, statusbarText, resetStyle)
  t.tb.display()


proc resetCursor*(t: ref TextArea) =
  t.rowCursor = 0
  t.cursor = 0


method onControl*(t: ref TextArea) =
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
  t.focus = true
  while t.focus:
    var key = getKey()
    case key
    of Key.None, FnKeys, CtrlKeys: continue
    of EscapeKeys: t.focus = false
    of Key.Backspace, Key.Delete:
      if t.cursor > 0:
        t.value.delete(t.cursor - 1..t.cursor - 1)
        t.cursorMove(-1)
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
      t.value.insert("(", t.cursor)
      t.cursorMove(1)
    of Key.RightBrace:
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
    of Key.Home: discard
      # t.cursor = 0
    of Key.End: discard
      # t.cursor = t.value.len - 1
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
      t.onEnter()
      t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)
    else:
      var ch = $key
      t.value.insert(ch.toLower(), t.cursor)
      t.cursorMove(1)

    t.render()
    sleep(t.refreshWaitTime)


method wg*(t: ref TextArea): ref BaseWidget = t


proc value*(t: ref TextArea): string = 
  return t.value[0 ..< t.value.len - 1]


proc `value=`*(t: ref TextArea, val: string) =
  t.clear()
  t.value = val
  t.rowReCal()
  t.render()
