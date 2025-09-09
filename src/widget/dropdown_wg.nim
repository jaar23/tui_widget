import illwill, base_wg, sequtils, tables, os
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
    events*: Table[string, EventFn[Dropdown]]
    keyEvents*: Table[Key, EventFn[Dropdown]]
    
  Dropdown* = ref DropdownObj

const forbiddenKeyBind = {Key.Tab, Key.None, Key.Up, Key.Down, Key.Enter, Key.Escape}

# proc help(dd: Dropdown, args: varargs[string]): void

proc on*(dd: Dropdown, key: Key, fn: EventFn[Dropdown]) {.raises: [EventKeyError]}

proc newDropdownOption*(text, value: string, visible: bool = true): DropdownOption =
  result = DropdownOption(
    text: text,
    value: value,
    visible: visible
  )

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
    statusbarText: "[↑↓] Navigate [Enter] Select [Esc] Close",
    events: initTable[string, EventFn[Dropdown]](),
    keyEvents: initTable[Key, EventFn[Dropdown]]()
  )
  
  result.dropdownHeight = min(maxVisibleOptions, options.len) + 2 # +2 for borders
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


proc renderDropdownBox(dd: Dropdown) =
  # Clear the main dropdown box
  dd.tb.fill(dd.posX, dd.posY, dd.width, dd.height, dd.bg, dd.fg, " ")
  
  # Render border with focus highlighting
  if dd.style.border:
    if dd.focus:
      # Draw focused border with different style/color
      dd.tb.drawRect(dd.width, dd.height, dd.posX, dd.posY, doubleStyle = dd.focus) # Highlight border color
    else:
      dd.tb.drawRect(dd.width, dd.height, dd.posX, dd.posY)
  
  # Render title
  dd.renderTitle()
  
  # Render selected value or placeholder
  let displayText = if dd.selectedIndex >= 0 and dd.selectedIndex < dd.options.len:
    dd.options[dd.selectedIndex].text
  else:
    dd.placeholder
    
  let textY = dd.posY + dd.paddingY1 + (if dd.title != "": 1 else: 0)
  let availableWidth = dd.width - dd.paddingX1 - dd.paddingX2 - 2 # -2 for dropdown arrow
  let truncatedText = if displayText.len > availableWidth:
    displayText[0..<availableWidth-3] & "..." 
  else: 
    displayText
    
  # Render text with focus-aware colors
  if dd.focus:
    dd.tb.write(dd.posX + dd.paddingX1, textY, bgNone, fgWhite, truncatedText, resetStyle)
  else:
    dd.tb.write(dd.posX + dd.paddingX1, textY, bgNone, fgWhite, truncatedText, resetStyle)
    
  # Render dropdown arrow with focus colors
  let arrow = if dd.expanded: "▲" else: "▼"
  if dd.focus:
    dd.tb.write(dd.posX + dd.width - dd.paddingX2 - 1, textY, bgNone, fgWhite, arrow, resetStyle)
  else:
    dd.tb.write(dd.posX + dd.width - dd.paddingX2 - 1, textY, bgNone, fgWhite, arrow, resetStyle)


proc renderDropdownList(dd: Dropdown) =
  if not dd.expanded or dd.options.len == 0:
    return
    
  let visOpts = dd.visibleOptions()
  let listY = dd.posY + dd.height
  let listHeight = min(dd.maxVisibleOptions, visOpts.len)
  
  # Clear dropdown list area
  dd.tb.fill(dd.posX, listY, dd.width, listY + listHeight + 1, bgBlack, fgWhite, " ")
  
  # Draw dropdown list border with focus highlighting
  if dd.focus:
    dd.tb.drawRect(dd.width, listHeight + 2, dd.posX, listY) # Highlight border color
  else:
    dd.tb.drawRect(dd.width, listHeight + 2, dd.posX, listY)
  
  # Render options - fixed selection logic
  for i in 0..<min(listHeight, visOpts.len):
    let optionY = listY + 1 + i
    let actualIndex = dd.options.find(visOpts[i])  # Find actual index in full options
    let isSelected = dd.selectedIndex == actualIndex
    
    let optionText = if visOpts[i].text.len > dd.width - 4:
      visOpts[i].text[0..<dd.width-7] & "..."
    else:
      visOpts[i].text
    
    if isSelected and dd.focus:
      dd.tb.write(dd.posX + 1, optionY, bgBlue, fgWhite, optionText, resetStyle)
    else:
      dd.tb.write(dd.posX + 1, optionY, bgBlack, fgWhite, optionText, resetStyle)


proc clearDropdownList(dd: Dropdown) =
  if dd.dropdownHeight > 0:
    let listY = dd.posY + dd.height
    dd.tb.fill(dd.posX, listY, dd.width, listY + dd.dropdownHeight, bgNone, fgWhite, " ")

proc renderStatusBar(dd: Dropdown) =
  if dd.statusbar:
    if dd.events.hasKey("statusbar"):
      dd.call("statusbar")
    else:
      let statusText = if dd.expanded: "[↑↓] Navigate [Enter] Select " else: "[Space] Open"
      dd.tb.write(dd.x1, dd.height, bgWhite, fgBlack, statusText, resetStyle)

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
  dd.renderBorder()
  dd.renderDropdownBox()
  dd.renderDropdownList()
  dd.renderStatusBar()
  dd.tb.display()

method onUpdate*(dd: Dropdown, key: Key) =
  dd.call("preupdate", $key)
  
  case key
  of Key.None: dd.render()
  of Key.Up:
    if dd.expanded and dd.options.len > 0:
      let visOpts = dd.visibleOptions()
      if visOpts.len > 0:
        # Navigate within visible options only
        let currentVisIndex = visOpts.find(dd.options[dd.selectedIndex])
        let newVisIndex = if currentVisIndex <= 0: visOpts.len - 1 else: currentVisIndex - 1
        dd.selectedIndex = dd.options.find(visOpts[newVisIndex])
  of Key.Down:
    if dd.expanded and dd.options.len > 0:
      let visOpts = dd.visibleOptions()
      if visOpts.len > 0:
        # Navigate within visible options only
        let currentVisIndex = visOpts.find(dd.options[dd.selectedIndex])
        let newVisIndex = if currentVisIndex >= visOpts.len - 1: 0 else: currentVisIndex + 1
        dd.selectedIndex = dd.options.find(visOpts[newVisIndex])
  of Key.Enter:
    if dd.expanded:
      # Select current option and close dropdown
      dd.expanded = false
      dd.clearDropdownList()
      if dd.selectedIndex >= 0 and dd.selectedIndex < dd.options.len:
        dd.call("select", dd.options[dd.selectedIndex].value, dd.options[dd.selectedIndex].text)
    else:
      # Open dropdown if closed
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
  if dd.visibility == false: 
    dd.expanded = false
    return
    
  dd.focus = true
  while dd.focus:
    var key = getKeyWithTimeout(dd.rpms)
    dd.onUpdate(key)

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
  ## Select option by its value, returns true if found
  for i, option in dd.options:
    if option.value == value:
      dd.selectedIndex = i
      return true
  return false

proc selectByText*(dd: Dropdown, text: string): bool =
  ## Select option by its text, returns true if found
  for i, option in dd.options:
    if option.text == text:
      dd.selectedIndex = i
      return true
  return false

proc setOptionVisibility*(dd: Dropdown, value: string, visible: bool) =
  ## Set visibility of an option by value
  for option in dd.options.mitems:
    if option.value == value:
      option.visible = visible
      break
  dd.resize()