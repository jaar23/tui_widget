import illwill, base_wg, os, std/wordwrap, strutils, options, tables, algorithm, sequtils, input_box_wg, streams, display_wg
import threading/channels
import yaml

type
  YamlNodeData = object
    key: string
    value: YamlNode
    expanded: bool
    level: int
    visible: bool
    lineIndex: int
    isLastChild: bool

  YamlViewer* = ref YamlViewerObj

  YamlViewerObj* = object of BaseWidget
    rootNode: YamlNode
    nodes: seq[YamlNodeData]
    visibleNodes: seq[int]  # indices of visible nodes
    selectedNode: int
    searchText: string
    searchResults: seq[int]  # indices of nodes matching search
    currentSearchIndex: int
    filePath: string
    events*: Table[string, EventFn[YamlViewer]]
    keyEvents*: Table[Key, EventFn[YamlViewer]]
    searchMode: bool
    searchInput: string
    text: string
    horizontalOffset: int
    showFormattedYaml: bool

proc help(yv: YamlViewer, args: varargs[string]): void
proc on*(yv: YamlViewer, key: Key, fn: EventFn[YamlViewer]) {.raises: [EventKeyError].}
proc buildNodeTree(yv: YamlViewer): void
proc updateVisibleNodes(yv: YamlViewer): void
proc ensureNodeVisible(yv: YamlViewer, nodeIndex: int): void
proc renderStatusbar(yv: YamlViewer): void
proc yamlNodeToString(yv: YamlViewer, node: YamlNode, indent: int): string 

# Allow ShiftW for binding
const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.None, Key.Up,
                          Key.Down, Key.PageUp, Key.PageDown, Key.Home,
                          Key.End, Key.Left, Key.Right}

proc newYamlViewer*(px, py, w, h: int, id = "";
                    title: string = "", yamlData: string = "", filePath: string = "",
                    border: bool = true, statusbar = true,
                    bgColor: BackgroundColor = bgNone,
                    fgColor: ForegroundColor = fgWhite,
                    tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): YamlViewer =
  let padding = if border: 1 else: 0
  let statusbarSize = if statusbar: 1 else: 0
  let style = WidgetStyle(
    paddingX1: padding,
    paddingX2: padding,
    paddingY1: padding,
    paddingY2: padding,
    border: border,
    fgColor: fgColor,
    bgColor: bgColor
  )
  result = (YamlViewer)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    size: h - statusbarSize - py - (padding * 2),
    statusbarSize: statusbarSize,
    title: title,
    statusbar: statusbar,
    tb: tb,
    style: style,
    filePath: filePath,
    selectedNode: 0,
    events: initTable[string, EventFn[YamlViewer]](),
    keyEvents: initTable[Key, EventFn[YamlViewer]]()
  )
  result.helpText = " [Enter] toggle expand/collapse\n" &
                    " [←/→]   scroll left/right\n" &
                    " [/]     search\n" &
                    " [n]     next search result\n" &
                    " [N]     previous search result\n" &
                    " [T]     toggle formatted YAML view\n" &
                    " [?]     for help\n" &
                    " [Tab]   to go next widget\n" & 
                    " [Esc]   to exit this window"
 
  result.channel = newChan[WidgetBgEvent]()
  result.on(Key.QuestionMark, help)
  result.keepOriginalSize()
  result.text = yamlData  
  
  # Parse initial YAML data
  if yamlData.len > 0:
    try:
      var s = newStringStream(yamlData)
      result.rootNode = loadAs[YamlNode](s)
      result.buildNodeTree()
    except:
      result.text = "Invalid YAML data"
  elif filePath.len > 0 and fileExists(filePath):
    try:
      var s = newFileStream(filePath)
      result.rootNode = loadAs[YamlNode](s)
      s.close()
      result.buildNodeTree()
    except:
      result.text = "Invalid YAML file"


proc newYamlViewer*(id: string): YamlViewer =
  var viewer = YamlViewer(
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
    events: initTable[string, EventFn[YamlViewer]](),
    keyEvents: initTable[Key, EventFn[YamlViewer]]()
  )

  viewer.helpText = " [Enter] toggle expand/collapse\n" &
                    " [←/→]   scroll left/right\n" &
                    " [/]     search\n" &
                    " [n]     next search result\n" &
                    " [N]     previous search result\n" &
                    " [T]     toggle formatted YAML view\n" &
                    " [?]     for help\n" &
                    " [Tab]   to go next widget\n" & 
                    " [Esc]   to exit this window"
  viewer.on(Key.QuestionMark, help)
  viewer.channel = newChan[WidgetBgEvent]()
  viewer.text = "" 
  return viewer


proc buildNodeTree(yv: YamlViewer) =
  yv.nodes = @[]
  yv.visibleNodes = @[]
  
  if yv.rootNode.isNil:
    return
  
  proc traverse(node: YamlNode, key: string, level: int, parentExpanded: bool) =
    let nodeIndex = yv.nodes.len
    yv.nodes.add(YamlNodeData(
      key: key,
      value: node,
      expanded: node.kind in {yMapping, ySequence} and level < 1,  # Auto-expand first level
      level: level,
      visible: parentExpanded,
      lineIndex: 0,
      isLastChild: false
    ))
    
    if parentExpanded:
      yv.visibleNodes.add(nodeIndex)
    
    if node.kind == yMapping:
      let pairs = node.fields.pairs.toSeq()
      for i, (k, v) in pairs:
        let isLast = (i == pairs.high)
        let childExpanded = parentExpanded and yv.nodes[nodeIndex].expanded
        traverse(v, $k, level + 1, childExpanded)
        if isLast and yv.nodes.len > 0:
          yv.nodes[yv.nodes.high].isLastChild = true
          
    elif node.kind == ySequence:
      for i, item in node.elems:
        let isLast = (i == node.elems.len - 1)
        let childExpanded = parentExpanded and yv.nodes[nodeIndex].expanded
        traverse(item, "[" & $i & "]", level + 1, childExpanded)
        if isLast and yv.nodes.len > 0:
          yv.nodes[yv.nodes.high].isLastChild = true
  
  traverse(yv.rootNode, "root", 0, true)
  yv.updateVisibleNodes()


proc updateVisibleNodes(yv: YamlViewer) =
  yv.visibleNodes = @[]
  for i, node in yv.nodes:
    if node.visible:
      yv.nodes[i].lineIndex = yv.visibleNodes.len
      yv.visibleNodes.add(i)
    else:
      yv.nodes[i].lineIndex = -1


proc toggleNode(yv: YamlViewer, nodeIndex: int) =
  if yv.nodes[nodeIndex].value.kind notin {yMapping, ySequence}:
    return
  
  yv.nodes[nodeIndex].expanded = not yv.nodes[nodeIndex].expanded
  
  # Update visibility of children recursively
  proc updateChildVisibility(startIndex: int, parentLevel: int, shouldShow: bool) =
    var i = startIndex + 1
    while i < yv.nodes.len and yv.nodes[i].level > parentLevel:
      if yv.nodes[i].level == parentLevel + 1:
        # Direct child
        yv.nodes[i].visible = shouldShow
        if shouldShow and yv.nodes[i].expanded and yv.nodes[i].value.kind in {yMapping, ySequence}:
          # Recursively show grandchildren if this child is expanded
          updateChildVisibility(i, yv.nodes[i].level, true)
        elif not shouldShow:
          # Hide all descendants
          updateChildVisibility(i, yv.nodes[i].level, false)
      inc(i)
  
  updateChildVisibility(nodeIndex, yv.nodes[nodeIndex].level, yv.nodes[nodeIndex].expanded)
  yv.updateVisibleNodes()


proc formatNodeValue(yv: YamlViewer, node: YamlNodeData): string =
  case node.value.kind
  of yScalar:
    let tag = $node.value.tag
    let content = node.value.content
    # Debugging: uncomment next line to see tag values
    # echo "Tag: ", tag, " Content: '", content, "'"

    case tag
    of "tag:yaml.org,2002:str":
      result = "\"" & content & "\""
    of "tag:yaml.org,2002:int", "tag:yaml.org,2002:float":
      result = content
    of "tag:yaml.org,2002:bool":
      result = content
    of "tag:yaml.org,2002:null":
      result = "null"
    else:
      # Fallback: try to render the scalar safely
      try:
        result = content
      except:
        result = "<invalid scalar>"
  of yMapping:
    result = if node.expanded: "{...}" else: "{...} (" & $node.value.fields.len & " items)"
  of ySequence:
    result = if node.expanded: "[...]" else: "[...] (" & $node.value.elems.len & " items)"


proc renderNode(yv: YamlViewer, nodeIndex: int, lineIndex: int): string =
  let node = yv.nodes[nodeIndex]
  var prefix = ""
  
  # Add indentation
  for i in 1..<node.level:
    prefix.add("  ")
  
  # Add tree structure
  if node.level > 0:
    if node.isLastChild:
      prefix.add("`- ")
    else:
      prefix.add("|- ")
  
  # Add expand/collapse indicator
  if node.value.kind in {yMapping, ySequence}:
    if node.expanded:
      prefix.add("- ")
    else:
      prefix.add("+ ")
  else:
    prefix.add("  ")
  
  # Format the node
  var fullLine = ""
  if node.key == "root":
    fullLine = prefix & "(root) " & yv.formatNodeValue(node)
  else:
    var key = node.key
    key = key.replace("!<?>", "")
    fullLine = prefix & key & ": " & yv.formatNodeValue(node)
  
  # Add selection indicator
  if nodeIndex == yv.selectedNode:
    fullLine = "> " & fullLine
  else:
    fullLine = "  " & fullLine
  
  # Apply horizontal scrolling
  let availableWidth = yv.width - (if yv.border: 2 else: 0)
  if fullLine.len > yv.horizontalOffset:
    let endPos = min(fullLine.len, yv.horizontalOffset + availableWidth)
    result = fullLine[yv.horizontalOffset..<endPos]
  else:
    result = ""


proc search(yv: YamlViewer, searchText: string) =
  yv.searchText = searchText
  yv.searchResults = @[]
  yv.currentSearchIndex = 0
  
  if searchText.len == 0:
    return
  
  for i, node in yv.nodes:
    # Search in key
    if node.key.toLower().contains(searchText.toLower()):
      yv.searchResults.add(i)
    # Search in value (for scalar values)
    elif node.value.kind == yScalar:
      if node.value.content.toLower().contains(searchText.toLower()):
        yv.searchResults.add(i)
  
  if yv.searchResults.len > 0:
    yv.selectedNode = yv.searchResults[0]
    # Make sure the selected node is visible
    yv.ensureNodeVisible(yv.selectedNode)


proc onSearch(yv: YamlViewer) =
  yv.renderStatusBar()
  # Position search input at the top of the widget
  var input = newInputBox(yv.x1, yv.y1 + 1,  # Position at top, below title
                         yv.x2, yv.y1 + 3,    # Small height for input
                         title="search",
                         tb=yv.tb)
  let enterEv = proc(ib: InputBox, x: varargs[string]) =
    yv.search(ib.value)
    yv.searchInput = ib.value
    input.focus = false
    input.remove()
  
  # passing enter event as a callback
  input.illwillInit = true
  input.on("enter", enterEv)
  input.onControl()


proc ensureNodeVisible(yv: YamlViewer, nodeIndex: int) =
  # Expand all parents to make node visible
  var i = nodeIndex
  while i >= 0:
    if yv.nodes[i].level < yv.nodes[nodeIndex].level:
      yv.nodes[i].expanded = true
      yv.nodes[nodeIndex].visible = true
    dec(i)
  yv.updateVisibleNodes()


proc nextSearchResult(yv: YamlViewer) =
  if yv.searchResults.len == 0:
    return
  yv.currentSearchIndex = (yv.currentSearchIndex + 1) mod yv.searchResults.len
  yv.selectedNode = yv.searchResults[yv.currentSearchIndex]
  yv.ensureNodeVisible(yv.selectedNode)


proc prevSearchResult(yv: YamlViewer) =
  if yv.searchResults.len == 0:
    return
  yv.currentSearchIndex = (yv.currentSearchIndex - 1 + yv.searchResults.len) mod yv.searchResults.len
  yv.selectedNode = yv.searchResults[yv.currentSearchIndex]
  yv.ensureNodeVisible(yv.selectedNode)

proc help(yv: YamlViewer, args: varargs[string]) = 
  let wsize = ((yv.width - yv.posX).toFloat * 0.3).toInt()
  let hsize = ((yv.height - yv.posY).toFloat * 0.3).toInt()
  var display = newDisplay(yv.x2 - wsize, yv.y2 - hsize, 
                          yv.x2, yv.y2, title="help",
                          bgColor=bgWhite, fgColor=fgBlack,
                          tb=yv.tb, statusbar=false, 
                          enableHelp=false)
  var helpText: string = if yv.helpText == "":
    " [Enter] toggle expand/collapse\n" &
    " [←/→]   scroll left/right\n" &
    " [/]     search\n" &
    " [n]     next search result\n" &
    " [N]     previous search result\n" &
    " [T]     toggle formatted YAML view\n" &
    " [?]     for help\n" &
    " [Tab]   to go next widget\n" & 
    " [Esc]   to exit this window"
  else: yv.helpText
  display.text = helpText
  display.illwillInit = true
  yv.render()
  display.onControl()
  display.clear()


proc renderFormattedYaml(yv: YamlViewer, startLine: int): seq[string] =
  ## Display raw YAML text instead of rebuilding from nodes
  if yv.text.len == 0:
    return @["No YAML data"]
  
  let lines = yv.text.splitLines()  # Use splitLines instead of split('\n')
  
  # Apply horizontal scrolling to each line
  result = @[]
  let availableWidth = yv.width - (if yv.border: 2 else: 0)
  
  for line in lines:
    var displayLine = ""
    if line.len > yv.horizontalOffset:
      let endPos = min(line.len, yv.horizontalOffset + availableWidth)
      displayLine = line[yv.horizontalOffset..<endPos]
    result.add(displayLine)

proc renderStatusbar(yv: YamlViewer) =
  if yv.events.hasKey("statusbar"):
    yv.call("statusbar")
  else:
    var statusText = " "
    if yv.searchMode:
      statusText &= "Search: " & yv.searchInput
    elif yv.searchResults.len > 0:
      statusText &= "Match " & $(yv.currentSearchIndex + 1) & "/" & $yv.searchResults.len
    else:
      statusText &= "Line " & $(yv.nodes[yv.selectedNode].lineIndex + 1) & "/" & $yv.visibleNodes.len
      if yv.horizontalOffset > 0:
        statusText &= " | H-scroll: " & $yv.horizontalOffset
    
    let borderSize = if yv.border: 2 else: 1
    statusText = statusText & " ".repeat(yv.width - statusText.len - borderSize)
    yv.renderCleanRect(yv.x1, yv.height, yv.x1 + statusText.len - 1, yv.height)
    yv.tb.write(yv.x1, yv.height - 1, bgWhite, fgBlack, statusText, resetStyle)
    
    let q = "[?]"
    yv.tb.write(yv.x2 - len(q), yv.height - 1, bgWhite, fgBlack, q, resetStyle)
  
  if yv.border: yv.renderBorder()


method resize*(yv: YamlViewer) =
  let statusbarSize = if yv.statusbar: 1 else: 0
  yv.size = yv.height - statusbarSize - yv.posY - (yv.paddingY1 * 2)


proc on*(yv: YamlViewer, event: string, fn: EventFn[YamlViewer]) =
  yv.events[event] = fn


proc on*(yv: YamlViewer, key: Key, fn: EventFn[YamlViewer]) {.raises: [EventKeyError].} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  yv.keyEvents[key] = fn


method call*(yv: YamlViewer, event: string, args: varargs[string]) =
  if yv.events.hasKey(event):
    let fn = yv.events[event]
    fn(yv, args)


method call*(yv: YamlViewerObj, event: string, args: varargs[string]) =
  if yv.events.hasKey(event):
    let yvRef = yv.asRef()
    let fn = yv.events[event]
    fn(yvRef, args)


proc call(yv: YamlViewer, key: Key, args: varargs[string]) =
  if yv.keyEvents.hasKey(key):
    let fn = yv.keyEvents[key]
    fn(yv, args)


method render*(yv: YamlViewer) =
  if not yv.illwillInit: return
  yv.clear()
  yv.renderBorder()
  yv.renderTitle()
  
  var index = 1
  if yv.showFormattedYaml:
    # Render formatted YAML text
    let formattedLines = yv.renderFormattedYaml(yv.rowCursor)
    let endLine = min(yv.rowCursor + yv.size - 1, formattedLines.len - 1)
    
    if formattedLines.len > 0:
      for i in yv.rowCursor..endLine:
        if i < formattedLines.len:
          var line = formattedLines[i]
          if line.len > (yv.x2 - yv.x1):
            line = line[0..(min(yv.x2 - yv.x1, line.len))]
          yv.renderRow(line, index)
          inc index
  else:
    # Render tree view (existing code)
    if yv.visibleNodes.len > 0:
      let startLine = min(yv.rowCursor, yv.visibleNodes.len - 1)
      let endLine = min(startLine + yv.size - 1, yv.visibleNodes.len - 1)
      
      for i in startLine..endLine:
        let nodeIndex = yv.visibleNodes[i]
        var line = yv.renderNode(nodeIndex, i)
        if line.len > (yv.x2 - yv.x1):
          line = line[0..(min(yv.x2 - yv.x1, line.len))]
        yv.renderRow(line, index)
        inc index
  
  if yv.statusbar:
    yv.renderStatusbar()
  
  yv.tb.display()


method poll*(yv: YamlViewer) =
  var widgetEv: WidgetBgEvent
  if yv.channel.tryRecv(widgetEv):
    yv.call(widgetEv.event, widgetEv.args)
    yv.render()


method onUpdate*(yv: YamlViewer, key: Key) =
  if yv.visibility == false: 
    yv.rowCursor = 0
    yv.selectedNode = 0
    yv.horizontalOffset = 0
    return
  
  yv.call("preupdate", $key) 
  
  # Handle search input mode
  if yv.searchMode:
    yv.onSearch()
    yv.searchMode = false
  else:
    # Normal navigation mode
    case key
    of Key.None: discard
    of Key.T:  # Toggle between tree and formatted YAML view
      yv.showFormattedYaml = not yv.showFormattedYaml
      yv.rowCursor = 0  # Reset cursor position
      yv.horizontalOffset = 0  # Reset horizontal scroll
    of Key.Up:
      if yv.showFormattedYaml:
        # In formatted view, simple line navigation
        yv.rowCursor = max(0, yv.rowCursor - 1)
      else:
        # Existing tree navigation code
        if yv.visibleNodes.len > 0:
          let currentIndex = yv.nodes[yv.selectedNode].lineIndex
          if currentIndex > 0:
            yv.selectedNode = yv.visibleNodes[currentIndex - 1]
            # Adjust row cursor if needed
            if currentIndex <= yv.rowCursor:
              yv.rowCursor = max(0, yv.rowCursor - 1)
    of Key.Down:
      if yv.showFormattedYaml:
        # In formatted view, simple line navigation
        let totalLines = yv.yamlNodeToString(yv.rootNode, 0).split('\n').len
        let maxCursor = max(0, totalLines - yv.size)
        yv.rowCursor = min(maxCursor, yv.rowCursor + 1)
      else:
        # Existing tree navigation code
        if yv.visibleNodes.len > 0:
          let currentIndex = yv.nodes[yv.selectedNode].lineIndex
          if currentIndex < yv.visibleNodes.len - 1:
            yv.selectedNode = yv.visibleNodes[currentIndex + 1]
            # Adjust row cursor if needed
            if currentIndex >= yv.rowCursor + yv.size - 1:
              yv.rowCursor = min(yv.rowCursor + 1, max(0, yv.visibleNodes.len - yv.size))
    of Key.Left:
      # Horizontal scroll left (works in both modes)
      yv.horizontalOffset = max(0, yv.horizontalOffset - 4)
    of Key.Right:
      # Horizontal scroll right (works in both modes)
      yv.horizontalOffset += 4
    of Key.Enter:
      if not yv.showFormattedYaml:
        # Only toggle nodes in tree view
        yv.toggleNode(yv.selectedNode)
    of Key.Slash:  # Search
      yv.searchMode = true
    of Key.N:  # Next search result
      yv.nextSearchResult()
      # Reset horizontal scroll when jumping to search results
      yv.horizontalOffset = 0
      # Adjust row cursor to show selected node
      let selectedLineIndex = yv.nodes[yv.selectedNode].lineIndex
      if selectedLineIndex < yv.rowCursor:
        yv.rowCursor = selectedLineIndex
      elif selectedLineIndex >= yv.rowCursor + yv.size:
        yv.rowCursor = max(0, selectedLineIndex - yv.size + 1)
    of Key.P:  # Previous search result
      yv.prevSearchResult()
      # Reset horizontal scroll when jumping to search results
      yv.horizontalOffset = 0
      # Adjust row cursor to show selected node
      let selectedLineIndex = yv.nodes[yv.selectedNode].lineIndex
      if selectedLineIndex < yv.rowCursor:
        yv.rowCursor = selectedLineIndex
      elif selectedLineIndex >= yv.rowCursor + yv.size:
        yv.rowCursor = max(0, selectedLineIndex - yv.size + 1)
    of Key.PageUp:
      if yv.showFormattedYaml:
        yv.rowCursor = max(0, yv.rowCursor - yv.size)
      else:
        # Existing tree navigation code
        yv.rowCursor = max(0, yv.rowCursor - yv.size)
        if yv.visibleNodes.len > 0:
          let newIndex = max(0, yv.nodes[yv.selectedNode].lineIndex - yv.size)
          if newIndex < yv.visibleNodes.len:
            yv.selectedNode = yv.visibleNodes[newIndex]
    of Key.PageDown:
      if yv.showFormattedYaml:
        let totalLines = yv.yamlNodeToString(yv.rootNode, 0).split('\n').len
        let maxCursor = max(0, totalLines - yv.size)
        yv.rowCursor = min(maxCursor, yv.rowCursor + yv.size)
      else:
        # Existing tree navigation code
        yv.rowCursor = min(yv.rowCursor + yv.size, max(0, yv.visibleNodes.len - yv.size))
        if yv.visibleNodes.len > 0:
          let newIndex = min(yv.visibleNodes.len - 1, yv.nodes[yv.selectedNode].lineIndex + yv.size)
          if newIndex < yv.visibleNodes.len:
            yv.selectedNode = yv.visibleNodes[newIndex]
    of Key.Home:
      yv.rowCursor = 0
      yv.horizontalOffset = 0
      if not yv.showFormattedYaml and yv.visibleNodes.len > 0:
        yv.selectedNode = yv.visibleNodes[0]
    of Key.End:
      if yv.showFormattedYaml:
        let totalLines = yv.yamlNodeToString(yv.rootNode, 0).split('\n').len
        yv.rowCursor = max(0, totalLines - yv.size)
      else:
        yv.rowCursor = max(0, yv.visibleNodes.len - yv.size)
        if yv.visibleNodes.len > 0:
          yv.selectedNode = yv.visibleNodes[yv.visibleNodes.len - 1]
    of Key.Escape, Key.Tab:
      yv.focus = false
    else:
      if key in forbiddenKeyBind: discard
      elif yv.keyEvents.hasKey(key):
        yv.call(key, "")
  
  yv.render()
  yv.call("postupdate", $key)


method onControl*(yv: YamlViewer) =
  if yv.visibility == false: 
    yv.rowCursor = 0
    yv.selectedNode = 0
    return
  yv.focus = true
  yv.clear()
  while yv.focus:
    var key = getKeyWithTimeout(yv.rpms)
    yv.onUpdate(key)
    sleep(yv.rpms)


method wg*(yv: YamlViewer): ref BaseWidget = yv

proc text*(yv: YamlViewer): string = 
  if not yv.rootNode.isNil:
    return yv.yamlNodeToString(yv.rootNode, 0)
  return ""

proc yamlNodeToString(yv: YamlViewer, node: YamlNode, indent: int): string =
  let indentStr = "  ".repeat(indent)
  
  case node.kind
  of yScalar:
    return node.content
  of yMapping:
    var lines: seq[string] = @[]
    for key, value in node.fields.pairs:
      let keyStr = ($key).replace("!<?>")
      let valueStr = yv.yamlNodeToString(value, indent + 1)
      if value.kind in {yMapping, ySequence}:
        lines.add(indentStr & keyStr & ":")
        lines.add(valueStr)
      else:
        lines.add(indentStr & keyStr & ": " & valueStr)
    return lines.join("\n")
  of ySequence:
    var lines: seq[string] = @[]
    for item in node.elems:
      let itemStr = yv.yamlNodeToString(item, indent + 1)
      if item.kind in {yMapping, ySequence}:
        lines.add(indentStr & "-" & itemStr)
        # lines.add(itemStr)
      else:
        lines.add(indentStr & "- " & itemStr)
    return lines.join("\n")

proc `text=`*(yv: YamlViewer, yamlData: string) =
  yv.text = yamlData  # Store raw YAML text
  try:
    var s = newStringStream(yamlData)
    yv.rootNode = loadAs[YamlNode](s)
    yv.buildNodeTree()
    yv.render()
  except:
    yv.onError("Invalid YAML data")

proc loadFromFile*(yv: YamlViewer, filePath: string) =
  yv.filePath = filePath
  try:
    yv.text = readFile(filePath)  # Store raw YAML text
    var s = newFileStream(filePath)
    yv.rootNode = loadAs[YamlNode](s)
    s.close()
    yv.buildNodeTree()
    yv.render()
  except:
    yv.onError("Failed to load YAML file: " & filePath)


proc getNodeValue*(yv: YamlViewer, nodeIndex: int): YamlNode =
  if nodeIndex >= 0 and nodeIndex < yv.nodes.len:
    return yv.nodes[nodeIndex].value
  return nil


proc setNodeValue*(yv: YamlViewer, nodeIndex: int, value: YamlNode) =
  if nodeIndex >= 0 and nodeIndex < yv.nodes.len:
    yv.nodes[nodeIndex].value = value
    # Rebuild tree to reflect changes
    yv.buildNodeTree()


proc getSelectedNode*(yv: YamlViewer): int = yv.selectedNode


proc setSelectedNode*(yv: YamlViewer, nodeIndex: int) =
  if nodeIndex >= 0 and nodeIndex < yv.nodes.len:
    yv.selectedNode = nodeIndex
    # Ensure node is visible
    yv.ensureNodeVisible(nodeIndex)
    # Adjust row cursor
    let lineIndex = yv.nodes[nodeIndex].lineIndex
    if lineIndex < yv.rowCursor:
      yv.rowCursor = lineIndex
    elif lineIndex >= yv.rowCursor + yv.size:
      yv.rowCursor = max(0, lineIndex - yv.size + 1)