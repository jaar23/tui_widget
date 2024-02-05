import illwill, base_wg, options, sequtils, strutils, os

type
  ListRow* = object
    index: int
    text: string
    value*: string
    onSpace: Option[SpaceEventProcedure]
    onEnter: Option[EnterEventProcedure]
    bgColor: BackgroundColor
    fgColor: ForegroundColor
    visible: bool = true
    selected: bool = false
    align: Alignment

  ListView* = object of BaseWidget
    title: string
    rows: seq[ref ListRow]
    size: int
    cursor: int = 0
    rowCursor: int = 0
    colCursor: int = 0
    selectedRow: int = 0
    mode: Mode = Normal
    filteredSize: int = 0


proc newListRow*(index: int, text: string, value: string, align=Center,
                    onSpace: Option[SpaceEventProcedure] = none(SpaceEventProcedure),
                    onEnter: Option[EnterEventProcedure] = none(EnterEventProcedure),
                    bgColor = bgNone, fgColor = fgWhite, visible = true,
                    selected = false): ref ListRow =
  result = (ref ListRow)(
    index: index,
    text: text,
    value: value,
    onSpace: onSpace,
    onEnter: onEnter,
    bgColor: bgColor,
    fgColor: fgColor,
    visible: visible,
    selected: selected
  )


proc newListView*(w, h, px, py: int, rows: var seq[ref ListRow],
                     title: string = "", bordered = true,
                     tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py + 4)): ref ListView =
  for r in 0..<rows.len:
    rows[r].index = r
  rows[0].selected = true
  result = (ref ListView)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    rows: rows,
    title: title,
    cursor: 0,
    rowCursor: 0,
    size: h - py - 1,
    tb: tb,
    bordered: bordered,
    paddingX: if bordered: 2 else: 1,
    paddingY: if bordered: 2 else: 1,
    colCursor: 0
  )


proc vrows(lv: ref ListView): seq[ref ListRow] = 
  lv.rows.filter(proc(r: ref ListRow): bool = r.visible)


proc emptyRows(lv: ref ListView, emptyMessage = "No records") =
  lv.tb.write(lv.posX + lv.paddingX,
                 lv.posY + 3, bgRed, fgWhite, 
                 center(emptyMessage, lv.width - lv.paddingX - 2), resetStyle)


proc renderClearRow(lv: ref ListView, index: int, full = false) =
  if full:
    let totalWidth = lv.width
    lv.tb.fill(lv.posX, lv.posY,
                  totalWidth, lv.height + lv.paddingY + 3, " ")
  else:
    lv.tb.fill(lv.posX + lv.paddingX, lv.posY + index,
               lv.width - lv.paddingX, lv.posY + index, " ")


proc renderListRow(lv: ref ListView, row: ref ListRow, index: int) =
  var posX = lv.paddingX
  var borderX = if lv.bordered: 1 else: 0
  var text = row.text
  if row.align == Left:
    text = alignLeft(text, min(lv.width, lv.width - lv.posX - posX - borderX))
  elif row.align == Center:
    text = center(text, min(lv.width, lv.width - lv.posX - posX - borderX))
  elif row.align == Right:
    text = align(text, min(lv.width, lv.width - lv.posX - posX - borderX))
  var bgSelected = row.bgColor
  if row.selected:
    bgSelected = bgGreen
  lv.tb.write(lv.posX + posX, lv.posY + index, resetStyle,
                 bgSelected, row.fgColor, text, resetStyle)


proc renderStatusBar(lv: ref ListView) =
  lv.tb.write(lv.posX + lv.paddingX, lv.height + lv.paddingY, 
                 fgYellow, "rows: ", $lv.vrows().len , " selected: ", $lv.selectedRow, 
                 resetStyle)


proc render*(lv: ref ListView) =
  lv.renderClearRow(0, true)
  if lv.bordered:
    lv.tb.drawRect(lv.width, lv.height + lv.paddingY,
                   lv.posX, lv.posY, doubleStyle = lv.focus)
  if lv.title != "":
    lv.tb.write(lv.posX + lv.paddingX, lv.posY, lv.title)
  var index = 1
  let rows = lv.vrows()
  if rows.len > 0:
    lv.filteredSize = min(lv.size, rows.len)
    let rowStart = lv.rowCursor
    let rowEnd = if lv.rowCursor + lv.filteredSize > rows.len - 1: rows.len - 1
      else: lv.rowCursor + lv.filteredSize
    #echo "\n\n\n\n\n\n" & $lv.rowCursor & " " & $rowStart & "-" & $rowEnd
    for row in rows[rowStart..min(rowEnd, rows.len - 1)]:
      lv.renderClearRow(index)
      lv.renderListRow(row, index)
      index += 1
    lv.renderStatusBar()
    #lv.tb.drawVertLine(lv.width, lv.height, lv.posY + 1, doubleStyle = true)
    lv.tb.display()
  else:
    lv.emptyRows()
    lv.tb.display()


proc prevSelection(lv: ref ListView) =
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


proc nextSelection(lv: ref ListView) =
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


method onControl*(lv: ref ListView): void =
  lv.focus = true
  while lv.focus:
    var key = getKey()
    case key
    of Key.None: lv.render()
    of Key.Up:
      if lv.rowCursor == 0:
        lv.rowCursor = 0
      else:
        lv.rowCursor = lv.rowCursor - 1
      lv.prevSelection()
    of Key.Down:
      let rowSize = if lv.mode == Filter: lv.vrows().len else: lv.rows.len
      if lv.rowCursor >= rowSize - 1:
        lv.rowCursor = rowSize - 1
      else:
        lv.rowCursor += 1
      lv.nextSelection() 
    of Tab: lv.focus = false
    else: discard
  lv.render()
  sleep(20)
   

proc show*(lv: ref ListView) = lv.render()


proc `-`*(lv: ref ListView) = lv.show()


proc selected*(lv: ref ListView): ref ListRow =
  return lv.rows[lv.cursor]


