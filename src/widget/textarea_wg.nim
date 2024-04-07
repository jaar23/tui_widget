import illwill, base_wg, input_box_wg, os, math, sequtils, strutils
import std/wordwrap, std/enumerate


type
  RowTup = tuple
    min: int
    max: int
    val: string

  TextArea* = object of BaseWidget
    textRows: seq[string] = newSeq[string]()
    textBuffer: seq[string]
    value: string = ""
    rows: int
    cols: int


# proc initTextBuffer(rows, cols: int): seq[string] =
#   var buff = newSeq[string]()
#   for i in 0..< rows:
#     buff.add(repeat('*', cols))
#   return buff
#

proc newTextArea*(px, py, w, h, rows, cols: int, title=""; val=" ";
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
    rows: rows,
    cols: cols,
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
    let wrappedWords = val.wrapWords(size)
    result = wrappedWords.split("\n")
    result[result.len - 1] &= " "
  else:
    result.add(val)


func rowReCal(t: ref TextArea) =
  t.textRows = splitBySize(t.value, t.cols - t.paddingX1 - t.paddingX2, t.rows)


func onEnter(t: ref TextArea) =
  t.value.insert(repeat(' ', t.cols - 3), t.cursor)
  t.value &= " "
  t.cursor += t.cols
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
  if t.cursor < t.cols * max(t.rowCursor, 1):
    t.rowCursor = max(0, t.rowCursor - 1)


func moveRight(t: ref TextArea) =
  t.cursor = min(t.value.len - 1, t.cursor + 1)
  if t.cursor > t.cols:
    t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)


func cursorMove(t: ref TextArea, moved: int) =
  t.cursor = t.cursor + moved
  if t.cursor > t.value.len: t.cursor = t.value.len - 1
  if t.cursor < 0: t.cursor = 0
  if t.cursor > t.cols:
    t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)
  elif t.cursor < t.cols * max(t.rowCursor, 1):
    t.rowCursor = max(0, t.rowCursor - 1)


method render*(t: ref TextArea) =
  t.clear()
  t.renderBorder()
  t.renderTitle()
  t.rowReCal() 
  var index = 1
  var ir = false
  if t.textRows.len > 0:
    let rowStart = if t.rowCursor < t.size: 0 else: min(t.rowCursor - t.size + 1, t.textRows.len - 1)
    let rowEnd = min(t.textRows.len - 1, t.rowCursor + t.size - t.statusbarSize)
    setDoubleBuffering(false)
    var vcursor = 0
    for row in t.textRows[rowStart .. min(rowEnd, t.textRows.len)]:
      var pos = 0
      t.renderCleanRow(index)
      #if t.cursor >= row.min and t.cursor <= row.max:
      #ir = true
      for i, c in enumerate(row.items()):
        if vcursor == t.cursor:
          let ch = if c == ' ': '_' else: c
          t.tb.write(t.x1 + i, t.posY + index, styleBlink, 
                     styleUnderscore, bgBlue, $ch, resetStyle)
        else:
          t.tb.write(t.x1 + i, t.posY + index, bgGreen, $c, resetStyle)
        inc pos
        inc vcursor 

      # else:
      #   t.renderRow(row.val, index)
      inc index
  if t.statusbar:
    # let statusbarText = "size: " & $(t.value.len/1024).toInt() & " character(s)"
    let cval = if t.value.len > 0: $t.value[t.cursor] else: " "
    let statusbarText = $t.cursor & "|" & $t.rowCursor & "|" & $ir & "|" & cval & "|len:" & $t.value.len
    t.renderCleanRect(t.x1, t.height, statusbarText.len, t.height)
    t.tb.write(t.x1, t.height, fgCyan, statusbarText, resetStyle)
  t.tb.display()
  setDoubleBuffering(true)


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
  var moved = 1
  t.focus = true
  while t.focus:
    var key = getKey()
    case key
    of Key.None, FnKeys, CtrlKeys: continue
    of EscapeKeys: discard
    of Key.Backspace, Key.Delete:
      if t.cursor > 0:
        t.value.delete(t.cursor - 1..t.cursor - 1)
        moved = -1
    of Key.CtrlE:
      t.value = ""
      t.cursor = 0
      t.clear()
    of Key.ShiftA..Key.ShiftZ:
      let tmpKey = $key
      let alphabet = toSeq(tmpKey.items()).pop()
      t.value.insert($alphabet.toUpperAscii(), t.cursor)
    of Key.Zero..Key.Nine:
      let keyPos = NumericKeys.find(key)
      if keyPos > -1:
        t.value.insert($keyPos, t.cursor)
    of Key.Comma:
      t.value.insert(",", t.cursor)
    of Key.Colon:
      t.value.insert(":", t.cursor)
    of Key.Semicolon:
      t.value.insert(";", t.cursor)
    of Key.Underscore:
      t.value.insert("_", t.cursor)
    of Key.Dot:
      t.value.insert(".", t.cursor)
    of Key.Ampersand:
      t.value.insert("&", t.cursor)
    of Key.DoubleQuote:
      t.value.insert("\"", t.cursor)
    of Key.SingleQuote:
      t.value.insert("'", t.cursor)
    of Key.QuestionMark:
      t.value.insert("?", t.cursor)
    of Key.Space:
      t.value.insert(" ", t.cursor)
    of Key.Pipe:
      t.value.insert("|", t.cursor)
    of Key.Slash:
      t.value.insert("/", t.cursor)
    of Key.Equals:
      t.value.insert("=", t.cursor)
    of Key.Plus:
      t.value.insert("+", t.cursor)
    of Key.Minus:
      t.value.insert("-", t.cursor)
    of Key.Asterisk:
      t.value.insert("*", t.cursor)
    of Key.BackSlash:
      t.value.insert("\\", t.cursor)
    of Key.GreaterThan:
      t.value.insert(">", t.cursor)
    of Key.LessThan:
      t.value.insert("<", t.cursor)
    of Key.LeftBracket:
      t.value.insert("[", t.cursor)
    of Key.RightBracket:
      t.value.insert("]", t.cursor)
    of Key.LeftBrace:
      t.value.insert("(", t.cursor)
    of Key.RightBrace:
      t.value.insert(")", t.cursor)
    of Key.Percent:
      t.value.insert("%", t.cursor)
    of Key.Hash:
      t.value.insert("#", t.cursor)
    of Key.Dollar:
      t.value.insert("$", t.cursor)
    of Key.ExclamationMark:
      t.value.insert("!", t.cursor)
    of Key.At:
      t.value.insert("@", t.cursor)
    of Key.Caret:
      t.value.insert("^", t.cursor)
    of Key.GraveAccent:
      t.value.insert("~", t.cursor)
    of Key.Tilde:
      t.value.insert("`", t.cursor)
    of Key.Home: 
      t.cursor = 0
      #t.render()
      moved = 0
    of Key.End: 
      t.cursor = t.value.len
      #t.render()
      moved = 0
    of Key.PageUp, Key.PageDown, Key.Insert:
      discard
    of Key.Left:
      t.moveLeft()
      moved = 0
      #t.render()
    of Key.Right: 
      t.moveRight()
      moved = 0
      #t.render()
    of Key.Up: 
      t.moveUp()
      t.rowCursor = max(t.rowCursor - 1, 0)
      moved = 0
      #t.render()
    of Key.Down: 
      t.moveDown()
      moved = 0
      t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)
      #t.render()
    of Key.CtrlV: discard
      # let copiedText = $cb.clipboard_text()
      # t.value.insert(formatText(copiedText), t.cursor)
      # t.cursor = t.cursor + copiedText.len
    of Key.Enter: 
      t.onEnter()
      moved = 0
      t.rowCursor = min(t.textRows.len - 1, t.rowCursor + 1)
      #t.render()
    else:
      var ch = $key
      t.value.insert(ch.toLower(), t.cursor)
    
    t.cursorMove(moved)
    # var key = getKey()
    # case key
    # of Key.None: 
    #   discard
    #   #t.rows[t.rowCursor].focus = true
    # of Key.Enter: 
    #   t.rowCursor = min(t.rows.len - 1, t.rowCursor + 1)
    #   #t.rows[t.rowCursor].focus = true
    # of Key.Up: 
    #   t.rowCursor = max(t.rowCursor - 1, 0)
    #   #t.rows[t.rowCursor].focus = true
    # of Key.Down: 
    #   t.rowCursor = min(t.rows.len - 1, t.rowCursor + 1)
    #   #t.rows[t.rowCursor].focus = true
    # else:
    # for i in 0 ..< t.rows.len:
    #   # if i != t.rowCursor: t.focus = false
    #   t.rows[i].render()
    #
    # t.rows[t.rowCursor].onControl(proc(arg: string) =
    #   t.rows[t.rowCursor].focus = false
    #   t.rows[t.rowCursor].render()
    #   t.rowCursor = min(t.rows.len - 1, t.rowCursor + 1)
    # )
    # t.rows[t.rowCursor].onUp = proc(w: ref BaseWidget) =
    #   t.rows[t.rowCursor].focus = false
    #   t.rows[t.rowCursor].render()
    #   t.rowCursor = max(t.rowCursor - 1, 0)
    # t.rows[t.rowCursor].onDown = proc(w: ref BaseWidget) =
    #   t.rows[t.rowCursor].focus = false
    #   t.rows[t.rowCursor].render()
    #   t.rowCursor = min(t.rows.len - 1, t.rowCursor + 1)
    t.render()
    sleep(t.refreshWaitTime)


method wg*(t: ref TextArea): ref BaseWidget = t


# proc value*(t: ref TextArea): string =
#   for r in t.rows:
#     result &= r.value()
#

# proc value*(t: ref TextArea, val: string) =
#   let lineSize = t.x2 - t.x1
#   let rowSize = ceil(val.len / lineSize).toInt
#   if rowSize < t.rows.len:
#     let diffSize = rowSize - t.rows.len
#     for i in 0 ..< diffSize:
#       var t = newInputBox(t.posX, t.posY, t.width, t.height, 
#                           border=false, modeChar=' ',
#                           fgColor=t.fg, bgColor=bgNone)
#       t.rows.add(t)
#   
#   var pos = 0
#   for r in t.rows:
#     r.value(val.substr(pos, lineSize))
#     pos += lineSize
#
#
