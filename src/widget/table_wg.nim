import illwill, sequtils, base_wg, os, options, strutils, parsecsv, 
       input_box_wg, display_wg
from std/streams import newFileStream
import tables as systable
import threading/channels


type
  ColumnType* = enum
    Header, Column

  TableColumnObj* = object of RootObj
    index*: int
    width: int
    height: int
    overflow: bool
    text*: string
    key*: string
    bgColor*: BackgroundColor
    fgColor*: ForegroundColor
    align*: Alignment = Left
    columnType: ColumnType
    value*: string = ""
    visible: bool = true

  TableColumn* = ref TableColumnObj

  TableRowObj* = object of RootObj
    index*: int
    width: int
    height: int
    maxColWidth: int
    columns: seq[TableColumn]
    bgColor*: BackgroundColor
    fgColor*: ForegroundColor
    visible: bool = true
    selected*: bool = false
    value*: string = ""

  TableRow* = ref TableRowObj

  TableObj* = object of BaseWidget
    headers: Option[TableRow]
    rows: seq[TableRow]
    mode: Mode = Normal
    filteredSize: int = 0
    selectedRow: int = 0
    selectionStyle*: SelectionStyle
    maxColWidth: int = 64
    events*: systable.Table[string, EventFn[ref TableObj]]
    keyEvents*: systable.Table[Key, EventFn[ref TableObj]]
  
  Table* = ref TableObj

  SizeDiffError = object of CatchableError

  FileNotFoundError = object of CatchableError

const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.Slash, Key.Up, Key.Down,
                          Key.Left, Key.Right}


proc help(table: Table, args: varargs[string]): void

proc on*(table: Table, key: Key, fn: EventFn[Table]) {.raises: [EventKeyError]} 

proc call*(table: Table, event: string, args: varargs[string]): void

proc newTableColumn*(width: int, height: int = 1; text = ""; key = ""; 
                     index = 0; overflow: bool = false;
                     bgColor = bgNone; fgColor = fgWhite;
                     align = Left; columnType = Column): TableColumn =
  var tc = TableColumn(
    index: index,
    width: max(width, text.len),
    height: height,
    overflow: overflow,
    text: text,
    key: key,
    bgColor: bgColor,
    fgColor: fgColor,
    align: align,
    columnType: columnType,
  )
  return tc


proc newTableColumn*(text = "", columnType = Column): TableColumn =
  var tc = TableColumn(
    index: 0,
    width: len(text),
    height: 1,
    overflow: false,
    text: text,
    key: text,
    bgColor: bgNone,
    fgColor: fgWhite,
    align: Left,
    columnType: columnType,
  )
  return tc



proc newTableRow*(width: int, height = 1; 
                  columns: seq[TableColumn] = newSeq[TableColumn](), 
                  index = 0,bgColor = bgNone, fgColor = fgWhite,
                  selected = false): TableRow =
  var maxColWidth = 0
  for i in 0..<columns.len:
    columns[i].index = i
    maxColWidth = min(columns[i].width, maxColWidth)

  var tr = TableRow(
    index: index,
    width: width,
    height: height,
    columns: columns,
    bgColor: bgColor,
    fgColor: fgColor,
    selected: selected,
    maxColWidth: maxColWidth,
  )
  return tr


proc newTableRow*(): TableRow =
  var tr = TableRow(
    index: 0,
    width: 0,
    height: 1,
    columns: newSeq[TableColumn](),
    bgColor: bgNone,
    fgColor: fgWhite,
    selected: false,
    maxColWidth: 64,
  )
  return tr


proc `columns=`*(tr: TableRow, columns: seq[TableColumn]) =
  var maxColWidth = 0
  for i in 0 ..< columns.len:
    columns[i].index = i
    maxColWidth = min(columns[i].width, maxColWidth)
  tr.columns = columns
  tr.maxColWidth = maxColWidth


proc columns*(tr: TableRow, columns: seq[string]) =
  var maxColWidth = 0
  for i in 0 ..< columns.len:
    var col = newTableColumn(columns[i])
    col.index = i
    maxColWidth = min(len(columns[i]), maxColWidth)
    tr.columns.add(col)
  tr.maxColWidth = maxColWidth


proc addColumn*(tr: TableRow, column: string) =
  var col = newTableColumn(column)
  tr.columns.add(col)
  var maxColWidth = 0
  for i in 0 ..< tr.columns.len:
    tr.columns[i].index = i
    maxColWidth = min(tr.columns[i].width, maxColWidth)
  tr.maxColWidth = maxColWidth


proc addColumn*(tr: TableRow, column: TableColumn) =
  tr.columns.add(column)
  var maxColWidth = 0
  for i in 0 ..< tr.columns.len:
    tr.columns[i].index = i
    maxColWidth = min(tr.columns[i].width, maxColWidth)
  tr.maxColWidth = maxColWidth


proc newTable*(px, py, w, h: int, rows: seq[TableRow], 
               headers: Option[TableRow] = none(TableRow), 
               id = "", title = "", border = true, 
               statusbar = true, enableHelp=false,
               bgColor = bgNone, fgColor = fgWhite,
               selectionStyle: SelectionStyle, maxColWidth = w,
               tb = newTerminalBuffer(w + 2, h + py + 4)): Table =
  var seqColWidth = ($rows.len).len
  for i in 0..<rows.len:
    var seqCol = newTableColumn(seqColWidth, 1, text = $(i + 1), key = $i, index = i)
    rows[i].columns.insert(seqCol, 0)
    rows[i].index = i
  let padding = 1
  let statusbarSize = if statusbar: 2 else: 1
  let style = WidgetStyle(
    paddingX1: padding,
    paddingX2: padding,
    paddingY1: padding,
    paddingY2: padding,
    border: border,
    fgColor: fgColor,
    bgColor: bgColor
  )

  var table = (Table)(
    width: min(w + seqColWidth, w),
    height: h,
    posX: px,
    posY: py,
    id: id,
    headers: headers,
    rows: rows,
    title: title,
    size: h - py - style.paddingY1 - style.paddingY2 - statusbarSize,
    tb: tb,
    style: style,
    maxColWidth: maxColWidth,
    selectionStyle: selectionStyle,
    statusbar: statusbar,
    enableHelp: enableHelp,
    events: initTable[string, EventFn[Table]](),
    keyEvents: initTable[Key, EventFn[Table]]()
  )
  if headers.isSome: 
    table.size -= 1
    let seqCol = newTableColumn(seqColWidth, 1, text = alignLeft("i", seqColWidth), key = "", index = 0)
    table.headers.get.columns.insert(seqCol, 0)
    table.height += table.style.paddingY1
  if table.rows.len > 0:
    table.rows[0].selected = true
  table.channel = newChan[WidgetBgEvent]()
  if enableHelp:
    table.on(Key.QuestionMark, help)
  table.keepOriginalSize()
  return table


proc newTable*(px, py, w, h: int, id = "", title = "", border = true, 
               statusbar = true, enableHelp = false,
               bgColor = bgNone, fgColor = fgWhite,                
               selectionStyle: SelectionStyle = Highlight, maxColWidth=w,
               tb = newTerminalBuffer(w + 2, h + py + 4)): Table =
  var rows = newSeq[TableRow]()
  let padding = 1
  let statusbarSize = if statusbar: 2 else: 1
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
  var table = (Table)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    headers: none(TableRow),
    rows: rows,
    title: title,
    size: h - py - style.paddingY1 - style.paddingY2 - statusbarSize,
    tb: tb,
    style: style,
    maxColWidth: maxColWidth,
    selectionStyle: selectionStyle,
    statusbar: statusbar,
    enableHelp: enableHelp,
    events: initTable[string, EventFn[Table]](),
    keyEvents: initTable[Key, EventFn[Table]]()
  )
  table.channel = newChan[WidgetBgEvent]()
  if enableHelp:
    table.on(Key.QuestionMark, help)
  table.keepOriginalSize()
  return table


proc newTable*(px, py: int, w, h: WidgetSize, rows: seq[TableRow],
               headers: Option[TableRow] = none(TableRow), 
               id = "", title = "", border = true, statusbar = true, 
               enableHelp = false, bgColor = bgNone, fgColor = fgWhite,
               selectionStyle: SelectionStyle = Highlight, maxColWidth=w.toInt,
               tb = newTerminalBuffer(w.toInt + 2, h.toInt + py + 4)): Table =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newTable(px, py, width, height, rows, headers, id, title, border, statusbar,
                  enableHelp, bgColor, fgColor, selectionStyle, maxColWidth, tb) 


proc newTable*(id: string): Table =
  let padding = 1
  var table = Table(
    id: id,
    style: WidgetStyle(
      paddingX1: padding,
      paddingX2: padding,
      paddingY1: padding,
      paddingY2: padding,
      border: true,
      bgColor: bgNone,
      fgColor: fgWhite
    ),
    headers: none(TableRow),
    rows: newSeq[TableRow](),
    size: 0,
    events: initTable[string, EventFn[Table]](),
    keyEvents: initTable[Key, EventFn[Table]]()
  )
  table.channel = newChan[WidgetBgEvent]()
  table.on(Key.QuestionMark, help)
  return table


proc rowMaxWidth(table: Table): int =
  result = 0
  if table.headers.isSome:
    for col in table.headers.get.columns:
      result += col.width
  else:
    for col in table.rows[table.cursor].columns:
      result += col.width


proc vrows(table: Table): seq[TableRow] = 
  table.rows.filter(proc(r: TableRow): bool = r.visible)


proc dtmColumnToDisplay(table: Table) =
  if table.headers.isSome:
    table.headers.get.columns[table.colCursor].visible = true
    # var posX = table.headers.get.columns[table.colCursor].width
    #   table.paddingX1 - table.paddingX2
    var posX = table.paddingX1 + table.paddingX2
    for i in (table.colCursor + 1)..<table.headers.get.columns.len:
      if posX + table.headers.get.columns[i].width < table.x2:
        table.headers.get.columns[i].visible = true
      else:
        table.headers.get.columns[i].visible = false
      posX += table.headers.get.columns[i].width
    for i in 0..<table.colCursor:
      table.headers.get.columns[i].visible = false


proc prevSelection(table: Table, size: int = 1) =
  let rows = table.vrows()
  if table.cursor == 0:
    table.cursor = 0
  else:
    table.cursor -= size
  if rows.len > 0:
    let index = rows[table.cursor].index
    for r in 0..<table.rows.len:
      if table.rows[r].index == index:
        table.rows[r].selected = true
        table.selectedRow = table.rows[r].index
      else:
        table.rows[r].selected = false


proc nextSelection(table: Table, size: int = 1) =
  let rows = table.vrows()
  if table.cursor >= rows.len - size:
    table.cursor = rows.len - size
  else:
    table.cursor += size
  if rows.len > 0:
    let index = rows[table.cursor].index
    for r in 0..<table.rows.len:
      if table.rows[r].index == index:
        table.rows[r].selected = true
        table.selectedRow = table.rows[r].index
      else:
        table.rows[r].selected = false


proc emptyRows(table: Table, emptyMessage = "No records", 
                bgColor = bgRed, fgColor = fgWhite) =
  if table.events.hasKey("empty"):
    table.call("empty", "")
  else:
    table.tb.write(table.posX + table.paddingX1,
                   table.posY + 3, bgColor, fgColor, 
                   center(emptyMessage, table.width - table.paddingX1 - 2), resetStyle)


proc renderClearRow(table: Table, index: int, full = false) =
  if full:
    let totalWidth = table.rowMaxWidth()
    table.tb.fill(table.posX, table.posY,
                  totalWidth, table.height, " ")
  else:
    table.tb.fill(table.posX + table.paddingX1, table.posY + index,
                  table.width - table.posX + table.paddingX1, table.posY + index, " ")


proc renderTableHeader(table: Table): int =
  result = 1
  let borderX = if table.border: 1 else: 0
  if table.headers.isSome:
    var posX = table.paddingX1
    for i in table.colCursor..<table.headers.get.columns.len:
      if table.headers.get.columns[i].visible and posX < table.width:
        var text = table.headers.get.columns[i].text
        if table.posX + posX + text.len > table.x2:
          let extraSize = table.posX + posX + text.len - table.x2
          text = text.substr(0, (text.len - extraSize - 2)) & ".."
        table.tb.write(table.posX + posX, table.posY + result, 
                       table.headers.get.columns[i].bgColor, 
                       table.headers.get.columns[i].fgColor,
                       styleBright, if i == table.colCursor: styleUnderscore else: styleBright,
                       alignLeft(table.headers.get.columns[i].text, 
                                 min(table.headers.get.columns[i].width, 
                                     max(0, table.width - table.posX - posX - borderX))), 
                       resetStyle)
        posX = posX + table.headers.get.columns[i].width + 1

      if table.x2 - table.x1 - posX < 2: break
    result += 1


proc calColWidth(table: Table, cindex: int, defaultWidth: int): int =
  if table.headers.isSome:
    result = table.headers.get.columns[cindex].width
  else:
    result = defaultWidth


# TODO: multi row render for height > 1
proc renderTableRow(table: Table, row: TableRow, index: int) =
  var posX = table.paddingX1
  var borderX = if table.border: 1 else: 0
  for i in 0..<row.columns.len:
    var text = row.columns[i].text
    if row.visible and table.headers.get.columns[i].visible and posX < table.width:
      if row.selected and (table.selectionStyle == Arrow or table.selectionStyle == HighlightArrow):
        table.tb.write(table.posX + 1, table.posY + index, fgGreen, ">", resetStyle)
      var width = table.calColWidth(i, row.columns[i].width)
      # determine text to dislay by available wdith
      if row.columns[i].align == Left:
        # text = alignLeft(text, min(width, max(0, table.width - table.posX - posX - borderX)))
        text = alignLeft(text, min(width, max(0, table.x2 - table.x1 - posX - borderX)))
      elif row.columns[i].align == Center:
        #text = center(text, min(width, max(0, table.width - table.posX - posX - borderX)))
        text = center(text, min(width, max(0, table.x2 - table.x1 - posX - borderX)))
      elif row.columns[i].align == Right:
        # text = align(text, min(width, max(0, table.width - table.posX - posX - borderX)))
        text = align(text, min(width, max(0, table.x2 - table.x1 - posX - borderX)))
      if table.x1 + posX + text.len > table.x2:
        let extraSize = table.x1 + posX + text.len - table.x2
        text = text.substr(0, (text.len - extraSize - 2)) & ".."
      # render  row
      var bgSelected = row.columns[i].bgColor
      if row.selected and (table.selectionStyle == Highlight or table.selectionStyle == HighlightArrow):
        bgSelected = bgGreen
        table.tb.write(table.posX + posX, table.posY + index, resetStyle,
                       bgSelected, row.columns[i].fgColor, text, resetStyle)
      else:
        table.tb.write(table.posX + posX, table.posY + index, resetStyle,
                       bgSelected, row.columns[i].fgColor, text, resetStyle)
      posX += width + 1
    if table.x2 - table.x1 - posX < 2: break


proc renderStatusBar(table: Table) =
  if table.statusbar:
    if table.events.hasKey("statusbar"):
      table.call("statusbar")
    else:
      let mode = " " & $table.mode & " "
      table.tb.write(table.x1, table.height, fgBlack, bgWhite, mode, resetStyle)
      table.tb.write(table.x1 + mode.len + 1, table.height, fgBlack, bgWhite, 
                     " size: " & $table.vrows().len & " ", 
                     resetStyle)
      if table.enableHelp:
        let q = "[?]"
        table.tb.write(table.x2 - q.len, table.height, bgWhite, fgBlack, q, resetStyle)



proc help(table: Table, args: varargs[string]) = 
  let wsize = ((table.width - table.posX).toFloat * 0.3).toInt()
  let hsize = ((table.height - table.posY).toFloat * 0.3).toInt()
  var display = newDisplay(table.x2 - wsize, table.y2 - hsize, 
                          table.x2, table.y2, title="help",
                          bgColor=bgWhite, fgColor=fgBlack,
                          tb=table.tb, statusbar=false,
                          enableHelp=false)
  var helpText: string
  if table.helpText == "":
    helpText = " [Enter] to select\n" &
               " [/]     to search\n" &
               " [?]     for help\n" &
               " [Tab]   to go next widget\n" &
               " [Esc]   to exit this window"
  display.text = helpText
  display.illwillInit = true
  display.onControl()
  display.clear()


method resize*(table: Table) =
  let statusbarSize = 2
  let padding = 1
  table.size = table.height - table.posY - 
    padding - padding - statusbarSize
  table.maxColWidth = table.x2 - table.x1


method render*(table: Table): void =
  if not table.illwillInit: return
  table.call("prerender")
  #table.renderClearRow(0, true)
  table.clear()
  #if table.border:
  table.renderBorder()
  #if table.title != "":
  table.renderTitle()
  table.dtmColumnToDisplay()
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
      #table.renderClearRow(index)
      table.renderTableRow(row, index)
      index += 1

    table.renderStatusBar()
    table.tb.display()
  else:
    table.emptyRows()
    table.tb.display()
  table.call("postrender")


proc filter(table: Table, filterStr: string) =
  for r in 0..<table.rows.len:
    for col in table.rows[r].columns:
      if col.text.toLower().contains(filterStr.strip().toLower()): 
        table.rows[r].visible = true
        break
      else:
        table.rows[r].visible = false


proc onFilter(table: Table) =
  table.resetCursor()
  table.renderStatusBar()
  table.renderClearRow(table.size + 5)
  var input = newInputBox(table.x1, table.y1, 
                          table.x2, table.y1 + 2, 
                          title="search", 
                          tb=table.tb)
  let enterEv = proc(ib: InputBox, x: varargs[string]) = 
    table.filter(ib.value)
    table.prevSelection()
    input.focus = false
    input.remove()
  # passing enter event as a callback
  input.illwillInit = true
  input.on("enter", enterEv)
  input.onControl()
  #procCall input.onControl(enterEv)
  
  

proc resetFilter(table: Table) =
  for r in 0..<table.rows.len:
    table.rows[r].visible = true
  table.resize()
  #table.size = table.height - table.posY - table.paddingY1 - table.paddingY2
  table.rowCursor = 0
  table.cursor = 0
  table.colCursor = 0
  table.renderClearRow(0)
  table.prevSelection()


proc on*(table: Table, event: string, fn: EventFn[Table]) =
  table.events[event] = fn


proc on*(table: Table, key: Key, fn: EventFn[Table]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  table.keyEvents[key] = fn
    

proc call*(table: Table, event: string, args: varargs[string]) =
  let fn = table.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(table, args)


proc call(table: Table, key: Key, args: varargs[string]) =
  let fn = table.keyEvents.getOrDefault(key, nil)
  if not fn.isNil:
    fn(table, args)


method poll*(table: Table) =
  var widgetEv: WidgetBgEvent
  if table.channel.tryRecv(widgetEv):
    table.call(widgetEv.event, widgetEv.args)
    table.render()


method onUpdate*(table: Table, key: Key) =
  table.call("preupdate", $key)
  case key
  of Key.None: 
    #table.dtmColumnToDisplay()
    table.render()
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
  
  of Key.PageUp:
    let size = if table.cursor - table.size > 0: table.size - 1
      else: 1
    if table.rowCursor == 0:
      table.rowCursor = 0
    else:
      table.rowCursor = table.rowCursor - size
    table.prevSelection(size)

  of Key.PageDown:
    let size = if table.rows.len - table.cursor > table.size: table.size - 1 
      else: table.rows.len - table.cursor - 1
    let rowSize = if table.mode == Filter: table.vrows().len else: table.rows.len 
    if table.rowCursor >= rowSize - size:
      table.rowCursor = rowSize - size
    else:
      table.rowCursor += size
    table.nextSelection(size) 

  of Key.Right: 
    if table.colCursor == table.headers.get.columns.len - 1:
      table.colCursor = table.headers.get.columns.len - 1
    else:
      table.colCursor += 1
    #table.dtmColumnToDisplay()
  of Key.Left:
    if table.colCursor == 0:
      table.colCursor = 0
    else:
      table.colCursor -= 1
    #table.dtmColumnToDisplay()
  of Key.Slash:
    table.mode = Filter
    table.onFilter()
  of Key.Escape:
    if table.mode == Filter:
      table.mode = Normal
      table.resetFilter()
  of Key.Tab: 
    table.focus = false
  of Key.Enter:
    table.call("enter")
  else: 
    if key in forbiddenKeyBind: discard
    elif table.keyEvents.hasKey(key):
      table.call(key)

  table.render()
  table.call("postupdate", $key)


method onControl*(table: Table): void =
  table.focus = true
  while table.focus:
    var key = getKeyWithTimeout(table.rpms)
    table.onUpdate(key) 


method wg*(table: Table): ref BaseWidget = table


proc `header=`*(table: Table, header: TableRow) =
  table.headers = some(header)
  table.render()

proc header*(table: Table, header: TableRow) =
  table.headers = some(header)
  table.render()


proc header*(table: Table): Option[TableRow] = table.headers


proc addRow*(table: Table, tablerow: TableRow, index: Option[int] = none(int)): void =
  for i in 0..<tablerow.columns.len:
    if tablerow.columns[i].text.len >= table.headers.get.columns[i].width:
      table.headers.get.columns[i].width = min(table.maxColWidth, 
                                               tablerow.columns[i].text.len + 1)
    if tablerow.columns[i].text.len > table.maxColWidth:
      tablerow.columns[i].text = tablerow.columns[i].text[0..table.maxColWidth - 3] &  ".."

  if index.isSome:
    tablerow.index = index.get
  else:
    tablerow.index = table.rows.len + 1
  table.rows.add(tablerow)
  if table.rows.len == 1:
    tablerow.selected = true
    table.selectedRow = 1
  else:
    tablerow.selected = false


proc rows*(table: Table): seq[TableRow] =
  return table.rows


proc removeRow*(table: Table, index: int) =
  table.rows.delete(index)
  table.render()


proc clearRows*(table: Table) =
  table.rows = newSeq[TableRow]()
  table.resetCursor()
  table.render()


proc selected*(table: Table): TableRow =
  return table.rows[table.cursor]


proc loadFromCsv*(table: Table, filepath: string, withHeader = false, 
                  withIndex = false) =
  try:
    if not filepath.endsWith(".csv"):
      raise newException(IOError, "Unable to load non csv file")
    table.rows = newSeq[TableRow]()
    var stream = newFileStream(filepath, fmRead)
    if stream == nil:
      raise newException(FileNotFoundError, "Unable to open file")
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
    table.resetCursor()
    table.render()
  except IOError, FileNotFoundError:
    table.emptyRows()
    echo "failed to open file"


proc headerFromArray*(table: Table, header: openArray[string], 
                      bgColor=bgNone, fgColor=fgWhite) =
  if header.len == 0:
    raise newException(ValueError, "header cannot be empty")

  var headers = newTableRow(table.width)
  for h in header:
    let column = newTableColumn(h.len, 1, h, h, bgColor=bgColor, 
                                fgColor=fgColor)
    headers.columns.add(column)
  table.header = headers


proc loadFromSeq*(table: Table, rows: openArray[seq[string]]) =
  if rows.len == 0:
    raise newException(ValueError, "rows cannot be empty.")

  for i in 0 ..< rows.len:
    if table.headers.isSome:
      if table.headers.get.columns.len != rows[i].len:
        raise newException(SizeDiffError, "Table header and rows has different size")

    var row = newTableRow(table.width)
    for d in rows[i]:
      var column = newTableColumn(d.len, 1, d, d)
      row.columns.add(column)
    table.addRow(row)

  table.resetCursor()
  table.prevSelection()
  table.render()


