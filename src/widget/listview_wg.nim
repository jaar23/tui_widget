import illwill, base_wg, sequtils, strutils, os, tables, display_wg
import threading/channels

type
  ListRowObj* = object
    index: int
    text: string
    value*: string
    bgColor: BackgroundColor
    fgColor: ForegroundColor
    visible: bool = true
    selected: bool = false
    align: Alignment

  ListRow* = ref ListRowObj

  ListViewObj* = object of BaseWidget
    rows: seq[ListRow]
    selectedRow: int = 0
    mode: Mode = Normal
    filteredSize: int = 0
    selectionStyle*: SelectionStyle
    events*: Table[string, EventFn[ListView]]
    keyEvents*: Table[Key, EventFn[ListView]]

  ListView* = ref ListViewObj


const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.None, Key.Up,
                          Key.Down, Key.PageUp, Key.PageDown,
                          Key.Left, Key.Right}

proc help(lv: ListView, args: varargs[string]): void

proc on*(lv: ListView, key: Key, fn: EventFn[ListView]) {.raises: [EventKeyError]}

proc newListRow*(index: int, text: string, value: string, align = Center,
                 bgColor = bgNone, fgColor = fgWhite, visible = true,
                 selected = false): ListRow =
  result = ListRow(
    index: index,
    text: text,
    value: value,
    bgColor: bgColor,
    fgColor: fgColor,
    visible: visible,
    selected: selected
  )


proc newListView*(px, py, w, h: int, id = "", 
                  title = "", border = true, statusbar = true,
                  statusbarText = "[?]", enableHelp=false,
                  rows: seq[ListRow] = newSeq[ListRow](),
                  bgColor = bgNone, fgColor = fgWhite,
                  selectionStyle: SelectionStyle = Highlight,
                  tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py + 4)): ListView =
  let padding = if border: 1 else: 0
  let statusbarSize = if statusbar: 1 else: 0
  let style = WidgetStyle(
    paddingX1: padding,
    paddingX2: padding,
    paddingY1: padding,
    paddingY2: padding,
    border: border,
    fgColor: fgColor,
    bgColor: if @[Highlight, HighlightArrow].contains(selectionStyle) and bgColor !=
        bgNone: bgColor else: bgBlue
  )

  for r in 0..<rows.len:
    rows[r].index = r

  if rows.len > 0:
    rows[0].selected = true

  result = ListView(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    rows: rows,
    title: title,
    cursor: 0,
    rowCursor: 0,
    size: h - py - style.paddingY2 - style.paddingY1 - statusbarSize,
    tb: tb,
    style: style,
    statusbar: statusbar,
    enableHelp: enableHelp,
    selectionStyle: selectionStyle,
    colCursor: 0,
    statusbarText: statusbarText,
    statusbarSize: statusbarText.len(),
    events: initTable[string, EventFn[ListView]](),
    keyEvents: initTable[Key, EventFn[ListView]]()
  )
  result.channel = newChan[WidgetBgEvent]()
  if enableHelp:
    result.on(Key.QuestionMark, help)
  result.keepOriginalSize()


proc newListView*(px, py: int, w, h: WidgetSize, id = "", 
                  title = "", border = true, statusbar = true,
                  statusbarText = "[?]", enableHelp=false,
                  rows: seq[ListRow] = newSeq[ListRow](),
                  bgColor = bgNone, fgColor = fgWhite,
                  selectionStyle: SelectionStyle = Highlight,
                  tb = newTerminalBuffer(w.toInt + 2, h.toInt + py + 4)): ListView =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newListView(px, py, width, height, id, title, border, statusbar,
                    statusbarText, enableHelp, rows,bgColor, fgColor,
                    selectionStyle, tb)


proc newListView*(id: string): ListView =
  var lv = ListView(
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
    selectionStyle: SelectionStyle.Arrow,
    events: initTable[string, EventFn[ListView]](),
    keyEvents: initTable[Key, EventFn[ListView]]()
  )
  lv.channel = newChan[WidgetBgEvent]()
  lv.on(Key.QuestionMark, help)
  return lv


proc vrows(lv: ListView): seq[ListRow] =
  lv.rows.filter(proc(r: ListRow): bool = r.visible)


proc emptyRows(lv: ListView, emptyMessage = "No records",
                bgColor = bgRed, fgColor = fgWhite) =
  if lv.events.hasKey("empty"):
    lv.call("empty", "")
  else:  
    lv.tb.write(lv.posX + lv.paddingX1,
                 lv.posY + 3, bgColor, fgColor,
                 center(emptyMessage, lv.width - lv.paddingX1 - 2), resetStyle)


proc scrollRow(lv: ListView, startIndex: int): string =
  let selected = lv.selectedRow
  var extraPadd = if lv.selectionStyle == Arrow or lv.selectionStyle == HighlightArrow: 1 else: 0
  #if lv.border: extraPadd += 2
  #echo lv.rows[selected].text.len
  # testing
  # previously using lv.cursor
  var actualStartIndex = max(0, lv.rows[selected].text.len - (lv.width - (lv.paddingX1 +
      lv.paddingX2)))
  actualStartIndex = min(actualStartIndex, startIndex)
  if actualStartIndex < 0:
    actualStartIndex = 0
  # previously using lv.cursor
  let endIndex = min(actualStartIndex + lv.width - (lv.paddingX1 + lv.paddingX2), lv.rows[
      selected].text.len)
  # previously using lv.cursor
  return lv.rows[selected].text[actualStartIndex ..< min(lv.rows[selected].text.len, endIndex - extraPadd)]


proc renderClearRow(lv: ListView, index: int, full = false) =
  if full:
    let totalWidth = lv.width
    lv.tb.fill(lv.posX, lv.posY,
               totalWidth, lv.height, " ")
  else:
    lv.tb.fill(lv.posX + lv.paddingX1, lv.posY + index,
               lv.width - lv.paddingX1, lv.posY + index, " ")


proc renderListRow(lv: ListView, row: ListRow, index: int) =
  var posX = if lv.selectionStyle == Arrow or lv.selectionStyle == HighlightArrow: lv.paddingX1 + 1 else: lv.paddingX1
  var borderX = if lv.border: 0 else: 0
  # if lv.rows.len <= lv.selectedRow: 
  #   lv.selectedRow = 0
  #   lv.cursor = 0
  var text = ""
  if row.selected and (lv.x2 - lv.x1) > row.text.len:
    text = row.text
  elif row.selected and (lv.x2 - lv.x1) < row.text.len:
    text = lv.scrollRow(lv.colCursor) 
  else: 
    text = row.text[0..min(row.text.len - 1, lv.width - lv.x1 - posX - borderX)]

  if row.align == Left:
    text = alignLeft(text, min(lv.width, lv.width - lv.posX - posX - borderX))
  elif row.align == Center:
    text = center(text, min(lv.width, lv.width - lv.posX - posX - borderX))
  elif row.align == Right:
    text = align(text, min(lv.width, lv.width - lv.posX - posX - borderX))

  if row.selected and lv.selectionStyle == Highlight:
    lv.tb.write(lv.posX + posX, lv.posY + index, resetStyle,
                row.bgColor, row.fgColor, text, resetStyle)
  elif row.selected and lv.selectionStyle == Arrow:
    lv.tb.write(lv.posX + 1, lv.posY + index,
                fgGreen, ">",
                row.fgColor, text, resetStyle)
  elif row.selected and lv.selectionStyle == HighlightArrow:
    lv.tb.write(lv.posX + 1, lv.posY + index,
                fgGreen, ">",
                row.bgColor, row.fgColor, text, resetStyle)
  else:
    lv.tb.write(lv.posX + posX, lv.posY + index, resetStyle,
                bgNone, row.fgColor, text, resetStyle)


proc help(lv: ListView, args: varargs[string]) = 
  let wsize = ((lv.width - lv.posX).toFloat * 0.3).toInt()
  let hsize = ((lv.height - lv.posY).toFloat * 0.3).toInt()
  var display = newDisplay(lv.x2 - wsize, lv.y2 - hsize, 
                          lv.x2, lv.y2, title="help",
                          bgColor=bgWhite, fgColor=fgBlack,
                          tb=lv.tb, statusbar=false,
                          enableHelp=false)
  var helpText: string
  if lv.helpText == "":
    helpText = " [Enter] to select\n" &
               " [?]     for help\n" &
               " [Tab]   to go next widget\n" &
               " [Esc]   to exit this window"
  display.text = helpText
  display.illwillInit = true
  display.onControl()
  display.clear()


proc renderStatusBar(lv: ListView, text: string = "") =
  if lv.statusbar:
    if lv.events.hasKey("statusbar"):
      lv.call("statusbar")
    else: 
      let statusText = if text.len == 0: lv.statusbarText else: text
      lv.statusbarSize = statusText.len()
      lv.renderCleanRect(lv.x2 - lv.statusbarSize, lv.height, lv.statusbarSize, lv.height)
      # mode
      lv.tb.write(lv.x1, lv.height, bgWhite, fgBlack, $lv.mode, resetStyle)
      if lv.enableHelp:
        let q = "[?]"
        lv.tb.write(lv.x2 - q.len, lv.height, bgWhite, fgBlack, q, resetStyle)


method resize*(lv: ListView) =
  let statusbarSize = if lv.statusbar: 1 else: 0
  lv.size = lv.height - lv.posY - lv.paddingY2 - lv.paddingY1 - statusbarSize


method render*(lv: ListView) =
  if not lv.illwillInit: return
  lv.renderClearRow(0, true)
  lv.renderBorder()
  lv.renderTitle()
  if lv.rows.len == 0: return
  var index = 1
  let rows = lv.vrows()
  if rows.len > 0:
    lv.filteredSize = min(lv.size, rows.len)
    ##########################################
    # highlight at bottom while cursor moving
    var rowStart = max(0, lv.rowCursor)
    var rowEnd = rowStart + lv.filteredSize
    if rowEnd > lv.filteredSize:
      rowStart = max(0, lv.rowCursor - lv.filteredSize)
      rowEnd = max(lv.rowCursor + 1 , lv.filteredSize)

    ##########################################
    # highlight at top while cursor moving
    #
    #let rowStart = lv.rowCursor
    #let rowEnd = if lv.rowCursor + lv.filteredSize > rows.len - 1: rows.len - 1
    #  else: lv.rowCursor + lv.filteredSize
    for row in rows[rowStart..min(rowEnd, rows.len - 1)]:
      lv.renderClearRow(index)
      lv.renderListRow(row, index)
      index += 1
    if lv.mode == Filter:
      lv.renderStatusBar("Mode: " & $lv.mode & "|" & $lv.cursor)
    else:
      #lv.renderStatusBar($lv.cursor & "|" & $lv.selectedRow)
      lv.renderStatusBar()
    lv.tb.display()
  else:
    lv.emptyRows()
    lv.tb.display()


proc prevSelection(lv: ListView) =
  let rows = lv.vrows()
  if lv.cursor == 0:
    lv.cursor = 0
  else:
    lv.cursor -= 1
  if rows.len > 0:
    let index = rows[lv.cursor].index
    for r in 0..<lv.rows.len:
      if lv.rows[r].index == index:
        lv.rows[r].selected = true
        lv.selectedRow = lv.rows[r].index
      else:
        lv.rows[r].selected = false


proc nextSelection(lv: ListView) =
  let rows = lv.vrows()
  if lv.cursor >= rows.len - 1:
    lv.cursor = rows.len - 1
  else:
    lv.cursor += 1
  if rows.len > 0:
    let index = rows[lv.cursor].index
    for r in 0..<lv.rows.len:
      if lv.rows[r].index == index:
        lv.rows[r].selected = true
        lv.selectedRow = lv.rows[r].index
      else:
        lv.rows[r].selected = false


proc selected*(lv: ListView): ListRow =
  # previously using lv.cursor
  return lv.rows[lv.selectedRow]


proc `selectedRow=`*(lv: ListView, i: int) =
  lv.selectedRow = i


proc resetCursor*(lv: ListView) =
  lv.selectedRow = 0 
  lv.rowCursor = 0
  lv.colCursor = 0
  lv.cursor = 0
  for r in 0 ..< lv.rows.len:
    if r == 0:
      lv.rows[r].selected = true
    else:
      lv.rows[r].selected = false
      #lv.rows[r].visible = true


proc on*(lv: ListView, event: string, fn: EventFn[ListView]) =
  lv.events[event] = fn


proc on*(lv: ListView, key: Key, fn: EventFn[ListView]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  lv.keyEvents[key] = fn
    

proc call*(lv: ListView, event: string, args: varargs[string]) =
  let fn = lv.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(lv, args)


proc call(lv: ListView, key: Key, args: varargs[string]) =
  let fn = lv.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(lv, args)


method poll*(lv: ListView) =
  var widgetEv: WidgetBgEvent
  if lv.channel.tryRecv(widgetEv):
    lv.call(widgetEv.event, widgetEv.args)
    lv.render()


method onUpdate*(lv: ListView, key: Key) =
  case key
  of Key.None: lv.render()
  of Key.Up:
    if lv.rowCursor == 0:
      lv.rowCursor = 0
    else:
      lv.rowCursor = lv.rowCursor - 1
    lv.prevSelection()
    lv.colCursor = 0
  of Key.Down:
    let rowSize = if lv.mode == Filter: lv.vrows().len else: lv.rows.len
    if lv.rowCursor >= rowSize - 1:
      lv.rowCursor = rowSize - 1
    else:
      lv.rowCursor += 1
    lv.nextSelection()
    lv.colCursor = 0
  of Key.Right:
    lv.colCursor = min(lv.colCursor + 1, lv.rows[lv.cursor].text.len - (lv.width - (lv.paddingX1 +
        lv.paddingX2)))
  of Key.Left:
    lv.colCursor = max(lv.colCursor - 1, 0)
  of Key.Enter:
    lv.call("enter", lv.selected.value)
  of Tab: lv.focus = false
  else:
    if key in forbiddenKeyBind: discard
    elif lv.keyEvents.hasKey(key):
      lv.call(key, lv.selected.value)
  lv.render()
  sleep(lv.rpms)


method onControl*(lv: ListView): void =
  if lv.visibility == false: 
    lv.cursor = 0
    lv.rowCursor = 0
    lv.colCursor = 0
    return
  
  # catch changes from ref component
  if lv.rows.len != lv.vrows().len:
    lv.mode = Filter

  lv.focus = true
  while lv.focus:
    var key = getKeyWithTimeout(lv.rpms)
    lv.onUpdate(key)  


method wg*(lv: ListView): ref BaseWidget = lv


proc `onEnter=`*(lv: ListView, enterEv: EventFn[ListView]) =
  lv.on("enter", enterEv)


proc onEnter*(lv: ListView, enterEv: EventFn[ListView]) =
  lv.on("enter", enterEv)


proc rows*(lv: ListView): seq[ListRow] =
  return lv.rows


proc `rows=`*(lv: ListView, rows: seq[ListRow]) =
  for r in 0 ..< rows.len:
    rows[r].index = r
  
  if rows.len > 0:
    rows[0].selected = true
  
  lv.rows = rows


# proc `enableHelp=`*(lv: ListView, enable: bool) =
#   lv.enableHelp = enable
#   if lv.enableHelp:
#     lv.on(Key.QuestionMark, help)
#   else:
#     lv.keyEvents.del(Key.QuestionMark)
#
# ListRow attributes
#
proc index*(lr: ListRow): int = lr.index

proc text*(lr: ListRow): string = lr.text

proc value*(lr: ListRow): string = lr.value

proc bgColor*(lr: ListRow): BackgroundColor = lr.bgColor

proc fgColor*(lr: ListRow): ForegroundColor = lr.fgColor  

proc visible*(lr: ListRow): bool = lr.visible

proc selected*(lr: ListRow): bool = lr.selected

proc align*(lr: ListRow): Alignment = lr.align

proc `text=`*(lr: ListRow, text: string) = 
  lr.text = text

proc `value=`*(lr: ListRow, value: string) =
  lr.value = value

proc `bgColor=`*(lr: ListRow, bgColor: BackgroundColor)= 
  lr.bgColor = bgColor

proc `fgColor=`*(lr: ListRow, fgColor: ForegroundColor) = 
  lr.fgColor = fgColor

proc `visible=`*(lr: ListRow, visible: bool) = 
  lr.visible = visible

proc `selected=`*(lr: ListRow, selected: bool) =
  lr.selected = selected

proc `align=`*(lr: ListRow, align: Alignment) = 
  lr.align = align




