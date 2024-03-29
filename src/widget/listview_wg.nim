import illwill, base_wg, options, sequtils, strutils, os

type
  ListRow* = object
    index: int
    text: string
    value*: string
    bgColor: BackgroundColor
    fgColor: ForegroundColor
    visible: bool = true
    selected: bool = false
    align: Alignment

  ListView* = object of BaseWidget
    rows: seq[ref ListRow]
    cursor: int = 0
    rowCursor: int = 0
    colCursor: int = 0
    selectedRow: int = 0
    mode: Mode = Normal
    filteredSize: int = 0
    selectionStyle: SelectionStyle
    onEnter: Option[EnterEventProcedure]


proc newListRow*(index: int, text: string, value: string, align = Center,
                 bgColor = bgNone, fgColor = fgWhite, visible = true,
                 selected = false): ref ListRow =
  result = (ref ListRow)(
    index: index,
    text: text,
    value: value,
    bgColor: bgColor,
    fgColor: fgColor,
    visible: visible,
    selected: selected
  )


proc newListView*(px, py, w, h: int, rows: seq[ref ListRow] = newSeq[ref ListRow](),
                  title = "", border = true, statusbar = true,
                  fgColor = fgWhite, bgColor = bgNone,
                  selectionStyle: SelectionStyle = Highlight,
                  onEnter: Option[EnterEventProcedure] = none(EnterEventProcedure),
                  tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py + 4)): ref ListView =
  let padding = if border: 2 else: 1
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

  result = (ref ListView)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    rows: rows,
    title: title,
    cursor: 0,
    rowCursor: 0,
    size: h - py - style.paddingY1 - style.paddingY2,
    tb: tb,
    style: style,
    statusbar: statusbar,
    statusbarSize: statusbarSize,
    selectionStyle: selectionStyle,
    colCursor: 0,
    onEnter: onEnter
  )


proc `rows=`*(lv: ref ListView, rows: seq[ref ListRow]) =
  for r in 0 ..< rows.len:
    rows[r].index = r
  
  if rows.len > 0:
    rows[0].selected = true
  
  lv.rows = rows


proc vrows(lv: ref ListView): seq[ref ListRow] =
  lv.rows.filter(proc(r: ref ListRow): bool = r.visible)


proc emptyRows(lv: ref ListView, emptyMessage = "No records") =
  lv.tb.write(lv.posX + lv.paddingX1,
                 lv.posY + 3, bgRed, fgWhite,
                 center(emptyMessage, lv.width - lv.paddingX1 - 2), resetStyle)


proc scrollRow(lv: ref ListView, startIndex: int): string =
  var actualStartIndex = max(0, lv.rows[lv.cursor].text.len - (lv.width - (lv.paddingX1 +
      lv.paddingX2)))
  actualStartIndex = min(actualStartIndex, startIndex)
  if actualStartIndex < 0:
    actualStartIndex = 0
  let endIndex = min(actualStartIndex + lv.width - (lv.paddingX1 + lv.paddingX2), lv.rows[
      lv.cursor].text.len)
  return lv.rows[lv.cursor].text[actualStartIndex ..< min(lv.rows[lv.cursor].text.len, endIndex)]


proc renderClearRow(lv: ref ListView, index: int, full = false) =
  if full:
    let totalWidth = lv.width
    lv.tb.fill(lv.posX, lv.posY,
               totalWidth, lv.height, " ")
  else:
    lv.tb.fill(lv.posX + lv.paddingX1, lv.posY + index,
               lv.width - lv.paddingX1, lv.posY + index, " ")


proc renderListRow(lv: ref ListView, row: ref ListRow, index: int) =
  var posX = lv.paddingX1
  var borderX = if lv.border: 1 else: 0
  var text = if row.selected: lv.scrollRow(lv.colCursor)
    else: row.text[0..min(row.text.len - 1, lv.width - lv.posX - posX - borderX)]

  if row.align == Left:
    text = alignLeft(text, min(lv.width, lv.width - lv.posX - posX - borderX))
  elif row.align == Center:
    text = center(text, min(lv.width, lv.width - lv.posX - posX - borderX))
  elif row.align == Right:
    text = align(text, min(lv.width, lv.width - lv.posX - posX - borderX))

  if row.selected and lv.selectionStyle == Highlight:
    lv.tb.write(lv.posX + posX, lv.posY + index, resetStyle,
                lv.bg, row.fgColor, text, resetStyle)
  elif row.selected and lv.selectionStyle == Arrow:
    lv.tb.write(lv.posX + 1, lv.posY + index, resetStyle,
                fgGreen, ">",
                row.fgColor, text, resetStyle)
  elif row.selected and lv.selectionStyle == HighlightArrow:
    lv.tb.write(lv.posX + 1, lv.posY + index, resetStyle,
                fgGreen, ">",
                lv.bg, row.fgColor, text, resetStyle)
  else:
    lv.tb.write(lv.posX + posX, lv.posY + index, resetStyle,
                row.bgColor, row.fgColor, text, resetStyle)



proc renderStatusBar(lv: ref ListView) =
  lv.tb.write(lv.x1, lv.height, fgYellow, "rows: ", $lv.vrows().len,
              " selected: ", $lv.selectedRow, resetStyle)


method render*(lv: ref ListView) =
  lv.renderClearRow(0, true)
  if lv.border:
    lv.renderBorder()
  if lv.title != "":
    lv.renderTitle()
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
      rowEnd = max(lv.rowCursor + 1, lv.filteredSize)

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
    lv.renderStatusBar()
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
      if lv.onEnter.isSome:
        let fn = lv.onEnter.get
        fn(lv.rows[lv.cursor].value)
    of Tab: lv.focus = false
    else: discard
  lv.render()
  sleep(20)


method wg*(lv: ref ListView): ref BaseWidget = lv


proc show*(lv: ref ListView) = lv.render()


proc hide*(lv: ref ListView) = lv.clear()


proc `-`*(lv: ref ListView) = lv.show()


proc `onEnter=`*(lv: ref ListView, cb: EnterEventProcedure) =
  lv.onEnter = some(cb)


proc selected*(lv: ref ListView): ref ListRow =
  return lv.rows[lv.cursor]


## TODO: preprocess rows text
## TODO: event handler
