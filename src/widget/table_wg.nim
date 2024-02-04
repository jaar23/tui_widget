import illwill, sequtils, base_wg, os, options, strutils, parsecsv, input_box_wg
from std/streams import newFileStream

type
  Alignment* = enum
    Left, Center, Right

  ColumnType* = enum
    Header, Column

  Mode = enum
    Normal, Filter

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
    selected: bool

  Table = ref object of BaseWidget
    headers: Option[TableRow]
    rows: seq[TableRow]
    size: int
    title: string
    cursor: int = 0
    rowCursor: int = 0
    colCursor: int = 0
    mode: Mode = Normal
    filteredSize: int = 0
    selectedRow: int = 0


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
                     selected = false): TableRow =
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
    selected: selected,
    maxColWidth: maxColWidth
  )
  return tr


proc newTable*(w, h, px, py: int, rows: var seq[TableRow], headers: Option[TableRow] = none(TableRow), 
               title: string = "", cursor = 0, rowCursor = 0,
               tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py + 4),
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
    table.height += table.paddingY
  if table.rows.len > 0:
    table.rows[0].selected = true
  return table



proc rowMaxWidth(table: var Table): int =
  result = 0
  if table.headers.isSome:
    for col in table.headers.get.columns:
      result += col.width
  else:
    for col in table.rows[table.cursor].columns:
      result += col.width


proc vrows(table: var Table): seq[TableRow] = table.rows.filter(proc(r: TableRow): bool = r.visible)


proc dtmColumnToDisplay(table: var Table) =
  var posX = table.paddingX
  for i in table.colCursor..<table.headers.get.columns.len:
    if posX + table.headers.get.columns[i].width < table.width:
    #if posX < table.width:
      table.headers.get.columns[i].visible = true
      posX += table.headers.get.columns[i].width
    else:
      table.headers.get.columns[i].visible = false
  for i in 0..<table.colCursor:
    table.headers.get.columns[i].visible = false


proc emptyRows*(table: var Table, emptyMessage = "No records") =
  table.tb.write(table.posX + table.paddingX,
                 table.posY + 3, bgRed, fgWhite, center(emptyMessage, table.width - table.paddingX - 2), resetStyle)


proc renderClearRow(table: var Table, index: int, full = false) =
  if full:
    let totalWidth = table.rowMaxWidth()
    table.tb.fill(table.posX, table.posY,
                  totalWidth, table.height + table.paddingY + 3, " ")
  else:
    table.tb.fill(table.posX + table.paddingX, table.posY + index,
                  table.width - table.paddingX, table.posY + index, " ")


proc renderTableHeader(table: var Table): int =
  result = 1
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
    if row.visible and table.headers.get.columns[i].visible and posX < table.width:
      var width = table.calColWidth(i, row.columns[i].width)
      if row.columns[i].align == Left:
        text = alignLeft(text, min(width, table.width - table.posX - posX - borderX))
      elif row.columns[i].align == Center:
        text = center(text, min(width, table.width - table.posX - posX - borderX))
      elif row.columns[i].align == Right:
        text = align(text, min(width, table.width - table.posX - posX - borderX))
      var bgSelected = row.columns[i].bgColor
      if row.selected:
        bgSelected = bgGreen
      #else: bgSelected = bgRed
      table.tb.write(table.posX + posX, table.posY + index, 
                     bgSelected, row.columns[i].fgColor, text, resetStyle)
      posX += width + 1


proc renderStatusBar(table: var Table) =
  table.tb.write(table.posX + table.paddingX, table.height + 1 + table.paddingY, 
                 fgYellow, "rows: ", $table.vrows().len , " selected: ", $table.selectedRow, 
                 resetStyle)


proc render*(table: var Table): void =
  table.renderClearRow(0, true)
  if table.bordered:
    table.tb.drawRect(table.width, table.height + table.paddingY + 1,
                      table.posX, table.posY, doubleStyle = table.focus)
  if table.title != "":
    table.tb.write(table.posX + table.paddingX, table.posY, table.title)
  var index = table.renderTableHeader()
  let rows = table.vrows()
  if rows.len > 0:
    table.filteredSize = min(table.size, rows.len)
    let rowStart = table.rowCursor
    let rowEnd = if table.rowCursor + table.filteredSize > rows.len - 1: rows.len - 1
      else: table.rowCursor + table.filteredSize
    #echo "\n\n\n\n\n\n" & $table.rowCursor & " " & $rowStart & "-" & $rowEnd
    for row in rows[rowStart..min(rowEnd, rows.len - 1)]:
      table.renderClearRow(index)
      table.renderTableRow(row, index)
      index += 1
    table.renderStatusBar()
    #table.tb.drawVertLine(table.width, table.height, table.posY + 1, doubleStyle = true)
    table.tb.display()
  else:
    table.emptyRows()
    table.tb.display()


proc filter(table: var Table, filterStr: string) =
  for r in 0..<table.rows.len:
    for col in table.rows[r].columns:
      if col.text.toLower().contains(filterStr.strip().toLower()): 
        table.rows[r].visible = true
        break
      else:
        table.rows[r].visible = false


proc prevSelection(table: var Table) =
  let rows = table.vrows()
  if table.cursor == 0:
    table.cursor = 0
  else:
    table.cursor -= 1
  if rows.len > 0:
    let index = rows[table.cursor].index
    for r in 0..<table.rows.len:
      if table.rows[r].index == index:
        table.rows[r].selected = true
        table.selectedRow = table.rows[r].index
      else:
        table.rows[r].selected = false


proc nextSelection(table: var Table) =
  let rows = table.vrows()
  if table.cursor >= rows.len - 1:
    table.cursor = rows.len - 1
  else:
    table.cursor += 1
  if rows.len > 0:
    let index = rows[table.cursor].index
    for r in 0..<table.rows.len:
      if table.rows[r].index == index:
        table.rows[r].selected = true
        table.selectedRow = table.rows[r].index
      else:
        table.rows[r].selected = false


proc onFilter(table: var Table) =
  table.cursor = 0
  table.rowCursor = 0
  table.colCursor = 0
  table.renderClearRow(table.size + 5)
  var input = newInputBox(table.width, table.height + 4, table.posX, table.posY + table.size + 4, title="search", tb=table.tb)
  let enterEv = proc(x: string) = 
    input.focus = false
  input.onEnter(some(enterEv))
  procCall input.onControl()
  let filterStr = input.value()
  table.filter(filterStr)
  input.hide()
  table.prevSelection()


proc resetFilter(table: var Table) =
  for r in 0..<table.rows.len:
    table.rows[r].visible = true
  table.size = table.height - table.posY - table.paddingY - 1
  #if table.headers.isSome: table.size -= 1
  table.rowCursor = 0
  table.cursor = 0
  table.colCursor = 0
  table.renderClearRow(0)
  table.prevSelection()




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
      table.prevSelection()
    of Key.Down:
      let rowSize = if table.mode == Filter: table.vrows().len else: table.rows.len
      if table.rowCursor >= rowSize - 1:
        table.rowCursor = rowSize - 1
      else:
        table.rowCursor += 1
      table.nextSelection() 
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
      table.mode = Filter
      table.onFilter()
    of Key.Escape:
      if table.mode == Filter:
        table.mode = Normal
        table.resetFilter()
    of Key.Tab: table.focus = false
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

