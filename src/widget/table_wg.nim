import illwill, sequtils, base_wg, os, options, strutils

type
  Alignment* = enum
    Left, Center, Right

  ColumnType* = enum
    Header, Column

  TableColumn* = object
    index: int
    width: int
    height: int
    overflow: bool
    text: string
    widget: Option[BaseWidget]
    key: string
    bgColor: BackgroundColor
    fgColor: ForegroundColor
    align: Alignment = Left
    columnType: ColumnType

  TableRow* = object
    index: int
    width: int
    height: int
    maxColWidth: int
    columns: seq[TableColumn]
    onSpace: Option[SpaceEventProcedure]
    onEnter: Option[EnterEventProcedure]
    bgColor: BackgroundColor
    fgColor: ForegroundColor
    isSelected: bool

  Table = ref object of BaseWidget
    headers: Option[TableRow]
    rows: seq[TableRow]
    size: int
    title: string
    cursor: int = 0
    rowCursor: int = 0


proc newTableColumn*(width, height: int, text, key: string, index = 0, overflow: bool = false,
                     widget: Option[BaseWidget] = none(BaseWidget),
                     bgColor = bgNone, fgColor = fgWhite,
                     align = Left, columnType = Column): TableColumn =
  var tc = TableColumn(
    index: index,
    width: max(width, text.len),
    height: height,
    overflow: overflow,
    text: text,
    key: key,
    widget: widget,
    bgColor: bgColor,
    fgColor: fgColor,
    align: align,
    columnType: columnType
  )
  return tc



proc newTableRow*(width, height: int, columns: var seq[TableColumn], index = 0,
                 onSpace: Option[SpaceEventProcedure] = none(
                     SpaceEventProcedure),
                 onEnter: Option[EnterEventProcedure] = none(
                     EnterEventProcedure),
                 bgColor = bgNone, fgColor = fgWhite,
                     isSelected = false): TableRow =
  var maxColWidth = 0
  for i in 0..<columns.len:
    columns[i].index = i
    maxColWidth = max(columns[i].width, maxColWidth)

  var tr = TableRow(
    index: index,
    width: width,
    height: height,
    columns: columns,
    onSpace: onSpace,
    onEnter: onEnter,
    bgColor: bgColor,
    fgColor: fgColor,
    isSelected: isSelected,
    maxColWidth: maxColWidth
  )
  return tr


proc newTable*(w, h, px, py: int, rows: var seq[TableRow], headers: Option[TableRow] = none(TableRow), 
               title: string = "", cursor = 0, rowCursor = 0,
               tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py),
               bordered = true): Table =
  for i in 0..<rows.len:
    rows[i].index = i
  var table = Table(
    width: w,
    height: h,
    posX: px,
    posY: py,
    headers: headers,
    rows: rows,
    title: title,
    cursor: cursor,
    rowCursor: rowCursor,
    size: h - py,
    tb: tb,
    bordered: bordered,
    paddingX: if bordered: 2 else: 1
  )
  if headers.isSome: 
    table.size -= 1
  return table


proc renderTableHeader(table: var Table): int =
  result = 1
  let borderX = if table.bordered: 1 else: 2
  if table.headers.isSome:
    var posX = table.paddingX
    for col in table.headers.get.columns:
      table.tb.write(table.posX + posX, table.posY + result, bgBlue, col.fgColor, 
                     alignLeft(col.text, min(col.width, table.width - table.posX - posX - borderX)), 
                     resetStyle)
      posX = posX + col.width + 1
    result += 1


proc renderClearRow(table: var Table, index: int) =
  table.tb.fill(table.posX + table.paddingX, table.posY + index,
        table.width - table.paddingX, table.height, " ")


proc calColWidth(table: var Table, cindex: int, defaultWidth: int): int =
  if table.headers.isSome:
    result = table.headers.get.columns[cindex].width
  else:
    result = defaultWidth


proc renderTableRow(table: var Table, row: TableRow, index: int) =
  var posX = table.paddingX
  var borderX = if table.bordered: 1 else: 0
  for i in 0..<row.columns.len:
    var text = row.columns[i].text
    var width = table.calColWidth(i, row.columns[i].width)
    if row.columns[i].align == Left:
      text = alignLeft(text, min(width, table.width - table.posX - posX - i - borderX))
    elif row.columns[i].align == Center:
      text = center(text, min(width, table.width - table.posX - posX - i - borderX))
    elif row.columns[i].align == Right:
      text = align(text, min(width, table.width - table.posX - posX - i - borderX))
    table.tb.write(table.posX + posX + i, table.posY + index, row.columns[
        i].bgColor, row.columns[i].fgColor, text, resetStyle)
    posX += width


proc render*(table: var Table): void =
  if table.bordered:
    table.tb.drawRect(table.width, table.height + table.paddingX,
                      table.posX, table.posY, doubleStyle = table.focus)
  if table.title != "":
    table.tb.write(table.posX + table.paddingX, table.posY, table.title)

  let rowStart = table.rowCursor
  let rowEnd = if table.rowCursor + table.size >
      table.rows.len: table.rows.len - 1
    else: table.rowCursor + table.size - 1
  var index = table.renderTableHeader()

  for row in table.rows[rowStart..min(rowEnd, table.rows.len - 1)]:
    # table.tb.fill(table.posX + table.width - table.paddingX, table.posY + index,
    #     table.width - table.paddingX, table.height, " ")
    table.renderClearRow(index)
    # var colWidth = table.paddingX
    # for i in 0..<row.columns.len:
    #   var text = row.columns[i].text
    #   table.tb.write(table.posX + colWidth + i, table.posY + index, row.columns[
    #       i].bgColor, row.columns[i].fgColor, text, resetStyle)
    #   if table.headers.isSome:
    #     colWidth += table.headers.get.columns[i].width
    #   else:
    #     colWidth += text.len
    #
    table.renderTableRow(row, index)
    index += 1
  table.tb.write(table.posX + table.paddingX, table.posY + table.size +
      table.paddingX + 1, $rowStart, "...", $rowEnd)
  table.tb.display()


method onControl*(table: var Table): void =
  table.focus = true
  while table.focus:
    var key = getKey()
    case key
    of Key.None: table.render()
    of Key.Up:
      if table.rowCursor == 0:
        table.rowCursor = 0
      else:
        table.rowCursor = table.rowCursor - 1
    of Key.Down:
      if table.rowCursor + table.size > table.rows.len:
        table.rowCursor = table.rowCursor
      else:
        table.rowCursor = table.rowCursor + 1
    of Key.Escape, Key.Tab: table.focus = false
    else: discard
  table.render()
  sleep(20)


proc show*(table: var Table) = table.render()


proc `-`*(table: var Table) = table.show()


proc addRow*(table: var Table, tablerow: var TableRow): void =
  return


proc removeRow*(table: var Table, index: int): void =
  return



