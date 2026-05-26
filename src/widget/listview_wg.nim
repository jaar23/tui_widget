import illwill, base_wg, sequtils, strutils, os, tables, display_wg, unicode
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
    rows*: seq[ListRow]
    selectedRow*: int = 0
    mode: Mode = Normal
    filteredSize: int = 0
    selectionStyle*: SelectionStyle
    textOverlay*: bool = false
      ## When true, render() skips the per-row inner tb.write loop;
      ## a postDisplay hook is expected to overlay row text via stdout.
      ## Used for CJK / wide-glyph correctness. Pair with
      ## `enableTextOverlay()` to get a default overlay closure that
      ## handles selection via ANSI inverse video.
    events*: Table[string, EventFn[ListView]]
    keyEvents*: Table[Key, EventFn[ListView]]
    mouseEvents*: Table[MouseButton, EventFn[ListView]]
    mouseEnabled*: bool = false

  ListView* = ref ListViewObj


const forbiddenKeyBind = {Key.Tab, Key.None, Key.Up,
                          Key.Down, Key.PageUp, Key.PageDown}
                          # unlock left right key binding
                          # Key.Left, Key.Right}

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
                  mouseEnabled: bool = false,
                  tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py + 4)): ListView =
  let padding = if border: 1 else: 0
  # let statusbarSize = if statusbar: 1 else: 0
  let statusbarSize = 1
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
    keyEvents: initTable[Key, EventFn[ListView]](),
    mouseEnabled: mouseEnabled,
    mouseEvents: initTable[MouseButton, EventFn[ListView]]()
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
                  mouseEnabled: bool = false,
                  tb = newTerminalBuffer(w.toInt + 2, h.toInt + py + 4)): ListView =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newListView(px, py, width, height, id, title, border, statusbar,
                    statusbarText, enableHelp, rows,bgColor, fgColor,
                    selectionStyle, mouseEnabled, tb)


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
    keyEvents: initTable[Key, EventFn[ListView]](),
    mouseEnabled: false,
    mouseEvents: initTable[MouseButton, EventFn[ListView]]()
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
  # Strip ANSI before slicing — byte-indexing into a string with embedded
  # CSI sequences could cut mid-escape and leave the terminal in a stuck
  # styled state, or push the row's tail past the right border once
  # tb.write turns each ESC into a literal cell.
  let rowText = stripAnsi(lv.rows[selected].text)
  var actualStartIndex = max(0, rowText.len - (lv.width - (lv.paddingX1 +
      lv.paddingX2)))
  actualStartIndex = min(actualStartIndex, startIndex)
  if actualStartIndex < 0:
    actualStartIndex = 0
  let endIndex = min(actualStartIndex + lv.width - (lv.paddingX1 + lv.paddingX2), rowText.len)
  return rowText[actualStartIndex ..< min(rowText.len, endIndex - extraPadd)]


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
  # Embedded CSI escapes in row.text get drawn as literal cells by
  # tb.write, then re-interpreted as control codes when the buffer is
  # displayed — text after the escape shifts left and overflows the right
  # border. Strip before slicing so the byte length and the visible width
  # match. scrollRow already strips internally.
  let cleanText = stripAnsi(row.text)
  var text = ""
  if row.selected and (lv.x2 - lv.x1) > cleanText.len:
    text = cleanText
  elif row.selected and (lv.x2 - lv.x1) < cleanText.len:
    text = lv.scrollRow(lv.colCursor)
  else:
    text = cleanText[0..min(cleanText.len - 1, lv.width - lv.x1 - posX - borderX)]

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
  #let statusbarSize = if lv.statusbar: 1 else: 0
  let statusbarSize = 1
  lv.size = lv.height - lv.posY - lv.paddingY2 - lv.paddingY1 - statusbarSize


proc on*(lv: ListView, event: string, fn: EventFn[ListView]) =
  lv.events[event] = fn


proc on*(lv: ListView, key: Key, fn: EventFn[ListView]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  lv.keyEvents[key] = fn
    

proc call*(lv: ListView, event: string, args: varargs[string]) =
  if lv.events.hasKey(event):
    let fn = lv.events[event]
    fn(lv, args)


proc call(lv: ListView, key: Key, args: varargs[string]) =
  if lv.keyEvents.hasKey(key):
    let fn = lv.keyEvents[key]
    fn(lv, args)


method poll*(lv: ListView) =
  var widgetEv: WidgetBgEvent
  if lv.channel.tryRecv(widgetEv):
    lv.call(widgetEv.event, widgetEv.args)
    lv.render()


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
      # When textOverlay is true, leave the cleared row alone — a
      # postDisplay hook will write it via stdout (CJK-safe).
      if not lv.textOverlay:
        lv.renderListRow(row, index)
      index += 1
    if lv.mode == Filter:
      lv.renderStatusBar("Mode: " & $lv.mode & "|" & $lv.cursor)
    else:
      #lv.renderStatusBar($lv.cursor & "|" & $lv.selectedRow)
      lv.renderStatusBar()
    if not lv.suppressDisplay: lv.tb.display()
  else:
    lv.emptyRows()
    if not lv.suppressDisplay: lv.tb.display()


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

## Mouse events
proc onMouse*(lv: ListView, button: MouseButton, fn: EventFn[ListView]) =
  ## Set mouse event handler for specific button
  lv.mouseEvents[button] = fn

proc handleMouseEvent*(lv: ListView, mouseInfo: MouseInfo) =
  ## Handle mouse events including wheel scrolling and click-to-select.
  if mouseInfo.scroll:
    case mouseInfo.scrollDir
    of sdUp:
      lv.rowCursor = max(0, lv.rowCursor - 3)
    of sdDown:
      let rowSize = if lv.mode == Filter: lv.vrows().len else: lv.rows.len
      let maxCur = max(0, rowSize - 1)
      lv.rowCursor = min(maxCur, lv.rowCursor + 3)
    else:
      discard
    lv.render()
    return

  if mouseInfo.action == mbaPressed and mouseInfo.button == MouseButton.mbLeft:
    let rows = lv.vrows()
    if rows.len > 0:
      # First visible row is at posY + 1 (posY itself is the title row)
      let visualOffset = mouseInfo.y - lv.posY
      if visualOffset >= 1 and visualOffset <= lv.filteredSize:
        var rowStart = max(0, lv.rowCursor)
        var rowEnd = rowStart + lv.filteredSize
        if rowEnd > lv.filteredSize:
          rowStart = max(0, lv.rowCursor - lv.filteredSize)
        let targetIdx = rowStart + visualOffset - 1
        if targetIdx >= 0 and targetIdx < rows.len:
          lv.cursor = targetIdx
          let rowIdx = rows[targetIdx].index
          for r in 0..<lv.rows.len:
            lv.rows[r].selected = (lv.rows[r].index == rowIdx)
            if lv.rows[r].index == rowIdx:
              lv.selectedRow = lv.rows[r].index
          lv.call("enter", lv.selected.value)
          lv.render()
          return

    if lv.mouseEvents.hasKey(mouseInfo.button):
      let fn = lv.mouseEvents[mouseInfo.button]
      fn(lv, @[$mouseInfo.x, $mouseInfo.y])

method onMouseEvent*(lv: ListView, mouseInfo: MouseInfo) =
  handleMouseEvent(lv, mouseInfo)


method onUpdate*(lv: ListView, key: Key) =
  # Key.None means the input poll timed out — no actual keypress. Re-rendering
  # here on every idle tick is what makes the screen look "stuck flickering":
  # illwill's drawRect writes the border via a BoxBuffer whose horizontal box
  # chars carry forceWrite=true (see illwill.nim:1535), so displayDiff cannot
  # suppress the border — every onUpdate(Key.None) -> render() re-emits the
  # full border for this widget. With the host app firing Key.None at the rpms
  # cadence and the trailing render at the bottom of this proc, the focused
  # ListView was repainting itself ~20× per second forever. The app's main
  # render loop (TerminalApp.render) already re-renders this widget after
  # onUpdate returns, so dropping our own render on Key.None is safe: any
  # external content change still reaches the screen via the next frame.
  if key == Key.None:
    lv.call("preupdate", $key)
    lv.call("postupdate", $key)
    return
  lv.call("preupdate", $key)
  # catch changes from ref component
  if lv.rows.len != lv.vrows().len:
    lv.mode = Filter

  case key
  of Key.Mouse:  # Handle mouse events in onUpdate
    if lv.mouseEnabled:
      let mouseInfo = getMouse()
      lv.handleMouseEvent(mouseInfo)
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
  of Key.PageUp:
    # Scroll up one viewport; keep selection where it was (let the user
    # browse history without losing the active row).
    lv.rowCursor = max(0, lv.rowCursor - lv.size)
  of Key.PageDown:
    let total = if lv.mode == Filter: lv.vrows().len else: lv.rows.len
    let maxCur = max(0, total - 1)
    lv.rowCursor = min(maxCur, lv.rowCursor + lv.size)
  of Key.Right:
    # Same empty-list guard as the custom-key path below — Right/Left/Enter
    # all read lv.selected (= lv.rows[lv.selectedRow]) which is OOB on an
    # empty list. Skip the colCursor recompute too; there's no row to
    # horizontally scroll within.
    if lv.rows.len > 0 and lv.cursor < lv.rows.len:
      lv.colCursor = min(lv.colCursor + 1,
        lv.rows[lv.cursor].text.len -
          (lv.width - (lv.paddingX1 + lv.paddingX2)))
    let valR =
      if lv.rows.len == 0 or lv.selectedRow < 0 or
         lv.selectedRow >= lv.rows.len: ""
      else: lv.rows[lv.selectedRow].value
    lv.call(Key.Right, valR)
  of Key.Left:
    lv.colCursor = max(lv.colCursor - 1, 0)
    let valL =
      if lv.rows.len == 0 or lv.selectedRow < 0 or
         lv.selectedRow >= lv.rows.len: ""
      else: lv.rows[lv.selectedRow].value
    lv.call(Key.Left, valL)
  of Key.Enter:
    let valE =
      if lv.rows.len == 0 or lv.selectedRow < 0 or
         lv.selectedRow >= lv.rows.len: ""
      else: lv.rows[lv.selectedRow].value
    lv.call("enter", valE)
  of Tab: lv.focus = false
  else:
    if key in forbiddenKeyBind: discard
    elif lv.keyEvents.hasKey(key):
      # `lv.selected` indexes lv.rows[lv.selectedRow] unconditionally; if the
      # list is empty (or selectedRow is stale) that's an out-of-bounds.
      # Pass "" instead so user-registered key handlers can fire on an
      # empty list without crashing the dispatcher.
      let val =
        if lv.rows.len == 0 or lv.selectedRow < 0 or
           lv.selectedRow >= lv.rows.len: ""
        else: lv.rows[lv.selectedRow].value
      lv.call(key, val)
  lv.render()
  sleep(lv.rpms)
  lv.call("postupdate", $key)


method onControl*(lv: ListView): void =
  if lv.visibility == false: 
    lv.cursor = 0
    lv.rowCursor = 0
    lv.colCursor = 0
    return
  
  
  lv.focus = true
  while lv.focus:
    var key = getKeyWithTimeout(lv.rpms)
    case key
    of Key.Mouse:  # Handle mouse events in onControl
      if lv.mouseEnabled:
        let mouseInfo = getMouse()
        lv.handleMouseEvent(mouseInfo)
    else:
      lv.onUpdate(key)


method wg*(lv: ListView): ref BaseWidget = lv


proc enableTextOverlay*(lv: ListView) =
  ## Opt the list view into wide-glyph-correct rendering. Sets
  ## `textOverlay` and wires a `postDisplay` closure that writes each
  ## visible row's text directly to stdout, clipped by visual width.
  ## Selected rows are highlighted via ANSI inverse video (`\e[7m`) —
  ## simple and color-scheme-agnostic. The `selectionStyle` field is
  ## ignored in overlay mode; users wanting a custom selection visual
  ## can replace `postDisplay` themselves.
  lv.textOverlay = true
  lv.postDisplay = proc(wg: ref BaseWidget) =
    let lv = ListView(wg)
    if not lv.illwillInit or not lv.textOverlay: return
    let widthCells = max(1, lv.x2 - lv.x1)
    let baseRow    = lv.posY + 1 + 1
    let baseCol    = lv.x1 + 1
    let viewport   = max(0, lv.size)
    let blank      = " ".repeat(widthCells)
    # ----- shortcut: empty list ------------------------------------------
    # illwill's render only flushes buffer cells that *changed*. The
    # overlay writes via stdout, so its cells stay live on the terminal
    # until we explicitly overwrite them. When rows are empty (e.g. user
    # just hit /new) we must paint spaces across the whole viewport;
    # otherwise the previous conversation stays on screen.
    let rows = lv.vrows()
    if lv.rows.len == 0 or rows.len == 0:
      for j in 0 ..< viewport:
        stdout.write("\e[", baseRow + j, ";", baseCol, "f", blank)
      return
    # ----- normal path ---------------------------------------------------
    # Mirror the EXACT same scroll math as `method render*` so the
    # overlay paints the rows that the render pass cleared — otherwise
    # we draw to cells render didn't touch (stale content stays) and
    # leave cells render did touch blank (the "gaps" bug).
    let filteredSize = min(lv.size, rows.len)
    var rowStart = max(0, lv.rowCursor)
    var rowEnd = rowStart + filteredSize
    if rowEnd > filteredSize:
      rowStart = max(0, lv.rowCursor - filteredSize)
      rowEnd = max(lv.rowCursor + 1, filteredSize)
    rowEnd = min(rowEnd, rows.len - 1)
    var i = 0
    for idx in rowStart..rowEnd:
      let row = rows[idx]
      let clipped = clipToVisualWidth(row.text, widthCells)
      let used = visualWidth(clipped)
      let pad = if used < widthCells: " ".repeat(widthCells - used) else: ""
      let screenRow = baseRow + i
      if row.selected:
        stdout.write("\e[", screenRow, ";", baseCol, "f\e[7m",
                     clipped, pad, "\e[0m")
      else:
        # Trailing `\e[0m` so an unclosed CSI inside the row (a partial
        # `\e[31m...` with no reset) can't carry color into the padding,
        # the next row, or the right border. With visualWidth fixed to
        # skip CSI bytes, `pad` is now the correct cell count.
        stdout.write("\e[", screenRow, ";", baseCol, "f", clipped, pad,
                     "\e[0m")
      inc i
    # Clear any unused row slots BELOW the painted rows — covers the
    # case where the new frame has fewer rows than the previous one
    # (a tool-result row went away, a chat got shorter, etc.) and the
    # stale overlay text would otherwise linger.
    while i < viewport:
      stdout.write("\e[", baseRow + i, ";", baseCol, "f", blank)
      inc i


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
  lv.resize()


# TODO:
# add listRow at position

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




