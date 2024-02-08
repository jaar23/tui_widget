import illwill, sequtils, base_wg, os, options, strutils, parsecsv, input_box_wg
from std/streams import newFileStream

type
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
    value*: string = ""
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
    selected: bool = false

  Table = object of BaseWidget
    headers: Option[TableRow]
    rows: seq[TableRow]
    cursor: int = 0
    rowCursor: int = 0
    colCursor: int = 0
    mode: Mode = Normal
    filteredSize: int = 0
    selectedRow: int = 0
    maxColWidth: int = 64


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
    maxColWidth: maxColWidth,
  )
  return tr


proc newTable*(px, py, w, h: int, rows: var seq[TableRow], 
               headers: Option[TableRow] = none(TableRow), 
               title: string = "", cursor = 0, rowCursor = 0, 
               border: bool = true, statusbar: bool = true,
               fgColor: ForegroundColor = fgWhite, bgColor: BackgroundColor = bgNone,
               tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py + 4)): ref Table =
  var seqColWidth = ($rows.len).len
  for i in 0..<rows.len:
    var seqCol = newTableColumn(seqColWidth, 1, text = $(i + 1), key = $i, index = i)
    rows[i].columns.insert(seqCol, 0)
    rows[i].index = i
  let padding = if border: 2 else: 1
  let style = WidgetStyle(
    paddingX1: padding,
    paddingX2: padding,
    paddingY1: padding,
    paddingY2: padding,
    border: border,
    fgColor: fgColor,
    bgColor: bgColor
  )

  var table = (ref Table)(
    width: min(w + seqColWidth, w),
    height: h,
    posX: px,
    posY: py,
    headers: headers,
    rows: rows,
    title: title,
    cursor: cursor,
    rowCursor: rowCursor,
    size: h - py - style.paddingY1 - style.paddingY2,
    tb: tb,
    style: style,
    colCursor: 0,
    maxColWidth: w
  )
  if headers.isSome: 
    table.size -= 1
    var seqCol = newTableColumn(seqColWidth, 1, text = alignLeft("i", seqColWidth), key = "", index = 0)
    table.headers.get.columns.insert(seqCol, 0)
    table.height += table.style.paddingY1
  if table.rows.len > 0:
    table.rows[0].selected = true
  return table


proc newTable*(px, py, w, h: int, title: string = "", cursor = 0, rowCursor = 0, 
               border: bool = true, statusbar: bool = true,
               fgColor: ForegroundColor = fgWhite, bgColor: BackgroundColor = bgNone,
               tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py + 4)): ref Table =
  var rows = newSeq[TableRow]()
  let padding = if border: 2 else: 1
  let style = WidgetStyle(
    paddingX1: padding,
    paddingX2: padding,
    paddingY1: padding,
    paddingY2: padding,
    border: border,
    fgColor: fgColor,
    bgColor: bgColor
  )
  ##  size tp remove border, table title
  var table = (ref Table)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    headers: none(TableRow),
    rows: rows,
    title: title,
    cursor: cursor,
    rowCursor: rowCursor,
    size: h - py - style.paddingY1 - style.paddingY2,
    tb: tb,
    style: style,
    colCursor: 0
  )
  #table.height += table.style.paddingY1
  return table


proc rowMaxWidth(table: ref Table): int =
  result = 0
  if table.headers.isSome:
    for col in table.headers.get.columns:
      result += col.width
  else:
    for col in table.rows[table.cursor].columns:
      result += col.width


proc vrows(table: ref Table): seq[TableRow] = table.rows.filter(proc(r: TableRow): bool = r.visible)


proc dtmColumnToDisplay(table: ref Table) =
  var posX = table.paddingX1
  for i in table.colCursor..<table.headers.get.columns.len:
    if posX + table.headers.get.columns[i].width < table.width:
    #if posX < table.width:
      table.headers.get.columns[i].visible = true
      posX += table.headers.get.columns[i].width
    else:
      table.headers.get.columns[i].visible = false
  for i in 0..<table.colCursor:
    table.headers.get.columns[i].visible = false


proc prevSelection(table: ref Table) =
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


proc nextSelection(table: ref Table) =
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


proc emptyRows(table: ref Table, emptyMessage = "No records") =
  table.tb.write(table.posX + table.paddingX1,
                 table.posY + 3, bgRed, fgWhite, 
                 center(emptyMessage, table.width - table.paddingX1 - 2), resetStyle)


proc renderClearRow(table: ref Table, index: int, full = false) =
  if full:
    let totalWidth = table.rowMaxWidth()
    table.tb.fill(table.posX, table.posY,
                  totalWidth, table.height + table.paddingY1 + 3, " ")
  else:
    table.tb.fill(table.posX + table.paddingX1, table.posY + index,
                  table.width - table.paddingX1, table.posY + index, " ")


proc renderTableHeader(table: ref Table): int =
  result = 1
  let borderX = if table.border: 1 else: 2
  if table.headers.isSome:
    var posX = table.paddingX1
    for i in table.colCursor..<table.headers.get.columns.len:
      if table.headers.get.columns[i].visible and posX < table.width:
        table.tb.write(table.posX + posX, table.posY + result, bgBlue, 
                       table.headers.get.columns[i].fgColor, 
                       alignLeft(table.headers.get.columns[i].text, 
                                 min(table.headers.get.columns[i].width, 
                                     table.width - table.posX - posX - borderX)), 
                       resetStyle)
        posX = posX + table.headers.get.columns[i].width + 1
    result += 1


proc calColWidth(table: ref Table, cindex: int, defaultWidth: int): int =
  if table.headers.isSome:
    result = table.headers.get.columns[cindex].width
  else:
    result = defaultWidth


proc renderTableRow(table: ref Table, row: TableRow, index: int) =
  var posX = table.paddingX1
  var borderX = if table.border: 1 else: 0
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
      table.tb.write(table.posX + posX, table.posY + index, resetStyle,
                     bgSelected, row.columns[i].fgColor, text, resetStyle)
      posX += width + 1


proc renderStatusBar(table: ref Table) =
  if table.statusbar:
    table.tb.write(table.x1, table.height, fgYellow, "rows: ", 
                   $table.vrows().len , " selected: ", $table.selectedRow, 
                   resetStyle)


method render*(table: ref Table): void =
  table.renderClearRow(0, true)
  if table.border:
    table.renderBorder()
    # table.tb.drawRect(table.width, table.height + table.paddingY1 + 1,
    #                   table.posX, table.posY, doubleStyle = table.focus)
  if table.title != "":
    table.renderTitle(table.title)
    # table.tb.write(table.posX + table.paddingX1, table.posY, table.title)
  var index = table.renderTableHeader()
  let rows = table.vrows()
  if rows.len > 0:
    table.filteredSize = min(table.size, rows.len)
    ##########################################
    # highlight at bottom while cursor moving
    var rowStart = max(0, table.rowCursor)
    var rowEnd = rowStart + table.filteredSize
    if rowEnd > table.filteredSize:
      rowStart = max(0, table.rowCursor - table.filteredSize)
      rowEnd = max(table.rowCursor + 1, table.filteredSize)
    
    ##########################################
    # highlight at top while cursor moving
    # 
    # var rowStart = table.rowCursor
    # var rowEnd = if table.rowCursor + table.filteredSize > rows.len - 1: rows.len - 1
    #   else: table.rowCursor + table.filteredSize
    #########################################
    for row in rows[rowStart..min(rowEnd, rows.len - 1)]:
      table.renderClearRow(index)
      table.renderTableRow(row, index)
      index += 1
    table.renderStatusBar()
    table.tb.display()
  else:
    table.emptyRows()
    table.tb.display()


proc filter(table: ref Table, filterStr: string) =
  for r in 0..<table.rows.len:
    for col in table.rows[r].columns:
      if col.text.toLower().contains(filterStr.strip().toLower()): 
        table.rows[r].visible = true
        break
      else:
        table.rows[r].visible = false


proc onFilter(table: ref Table) =
  table.cursor = 0
  table.rowCursor = 0
  table.colCursor = 0
  table.renderClearRow(table.size + 5)
  var input = newInputBox(table.x1, table.y1, 
                          table.x2, table.y2, 
                          title="search", 
                          tb=table.tb)
  let enterEv: CallbackProcedure = proc(x: string) = 
    table.filter(x)
    table.prevSelection()
    input.focus = false
    input.remove()
  # passing enter event as a callback
  procCall input.onControl(some(enterEv))
  # passing enter event to onEnter method
  #input.onEnter(some(enterEv))
  # let filterStr = input.value()
  # table.filter(filterStr)
  # input.hide()
  # table.prevSelection()


proc resetFilter(table: ref Table) =
  for r in 0..<table.rows.len:
    table.rows[r].visible = true
  table.size = table.height - table.posY - table.paddingY1 - table.paddingY2
  #if table.headers.isSome: table.size -= 1
  table.rowCursor = 0
  table.cursor = 0
  table.colCursor = 0
  table.renderClearRow(0)
  table.prevSelection()




method onControl*(table: ref Table): void =
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


proc show*(table: ref Table) = table.render()


proc `-`*(table: ref Table) = table.show()


proc addRow*(table: ref Table, tablerow: var TableRow, index: Option[int] = none(int)): void =
  for i in 0..<tablerow.columns.len:
    if tablerow.columns[i].text.len >= table.headers.get.columns[i].width:
      table.headers.get.columns[i].width = min(table.maxColWidth, 
                                               tablerow.columns[i].text.len + 1)
  if index.isSome:
    tablerow.index = index.get
  else:
    tablerow.index = table.rows.len + 1
  tablerow.selected = false
  table.rows.add(tablerow)


proc removeRow*(table: ref Table, index: int): void =
  return


proc selected*(table: ref Table): TableRow =
  return table.rows[table.cursor]


proc loadFromCsv*(table: ref Table, filepath: string, withHeader = false, withIndex = false): void =
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
        if not withIndex:
          var column = newTableColumn(($rindex).len + 1, 1, "s/q", $rindex, rindex, columnType=Header)
          row.add(column)
        for val in items(csvparser.row):
          var column = newTableColumn(val.len + 1, 1, val, $rindex, rindex, columnType=Header)
          row.add(column)
          headerWidth += val.len + 1 
        var header = newTableRow(headerWidth, 1, row)
        table.headers = some(header)
      else:
        var rowWidth = 0
        if not withIndex:
          var column = newTableColumn(($rindex).len, 1, $rindex, $rindex, rindex, columnType=Column)
          row.add(column)
        for val in items(csvparser.row):
          var col = newTableColumn(val.len, 1, val, $rindex, rindex, columnType=Column)
          row.add(col)
          rowWidth += val.len
        var tableRow = newTableRow(rowWidth, 1, row)
        table.addRow(tableRow)
      rindex += 1
    csvparser.close()
    table.cursor = 0
    table.prevSelection()
  except:
    echo "failed to open file"

