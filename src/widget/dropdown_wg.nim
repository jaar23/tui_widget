import illwill, base_wg, sequtils, strutils, tables, os, unicode
import threading/channels

type
  DropdownOption* = object
    text*: string
    value*: string
    visible*: bool = true

  DropdownObj* = object of BaseWidget
    options*: seq[DropdownOption]
    selectedIndex*: int = 0
    expanded*: bool = false
    placeholder*: string = "Select an option..."
    maxVisibleOptions*: int = 5
    dropdownHeight*: int = 0
    savedList*: seq[TerminalChar]
    events*: Table[string, EventFn[Dropdown]]
    keyEvents*: Table[Key, EventFn[Dropdown]]

  Dropdown* = ref DropdownObj

const forbiddenKeyBind = {Key.Tab, Key.None, Key.Up, Key.Down, Key.Enter, Key.Escape}

proc on*(dd: Dropdown, key: Key, fn: EventFn[Dropdown]) {.raises: [EventKeyError]}

proc newDropdownOption*(text, value: string, visible: bool = true): DropdownOption =
  result = DropdownOption(text: text, value: value, visible: visible)

proc newDropdown*(px, py, w, h: int, id = "",
                  title = "", border = true, statusbar = true,
                  placeholder = "Select an option...",
                  options: seq[DropdownOption] = newSeq[DropdownOption](),
                  maxVisibleOptions = 5,
                  bgColor = bgNone, fgColor = fgWhite,
                  tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py + 10)): Dropdown =
  let padding = if border: 1 else: 0
  let statusbarSize = 1
  let style = WidgetStyle(
    paddingX1: padding,
    paddingX2: padding,
    paddingY1: padding,
    paddingY2: padding,
    border: border,
    fgColor: fgColor,
    bgColor: bgColor
  )
  result = Dropdown(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    title: title,
    options: options,
    placeholder: placeholder,
    maxVisibleOptions: maxVisibleOptions,
    selectedIndex: if options.len > 0: 0 else: -1,
    expanded: false,
    size: h - py - style.paddingY2 - style.paddingY1 - statusbarSize,
    tb: tb,
    style: style,
    statusbar: statusbar,
    events: initTable[string, EventFn[Dropdown]](),
    keyEvents: initTable[Key, EventFn[Dropdown]]()
  )
  result.dropdownHeight = min(maxVisibleOptions, options.len) + 2
  result.channel = newChan[WidgetBgEvent]()
  result.keepOriginalSize()


proc newDropdown*(px, py: int, w, h: WidgetSize, id = "",
                  title = "", border = true, statusbar = true,
                  placeholder = "Select an option...",
                  options: seq[DropdownOption] = newSeq[DropdownOption](),
                  maxVisibleOptions = 5,
                  bgColor = bgNone, fgColor = fgWhite,
                  tb = newTerminalBuffer(w.toInt + 2, h.toInt + py + 10)): Dropdown =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newDropdown(px, py, width, height, id, title, border, statusbar,
                     placeholder, options, maxVisibleOptions, bgColor, fgColor, tb)


proc visibleOptions(dd: Dropdown): seq[DropdownOption] =
  dd.options.filter(proc(opt: DropdownOption): bool = opt.visible)


# ---------------------------------------------------------------------------
# Clear the expanded-list region on collapse. Resetting the cells to bgNone
# lets the next app.render() cycle repaint any underlying widgets cleanly;
# without it, residual bgBlack/fill cells linger in rows not covered by any
# other widget.
# ---------------------------------------------------------------------------

proc clearListArea(dd: Dropdown) =
  let listY = dd.height
  let listBottom = min(listY + dd.maxVisibleOptions + 2, terminalHeight() - 1)
  let xEnd = min(dd.width, terminalWidth() - 1)
  let blank = TerminalChar(ch: " ".runeAt(0), fg: fgNone, bg: bgNone, style: {})
  for y in listY..listBottom:
    for x in dd.posX..xEnd:
      dd.tb[x, y] = blank


proc renderDropdownBox(dd: Dropdown) =
  # Clear the main dropdown box area
  dd.tb.fill(dd.posX, dd.posY, dd.width, dd.height, dd.bg, dd.fg, " ")

  # Draw border (single or double depending on focus)
  if dd.style.border:
    dd.tb.drawRect(dd.width, dd.height, dd.posX, dd.posY, doubleStyle = dd.focus)

  dd.renderTitle()

  # Selected value or placeholder
  let displayText =
    if dd.selectedIndex >= 0 and dd.selectedIndex < dd.options.len:
      dd.options[dd.selectedIndex].text
    else:
      dd.placeholder

  let textY = dd.posY + dd.paddingY1 + (if dd.title != "": 1 else: 0)
  let availableWidth = dd.x2 - dd.x1 - 2  # -2 for the arrow char + gap
  let truncatedText =
    if displayText.len > availableWidth: displayText[0..<availableWidth - 3] & "..."
    else: displayText

  dd.tb.write(dd.x1, textY, dd.bg, dd.fg, truncatedText, resetStyle)

  # Arrow — fixed: use x2-1, not posX+width-padding-1
  let arrow = if dd.expanded: "▲" else: "▼"
  dd.tb.write(dd.x2 - 1, textY, dd.bg, dd.fg, arrow, resetStyle)


proc renderDropdownList(dd: Dropdown) =
  if not dd.expanded or dd.options.len == 0:
    return

  let visOpts = dd.visibleOptions()
  # Fixed: height is an absolute coordinate, NOT a relative offset
  let listY = dd.height
  let listCount = min(dd.maxVisibleOptions, visOpts.len)

  # Clear and border the list box
  dd.tb.fill(dd.posX, listY, dd.width, listY + listCount + 1, bgBlack, fgWhite, " ")
  dd.tb.drawRect(dd.width, listY + listCount + 1, dd.posX, listY)

  # Render visible options
  for i in 0..<listCount:
    let optionY = listY + 1 + i
    let actualIndex = dd.options.find(visOpts[i])
    let isSelected = dd.selectedIndex == actualIndex

    let optionText =
      if visOpts[i].text.len > dd.x2 - dd.x1 - 2:
        visOpts[i].text[0..<dd.x2 - dd.x1 - 5] & "..."
      else:
        visOpts[i].text

    if isSelected:
      dd.tb.write(dd.x1, optionY, bgBlue, fgWhite, optionText, resetStyle)
    else:
      dd.tb.write(dd.x1, optionY, bgBlack, fgWhite, optionText, resetStyle)


proc clearDropdownList(dd: Dropdown) =
  # Clear the list area so next app.render() can repaint underlying widgets
  # cleanly without leftover bgBlack cells.
  dd.clearListArea()


proc renderStatusBar(dd: Dropdown) =
  if dd.statusbar:
    if dd.events.hasKey("statusbar"):
      dd.call("statusbar")
    else:
      let statusText =
        if dd.expanded: "[↑↓] Navigate [Enter] Select "
        else: "[Space]/[Enter] Open"
      # Fixed: write at height-1 (inside border), not height (the border row)
      let innerWidth = dd.x2 - dd.x1
      let padded = statusText & " ".repeat(max(0, innerWidth - statusText.len))
      dd.tb.write(dd.x1, dd.height - 1, bgWhite, fgBlack, padded, resetStyle)


proc on*(dd: Dropdown, event: string, fn: EventFn[Dropdown]) =
  dd.events[event] = fn


proc on*(dd: Dropdown, key: Key, fn: EventFn[Dropdown]) {.raises: [EventKeyError]} =
  if key in forbiddenKeyBind:
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  dd.keyEvents[key] = fn


proc call*(dd: Dropdown, event: string, args: varargs[string]) =
  if dd.events.hasKey(event):
    let fn = dd.events[event]
    fn(dd, args)


proc call(dd: Dropdown, key: Key, args: varargs[string]) =
  if dd.keyEvents.hasKey(key):
    let fn = dd.keyEvents[key]
    fn(dd, args)


method poll*(dd: Dropdown) =
  var widgetEv: WidgetBgEvent
  if dd.channel.tryRecv(widgetEv):
    dd.call(widgetEv.event, widgetEv.args)
    dd.render()


method render*(dd: Dropdown) =
  if not dd.illwillInit: return
  # Note: renderBorder() is NOT called here; renderDropdownBox handles the border
  dd.renderDropdownBox()
  dd.renderDropdownList()
  dd.renderStatusBar()
  if not dd.suppressDisplay: dd.tb.display()


method onUpdate*(dd: Dropdown, key: Key) =
  dd.call("preupdate", $key)

  case key
  of Key.None: dd.render()
  of Key.Up:
    if dd.expanded and dd.options.len > 0:
      let visOpts = dd.visibleOptions()
      if visOpts.len > 0:
        let currentVisIndex = visOpts.find(dd.options[dd.selectedIndex])
        let newVisIndex = if currentVisIndex <= 0: visOpts.len - 1 else: currentVisIndex - 1
        dd.selectedIndex = dd.options.find(visOpts[newVisIndex])
  of Key.Down:
    if dd.expanded and dd.options.len > 0:
      let visOpts = dd.visibleOptions()
      if visOpts.len > 0:
        let currentVisIndex = visOpts.find(dd.options[dd.selectedIndex])
        let newVisIndex = if currentVisIndex >= visOpts.len - 1: 0 else: currentVisIndex + 1
        dd.selectedIndex = dd.options.find(visOpts[newVisIndex])
  of Key.Enter:
    if dd.expanded:
      dd.expanded = false
      dd.clearDropdownList()
      if dd.selectedIndex >= 0 and dd.selectedIndex < dd.options.len:
        dd.call("select", dd.options[dd.selectedIndex].value, dd.options[dd.selectedIndex].text)
    else:
      dd.expanded = true
  of Key.Escape:
    if dd.expanded:
      dd.expanded = false
      dd.clearDropdownList()
    else:
      dd.focus = false
  of Key.Space:
    dd.expanded = not dd.expanded
    if not dd.expanded:
      dd.clearDropdownList()
  of Key.Tab:
    dd.expanded = false
    dd.clearDropdownList()
    dd.focus = false
  else:
    if key notin forbiddenKeyBind and dd.keyEvents.hasKey(key):
      dd.call(key, if dd.selectedIndex >= 0: dd.options[dd.selectedIndex].value else: "")

  dd.render()
  sleep(dd.rpms)
  dd.call("postupdate", $key)


method onControl*(dd: Dropdown): void =
  if not dd.visibility:
    dd.expanded = false
    return
  dd.focus = true
  while dd.focus:
    var key = getKeyWithTimeout(dd.rpms)
    dd.onUpdate(key)


method contains*(dd: Dropdown, x, y: int): bool =
  ## Include the expanded list area in hit-testing so option clicks reach us.
  if x < dd.posX or x > dd.width: return false
  if y >= dd.posY and y <= dd.height: return true
  if dd.expanded:
    let listBottom = dd.height + min(dd.maxVisibleOptions, dd.options.len) + 1
    return y > dd.height and y <= listBottom
  return false


method onMouseEvent*(dd: Dropdown, mouseInfo: MouseInfo) =
  if mouseInfo.button == MouseButton.mbLeft and mouseInfo.action == MouseButtonAction.mbaPressed:
    if dd.expanded:
      # Detect click on a specific option row in the expanded list
      let visOpts = dd.visibleOptions()
      let listCount = min(dd.maxVisibleOptions, visOpts.len)
      let firstOptionRow = dd.height + 1
      let lastOptionRow = dd.height + listCount
      if mouseInfo.y >= firstOptionRow and mouseInfo.y <= lastOptionRow:
        let optIdx = mouseInfo.y - firstOptionRow
        if optIdx < visOpts.len:
          dd.selectedIndex = dd.options.find(visOpts[optIdx])
      # Either an option was clicked, or the box itself was clicked while
      # expanded — collapse and fire select with the current selectedIndex.
      dd.expanded = false
      dd.clearDropdownList()
      if dd.selectedIndex >= 0 and dd.selectedIndex < dd.options.len:
        dd.call("select", dd.options[dd.selectedIndex].value, dd.options[dd.selectedIndex].text)
    else:
      dd.expanded = true
    dd.render()
  elif mouseInfo.scroll and dd.expanded and dd.options.len > 0:
    let visOpts = dd.visibleOptions()
    if visOpts.len > 0:
      let currentVisIndex = visOpts.find(dd.options[dd.selectedIndex])
      if mouseInfo.scrollDir == ScrollDirection.sdUp:
        let newVisIndex = if currentVisIndex <= 0: visOpts.len - 1 else: currentVisIndex - 1
        dd.selectedIndex = dd.options.find(visOpts[newVisIndex])
      elif mouseInfo.scrollDir == ScrollDirection.sdDown:
        let newVisIndex = if currentVisIndex >= visOpts.len - 1: 0 else: currentVisIndex + 1
        dd.selectedIndex = dd.options.find(visOpts[newVisIndex])
    dd.render()
  if not dd.onMouse.isNil:
    dd.onMouse(dd, mouseInfo)

method wg*(dd: Dropdown): ref BaseWidget = dd


method resize*(dd: Dropdown) =
  dd.dropdownHeight = min(dd.maxVisibleOptions, dd.options.len) + 2


# Getters and setters

proc selectedValue*(dd: Dropdown): string =
  if dd.selectedIndex >= 0 and dd.selectedIndex < dd.options.len:
    return dd.options[dd.selectedIndex].value
  return ""

proc selectedText*(dd: Dropdown): string =
  if dd.selectedIndex >= 0 and dd.selectedIndex < dd.options.len:
    return dd.options[dd.selectedIndex].text
  return ""

proc `selectedIndex=`*(dd: Dropdown, index: int) =
  if index >= 0 and index < dd.options.len:
    dd.selectedIndex = index

proc `options=`*(dd: Dropdown, options: seq[DropdownOption]) =
  dd.options = options
  dd.selectedIndex = if options.len > 0: 0 else: -1
  dd.resize()

proc addOption*(dd: Dropdown, option: DropdownOption) =
  dd.options.add(option)
  if dd.selectedIndex == -1:
    dd.selectedIndex = 0
  dd.resize()

proc removeOption*(dd: Dropdown, index: int) =
  if index >= 0 and index < dd.options.len:
    dd.options.delete(index)
    if dd.selectedIndex >= dd.options.len:
      dd.selectedIndex = max(0, dd.options.len - 1)
    if dd.options.len == 0:
      dd.selectedIndex = -1
  dd.resize()

proc clearOptions*(dd: Dropdown) =
  dd.options = @[]
  dd.selectedIndex = -1
  dd.expanded = false
  dd.resize()

proc `onSelect=`*(dd: Dropdown, selectEv: EventFn[Dropdown]) =
  dd.on("select", selectEv)

method resetCursor*(dd: Dropdown) =
  dd.selectedIndex = if dd.options.len > 0: 0 else: -1
  dd.expanded = false

proc selectByValue*(dd: Dropdown, value: string): bool =
  for i, option in dd.options:
    if option.value == value:
      dd.selectedIndex = i
      return true
  return false

proc selectByText*(dd: Dropdown, text: string): bool =
  for i, option in dd.options:
    if option.text == text:
      dd.selectedIndex = i
      return true
  return false

proc setOptionVisibility*(dd: Dropdown, value: string, visible: bool) =
  for option in dd.options.mitems:
    if option.value == value:
      option.visible = visible
      break
  dd.resize()
