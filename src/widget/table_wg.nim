import illwill, sequtils, base_wg, os, options, strutils, parsecsv
from std/streams import newFileStream

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
    data: string = ""
    visible: bool = true

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
    visible: bool = true
    isSelected: bool

  Table = ref object of BaseWidget
    headers: Option[TableRow]
    rows: seq[TableRow]
    size: int
    title: string
    cursor: int = 0
    rowCursor: int = 0
    colCursor: int = 0


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
    columnType: columnType,
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
  var seqColWidth = ($rows.len).len
  for i in 0..<rows.len:
    var seqCol = newTableColumn(seqColWidth, 1, text = $(i + 1), key = $i, index = i)
    rows[i].columns.insert(seqCol, 0)
    rows[i].index = i
  var table = Table(
    width: min(w + seqColWidth, w),
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
    paddingX: if bordered: 2 else: 1,
    colCursor: 0
  )
  if headers.isSome: 
    table.size -= 1
    var seqCol = newTableColumn(seqColWidth, 1, text = alignLeft("i", seqColWidth), key = "", index = 0)
    table.headers.get.columns.insert(seqCol, 0)
  return table



proc rowMaxWidth(table: var Table): int =
  result = 0
  if table.headers.isSome:
    for col in table.headers.get.columns:
      result += col.width
  else:
    for col in table.rows[table.cursor].columns:
      result += col.width


proc dtmColumnToDisplay(table: var Table) =
  var posX = table.paddingX
  for i in table.colCursor..<table.headers.get.columns.len:
    #if posX + table.headers.get.columns[i].width < table.width:
    if posX < table.width:
      table.headers.get.columns[i].visible = true
      posX += table.headers.get.columns[i].width
    else:
      table.headers.get.columns[i].visible = false
  for i in 0..<table.colCursor:
    table.headers.get.columns[i].visible = false


proc filter(table: var Table, filterStr: string) =
  for r in 0..<table.rows.len:
    for col in table.rows[r].columns:
      if col.text.contains(filterStr): 
        table.rows[r].visible = true
        continue
      else:
        table.rows[r].visible = false


proc resetFilter(table: var Table) =
  for r in 0..<table.rows.len:
    table.rows[r].visible = true


proc renderClearRow(table: var Table, index: int, full = false) =
  if full:
    var totalWidth = table.rowMaxWidth()
    table.tb.fill(table.posX + table.paddingX, table.posY + index,
                  totalWidth, table.height, " ")
  else:
    table.tb.fill(table.posX + table.paddingX, table.posY + index,
                  table.width - table.paddingX, table.height, " ")


proc renderTableHeader(table: var Table): int =
  result = 1
  table.renderClearRow(result, true)
  let borderX = if table.bordered: 1 else: 2
  if table.headers.isSome:
    var posX = table.paddingX
    for i in table.colCursor..<table.headers.get.columns.len:
      if table.headers.get.columns[i].visible and posX < table.width:
        table.tb.write(table.posX + posX, table.posY + result, bgBlue, table.headers.get.columns[i].fgColor, 
                       alignLeft(table.headers.get.columns[i].text, min(table.headers.get.columns[i].width, table.width - table.posX - posX - borderX)), 
                       resetStyle)
        posX = posX + table.headers.get.columns[i].width + 1
    result += 1


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
    if table.headers.get.columns[i].visible and posX < table.width:
      var width = table.calColWidth(i, row.columns[i].width)
      if row.columns[i].align == Left:
        text = alignLeft(text, min(width, table.width - table.posX - posX - borderX))
      elif row.columns[i].align == Center:
        text = center(text, min(width, table.width - table.posX - posX - borderX))
      elif row.columns[i].align == Right:
        text = align(text, min(width, table.width - table.posX - posX - borderX))
      var bgSelected = row.columns[i].bgColor
      if row.index == table.cursor:
        bgSelected = bgGreen
      table.tb.write(table.posX + posX, table.posY + index, 
                     bgSelected, row.columns[i].fgColor, text, resetStyle)
      posX += width + 1




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
    table.renderClearRow(index)
    table.renderTableRow(row, index)
    index += 1
  table.tb.write(table.posX + table.paddingX, table.posY + table.size +
      table.paddingY + 2, $rowStart, "...", $rowEnd, " selected: ", $table.cursor, " col: " & $table.colCursor)
  table.tb.drawVertLine(table.width, table.height, table.posY + 1, doubleStyle = true)
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
      if table.cursor == 0:
        table.cursor = 0
      else:
        table.cursor -= 1
    of Key.Down:
      if table.rowCursor + table.size > table.rows.len:
        table.rowCursor = table.rowCursor
      else:
        table.rowCursor = table.rowCursor + 1
      if table.cursor >= table.rows.len - 1:
        table.cursor = table.rows.len - 1
      else:
        table.cursor += 1
    of Key.Right: 
      if table.colCursor == table.headers.get.columns.len - 1:
        table.colCursor = table.headers.get.columns.len - 1
      else:
        table.colCursor += 1
      table.dtmColumnToDisplay()
    of Key.Left:
      if table.colCursor == 0:
        table.colCursor = 0
      else:
        table.colCursor -= 1
      table.dtmColumnToDisplay()
    of Key.Slash:
      discard
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


proc selected*(table: var Table): TableRow =
  return table.rows[table.cursor]


proc loadFromCsv*(table: var Table, filepath: string, withHeader = false): void =
  try:
    if not filepath.endsWith(".csv"):
      raise newException(IOError, "Unable to load non csv file")
    table.rows = newSeq[TableRow]()
    var stream = newFileStream(filepath, fmRead)
    if stream == nil:
      raise newException(IOError, "Unable to open file")
    var csvparser: CsvParser
    open(csvparser, stream, filepath)
    var rindex = 0
    while readRow(csvparser):
      var row = newSeq[TableColumn]()
      if rindex == 0:
        var headerWidth = 0
        for val in items(csvparser.row):
          var column = newTableColumn(val.len + 1, 1, val, $rindex, rindex, columnType=Header)
          row.add(column)
          headerWidth += val.len + 1 
        var header = newTableRow(headerWidth, 1, row)
        table.headers = some(header)
      else:
        var rowWidth = 0
        for val in items(csvparser.row):
          var col = newTableColumn(val.len, 1, val, $rindex, rindex, columnType=Column)
          row.add(col)
          rowWidth += val.len
        var tableRow = newTableRow(rowWidth, 1, row)
        table.rows.add(tableRow) 
  except:
    echo "failed to open file"

