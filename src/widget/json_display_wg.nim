import illwill, base_wg, os, std/wordwrap, strutils, options, tables, json, algorithm, sequtils, input_box_wg
import threading/channels

type
  JsonNodeData = object
    key: string
    value: JsonNode
    expanded: bool
    level: int
    visible: bool
    lineIndex: int
    isLastChild: bool

  JsonViewer* = ref JsonViewerObj

  JsonViewerObj* = object of BaseWidget
    rootNode: JsonNode
    nodes: seq[JsonNodeData]
    visibleNodes: seq[int]  # indices of visible nodes
    selectedNode: int
    searchText: string
    searchResults: seq[int]  # indices of nodes matching search
    currentSearchIndex: int
    filePath: string
    events*: Table[string, EventFn[JsonViewer]]
    keyEvents*: Table[Key, EventFn[JsonViewer]]
    searchMode: bool
    searchInput: string
    text: string
    horizontalOffset: int

proc help(jv: JsonViewer, args: varargs[string]): void
proc on*(jv: JsonViewer, key: Key, fn: EventFn[JsonViewer]) {.raises: [EventKeyError].}
proc buildNodeTree(jv: JsonViewer): void
proc updateVisibleNodes(jv: JsonViewer): void
proc ensureNodeVisible(jv: JsonViewer, nodeIndex: int): void
proc renderStatusbar(jv: JsonViewer): void

# Allow ShiftW for binding
const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.None, Key.Up,
                          Key.Down, Key.PageUp, Key.PageDown, Key.Home,
                          Key.End, Key.Left, Key.Right}

proc newJsonViewer*(px, py, w, h: int, id = "";
                    title: string = "", jsonData: string = "", filePath: string = "",
                    border: bool = true, statusbar = true,
                    bgColor: BackgroundColor = bgNone,
                    fgColor: ForegroundColor = fgWhite,
                    tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): JsonViewer =
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
  result = (JsonViewer)(
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
    events: initTable[string, EventFn[JsonViewer]](),
    keyEvents: initTable[Key, EventFn[JsonViewer]]()
  )
  result.helpText = " [Enter] toggle expand/collapse\n" &
                    " [←/→]   scroll left/right\n" &
                    " [/]     search\n" &
                    " [n]     next search result\n" &
                    " [N]     previous search result\n" &
                    " [Ctrl+S] save changes\n" &
                    " [?]     for help\n" &
                    " [Tab]   to go next widget\n" & 
                    " [Esc]   to exit this window"
 
  result.channel = newChan[WidgetBgEvent]()
  result.on(Key.QuestionMark, help)
  result.keepOriginalSize()
  
  # Parse initial JSON data
  if jsonData.len > 0:
    try:
      result.rootNode = parseJson(jsonData)
      result.buildNodeTree()
    except:
      result.text = "Invalid JSON data"
  elif filePath.len > 0 and fileExists(filePath):
    try:
      result.rootNode = parseFile(filePath)
      result.buildNodeTree()
    except:
      result.text = "Invalid JSON file"


proc newJsonViewer*(id: string): JsonViewer =
  var viewer = JsonViewer(
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
    events: initTable[string, EventFn[JsonViewer]](),
    keyEvents: initTable[Key, EventFn[JsonViewer]]()
  )

  viewer.helpText = " [Enter] toggle expand/collapse\n" &
                    " [←/→]   scroll left/right\n" &
                    " [/]     search\n" &
                    " [n]     next search result\n" &
                    " [N]     previous search result\n" &
                    " [Ctrl+S] save changes\n" &
                    " [?]     for help\n" &
                    " [Tab]   to go next widget\n" & 
                    " [Esc]   to exit this window"
  viewer.on(Key.QuestionMark, help)
  viewer.channel = newChan[WidgetBgEvent]()
  return viewer


proc buildNodeTree(jv: JsonViewer) =
  jv.nodes = @[]
  jv.visibleNodes = @[]
  
  if jv.rootNode.isNil:
    return
  
  proc traverse(node: JsonNode, key: string, level: int, parentExpanded: bool) =
    let nodeIndex = jv.nodes.len
    jv.nodes.add(JsonNodeData(
      key: key,
      value: node,
      expanded: node.kind in {JObject, JArray} and level < 1,  # Auto-expand first level
      level: level,
      visible: parentExpanded,
      lineIndex: 0,
      isLastChild: false
    ))
    
    if parentExpanded:
      jv.visibleNodes.add(nodeIndex)
    
    if node.kind == JObject:
      let keys = node.keys.toSeq()
      for i, k in keys:
        let isLast = (i == keys.high)
        let childNode = node[k]
        let childExpanded = parentExpanded and jv.nodes[nodeIndex].expanded
        traverse(childNode, k, level + 1, childExpanded)
        if isLast and jv.nodes.len > 0:
          jv.nodes[jv.nodes.high].isLastChild = true
          
    elif node.kind == JArray:
      for i, item in node.getElems:
        let isLast = (i == node.len - 1)
        let childExpanded = parentExpanded and jv.nodes[nodeIndex].expanded
        traverse(item, "[" & $i & "]", level + 1, childExpanded)
        if isLast and jv.nodes.len > 0:
          jv.nodes[jv.nodes.high].isLastChild = true
  
  traverse(jv.rootNode, "root", 0, true)
  jv.updateVisibleNodes()



proc updateVisibleNodes(jv: JsonViewer) =
  jv.visibleNodes = @[]
  for i, node in jv.nodes:
    if node.visible:
      jv.nodes[i].lineIndex = jv.visibleNodes.len
      jv.visibleNodes.add(i)
    else:
      jv.nodes[i].lineIndex = -1


proc toggleNode(jv: JsonViewer, nodeIndex: int) =
  if jv.nodes[nodeIndex].value.kind notin {JObject, JArray}:
    return
  
  jv.nodes[nodeIndex].expanded = not jv.nodes[nodeIndex].expanded
  
  # Update visibility of children recursively
  proc updateChildVisibility(startIndex: int, parentLevel: int, shouldShow: bool) =
    var i = startIndex + 1
    while i < jv.nodes.len and jv.nodes[i].level > parentLevel:
      if jv.nodes[i].level == parentLevel + 1:
        # Direct child
        jv.nodes[i].visible = shouldShow
        if shouldShow and jv.nodes[i].expanded and jv.nodes[i].value.kind in {JObject, JArray}:
          # Recursively show grandchildren if this child is expanded
          updateChildVisibility(i, jv.nodes[i].level, true)
        elif not shouldShow:
          # Hide all descendants
          updateChildVisibility(i, jv.nodes[i].level, false)
      inc(i)
  
  updateChildVisibility(nodeIndex, jv.nodes[nodeIndex].level, jv.nodes[nodeIndex].expanded)
  jv.updateVisibleNodes()


proc formatNodeValue(jv: JsonViewer, node: JsonNodeData): string =
  case node.value.kind
  of JString:
    result = "\"" & node.value.getStr() & "\""
  of JInt:
    result = $node.value.getInt()
  of JFloat:
    result = $node.value.getFloat()
  of JBool:
    result = if node.value.getBool(): "true" else: "false"
  of JNull:
    result = "null"
  of JObject:
    result = if node.expanded: "{...}" else: "{...} (" & $node.value.len & " items)"
  of JArray:
    result = if node.expanded: "[...]" else: "[...] (" & $node.value.len & " items)"

proc renderNode(jv: JsonViewer, nodeIndex: int, lineIndex: int): string =
  let node = jv.nodes[nodeIndex]
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
  if node.value.kind in {JObject, JArray}:
    if node.expanded:
      prefix.add("- ")
    else:
      prefix.add("+ ")
  else:
    prefix.add("  ")
  
  # Format the node
  var fullLine = ""
  if node.key == "root":
    fullLine = prefix & "(root) " & jv.formatNodeValue(node)
  else:
    fullLine = prefix & node.key & ": " & jv.formatNodeValue(node)
  
  # Add selection indicator
  if nodeIndex == jv.selectedNode:
    fullLine = "> " & fullLine
  else:
    fullLine = "  " & fullLine
  
  # Apply horizontal scrolling
  let availableWidth = jv.width - (if jv.border: 2 else: 0)
  if fullLine.len > jv.horizontalOffset:
    let endPos = min(fullLine.len, jv.horizontalOffset + availableWidth)
    result = fullLine[jv.horizontalOffset..<endPos]
  else:
    result = ""


proc search(jv: JsonViewer, searchText: string) =
  jv.searchText = searchText
  jv.searchResults = @[]
  jv.currentSearchIndex = 0
  
  if searchText.len == 0:
    return
  
  for i, node in jv.nodes:
    # Search in key
    if node.key.toLower().contains(searchText.toLower()):
      jv.searchResults.add(i)
    # Search in value (for simple values)
    elif node.value.kind in {JString, JInt, JFloat, JBool}:
      var valueStr = ""
      case node.value.kind
      of JString: valueStr = node.value.getStr()
      of JInt: valueStr = $node.value.getInt()
      of JFloat: valueStr = $node.value.getFloat()
      of JBool: valueStr = if node.value.getBool(): "true" else: "false"
      else: discard
      
      if valueStr.toLower().contains(searchText.toLower()):
        jv.searchResults.add(i)
  
  if jv.searchResults.len > 0:
    jv.selectedNode = jv.searchResults[0]
    # Make sure the selected node is visible
    jv.ensureNodeVisible(jv.selectedNode)


proc onSearch(jv: JsonViewer) =
  jv.renderStatusBar()
  # Position search input at the top of the widget
  var input = newInputBox(jv.x1, jv.y1 + 1,  # Position at top, below title
                         jv.x2, jv.y1 + 3,    # Small height for input
                         title="search",
                         tb=jv.tb)
  let enterEv = proc(ib: InputBox, x: varargs[string]) =
    jv.search(ib.value)
    jv.searchInput = ib.value
    input.focus = false
    input.remove()
  
  # passing enter event as a callback
  input.illwillInit = true
  input.on("enter", enterEv)
  input.onControl()


proc ensureNodeVisible(jv: JsonViewer, nodeIndex: int) =
  # Expand all parents to make node visible
  var i = nodeIndex
  while i >= 0:
    if jv.nodes[i].level < jv.nodes[nodeIndex].level:
      jv.nodes[i].expanded = true
      jv.nodes[nodeIndex].visible = true
    dec(i)
  jv.updateVisibleNodes()


proc nextSearchResult(jv: JsonViewer) =
  if jv.searchResults.len == 0:
    return
  jv.currentSearchIndex = (jv.currentSearchIndex + 1) mod jv.searchResults.len
  jv.selectedNode = jv.searchResults[jv.currentSearchIndex]
  jv.ensureNodeVisible(jv.selectedNode)


proc prevSearchResult(jv: JsonViewer) =
  if jv.searchResults.len == 0:
    return
  jv.currentSearchIndex = (jv.currentSearchIndex - 1 + jv.searchResults.len) mod jv.searchResults.len
  jv.selectedNode = jv.searchResults[jv.currentSearchIndex]
  jv.ensureNodeVisible(jv.selectedNode)


proc saveToFile(jv: JsonViewer) =
  if jv.filePath.len > 0:
    try:
      writeFile(jv.filePath, jv.rootNode.pretty())
    except:
      # Handle error - could add error display
      discard


proc help(jv: JsonViewer, args: varargs[string]) = 
  let wsize = ((jv.width - jv.posX).toFloat * 0.3).toInt()
  let hsize = ((jv.height - jv.posY).toFloat * 0.3).toInt()
  var viewer = newJsonViewer(jv.x2 - wsize, jv.y2 - hsize, 
                          wsize, hsize, title="help",
                          bgColor=bgWhite, fgColor=fgBlack,
                          tb=jv.tb, statusbar=false)
  var helpText: string = if jv.helpText == "":
    " [Enter] toggle expand/collapse\n" &
    " [←/→]   scroll left/right\n" &
    " [/]     search\n" &
    " [n]     next search result\n" &
    " [N]     previous search result\n" &
    " [Ctrl+S] save changes\n" &
    " [?]     for help\n" &
    " [Tab]   to go next widget\n" & 
    " [Esc]   to exit this window"
  else: jv.helpText
  viewer.text = helpText
  viewer.illwillInit = true
  jv.render()
  viewer.onControl()
  viewer.clear()



proc renderStatusbar(jv: JsonViewer) =
  if jv.events.hasKey("statusbar"):
    jv.call("statusbar")
  else:
    var statusText = " "
    if jv.searchMode:
      statusText &= "Search: " & jv.searchInput
    elif jv.searchResults.len > 0:
      statusText &= "Match " & $(jv.currentSearchIndex + 1) & "/" & $jv.searchResults.len
    else:
      statusText &= "Line " & $(jv.nodes[jv.selectedNode].lineIndex + 1) & "/" & $jv.visibleNodes.len
      if jv.horizontalOffset > 0:
        statusText &= " | H-scroll: " & $jv.horizontalOffset
    
    let borderSize = if jv.border: 2 else: 1
    statusText = statusText & " ".repeat(jv.width - statusText.len - borderSize)
    jv.renderCleanRect(jv.x1, jv.height, jv.x1 + statusText.len - 1, jv.height)
    jv.tb.write(jv.x1, jv.height - 1, bgWhite, fgBlack, statusText, resetStyle)
    
    let q = "[?]"
    jv.tb.write(jv.x2 - len(q), jv.height - 1, bgWhite, fgBlack, q, resetStyle)
  
  if jv.border: jv.renderBorder()


method resize*(jv: JsonViewer) =
  let statusbarSize = if jv.statusbar: 1 else: 0
  jv.size = jv.height - statusbarSize - jv.posY - (jv.paddingY1 * 2)


proc on*(jv: JsonViewer, event: string, fn: EventFn[JsonViewer]) =
  jv.events[event] = fn


proc on*(jv: JsonViewer, key: Key, fn: EventFn[JsonViewer]) {.raises: [EventKeyError].} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  jv.keyEvents[key] = fn


method call*(jv: JsonViewer, event: string, args: varargs[string]) =
  if jv.events.hasKey(event):
    let fn = jv.events[event]
    fn(jv, args)


method call*(jv: JsonViewerObj, event: string, args: varargs[string]) =
  if jv.events.hasKey(event):
    let jvRef = jv.asRef()
    let fn = jv.events[event]
    fn(jvRef, args)


proc call(jv: JsonViewer, key: Key, args: varargs[string]) =
  if jv.keyEvents.hasKey(key):
    let fn = jv.keyEvents[key]
    fn(jv, args)


method render*(jv: JsonViewer) =
  if not jv.illwillInit: return
  jv.clear()
  jv.renderBorder()
  jv.renderTitle()
  
  var index = 1
  if jv.visibleNodes.len > 0:
    let startLine = min(jv.rowCursor, jv.visibleNodes.len - 1)
    let endLine = min(startLine + jv.size - 1, jv.visibleNodes.len - 1)
    
    for i in startLine..endLine:
      let nodeIndex = jv.visibleNodes[i]
      var line = jv.renderNode(nodeIndex, i)
      if line.len > (jv.x2 - jv.x1):
        line = line[0..(min(jv.x2 - jv.x1, line.len))]
      jv.renderRow(line, index)
      inc index
  
  if jv.statusbar:
    jv.renderStatusbar()
  
  jv.tb.display()


method poll*(jv: JsonViewer) =
  var widgetEv: WidgetBgEvent
  if jv.channel.tryRecv(widgetEv):
    jv.call(widgetEv.event, widgetEv.args)
    jv.render()

method onUpdate*(jv: JsonViewer, key: Key) =
  if jv.visibility == false: 
    jv.rowCursor = 0
    jv.selectedNode = 0
    jv.horizontalOffset = 0
    return
  
  jv.call("preupdate", $key) 
  
  # Handle search input mode
  if jv.searchMode:
    jv.onSearch()
    jv.searchMode = false
  else:
    # Normal navigation mode
    case key
    of Key.None: discard
    of Key.Up:
      if jv.visibleNodes.len > 0:
        let currentIndex = jv.nodes[jv.selectedNode].lineIndex
        if currentIndex > 0:
          jv.selectedNode = jv.visibleNodes[currentIndex - 1]
          # Adjust row cursor if needed
          if currentIndex <= jv.rowCursor:
            jv.rowCursor = max(0, jv.rowCursor - 1)
    of Key.Down:
      if jv.visibleNodes.len > 0:
        let currentIndex = jv.nodes[jv.selectedNode].lineIndex
        if currentIndex < jv.visibleNodes.len - 1:
          jv.selectedNode = jv.visibleNodes[currentIndex + 1]
          # Adjust row cursor if needed
          if currentIndex >= jv.rowCursor + jv.size - 1:
            jv.rowCursor = min(jv.rowCursor + 1, max(0, jv.visibleNodes.len - jv.size))
    of Key.Left:
      # Horizontal scroll left
      jv.horizontalOffset = max(0, jv.horizontalOffset - 4)  # Scroll by 4 characters
    of Key.Right:
      # Horizontal scroll right
      jv.horizontalOffset += 4  # Scroll by 4 characters
    of Key.Enter:
      jv.toggleNode(jv.selectedNode)
    of Key.Slash:  # Search
      jv.searchMode = true
    of Key.N:  # Next search result
      jv.nextSearchResult()
      # Reset horizontal scroll when jumping to search results
      jv.horizontalOffset = 0
      # Adjust row cursor to show selected node
      let selectedLineIndex = jv.nodes[jv.selectedNode].lineIndex
      if selectedLineIndex < jv.rowCursor:
        jv.rowCursor = selectedLineIndex
      elif selectedLineIndex >= jv.rowCursor + jv.size:
        jv.rowCursor = max(0, selectedLineIndex - jv.size + 1)
    of Key.P:  # Previous search result
      jv.prevSearchResult()
      # Reset horizontal scroll when jumping to search results
      jv.horizontalOffset = 0
      # Adjust row cursor to show selected node
      let selectedLineIndex = jv.nodes[jv.selectedNode].lineIndex
      if selectedLineIndex < jv.rowCursor:
        jv.rowCursor = selectedLineIndex
      elif selectedLineIndex >= jv.rowCursor + jv.size:
        jv.rowCursor = max(0, selectedLineIndex - jv.size + 1)
    of Key.PageUp:
      jv.rowCursor = max(0, jv.rowCursor - jv.size)
      # Update selected node to first visible node
      if jv.visibleNodes.len > 0:
        let newIndex = max(0, jv.nodes[jv.selectedNode].lineIndex - jv.size)
        if newIndex < jv.visibleNodes.len:
          jv.selectedNode = jv.visibleNodes[newIndex]
    of Key.PageDown:
      jv.rowCursor = min(jv.rowCursor + jv.size, max(0, jv.visibleNodes.len - jv.size))
      # Update selected node to last visible node
      if jv.visibleNodes.len > 0:
        let newIndex = min(jv.visibleNodes.len - 1, jv.nodes[jv.selectedNode].lineIndex + jv.size)
        if newIndex < jv.visibleNodes.len:
          jv.selectedNode = jv.visibleNodes[newIndex]
    of Key.Home:
      jv.rowCursor = 0
      jv.horizontalOffset = 0  # Reset horizontal scroll
      if jv.visibleNodes.len > 0:
        jv.selectedNode = jv.visibleNodes[0]
    of Key.End:
      jv.rowCursor = max(0, jv.visibleNodes.len - jv.size)
      if jv.visibleNodes.len > 0:
        jv.selectedNode = jv.visibleNodes[jv.visibleNodes.len - 1]
    of Key.Escape, Key.Tab:
      jv.focus = false
    of Key.CtrlS:  # Save
      jv.saveToFile()
    else:
      if key in forbiddenKeyBind: discard
      elif jv.keyEvents.hasKey(key):
        jv.call(key, "")
  
  jv.render()
  jv.call("postupdate", $key)

method onControl*(jv: JsonViewer) =
  if jv.visibility == false: 
    jv.rowCursor = 0
    jv.selectedNode = 0
    return
  jv.focus = true
  jv.clear()
  while jv.focus:
    var key = getKeyWithTimeout(jv.rpms)
    jv.onUpdate(key)
    sleep(jv.rpms)


method wg*(jv: JsonViewer): ref BaseWidget = jv


proc text*(jv: JsonViewer): string = 
  if not jv.rootNode.isNil:
    return jv.rootNode.pretty()
  return ""


proc `text=`*(jv: JsonViewer, jsonData: string) =
  try:
    jv.rootNode = parseJson(jsonData)
    jv.buildNodeTree()
    jv.render()
  except:
    jv.onError("Invalid JSON data")


proc loadFromFile*(jv: JsonViewer, filePath: string) =
  jv.filePath = filePath
  try:
    jv.rootNode = parseFile(filePath)
    jv.buildNodeTree()
    jv.render()
  except:
    jv.onError("Failed to load JSON file: " & filePath)


proc getNodeValue*(jv: JsonViewer, nodeIndex: int): JsonNode =
  if nodeIndex >= 0 and nodeIndex < jv.nodes.len:
    return jv.nodes[nodeIndex].value
  return nil


proc setNodeValue*(jv: JsonViewer, nodeIndex: int, value: JsonNode) =
  if nodeIndex >= 0 and nodeIndex < jv.nodes.len:
    jv.nodes[nodeIndex].value = value
    # Rebuild tree to reflect changes
    jv.buildNodeTree()


proc getSelectedNode*(jv: JsonViewer): int = jv.selectedNode


proc setSelectedNode*(jv: JsonViewer, nodeIndex: int) =
  if nodeIndex >= 0 and nodeIndex < jv.nodes.len:
    jv.selectedNode = nodeIndex
    # Ensure node is visible
    jv.ensureNodeVisible(nodeIndex)
    # Adjust row cursor
    let lineIndex = jv.nodes[nodeIndex].lineIndex
    if lineIndex < jv.rowCursor:
      jv.rowCursor = lineIndex
    elif lineIndex >= jv.rowCursor + jv.size:
      jv.rowCursor = max(0, lineIndex - jv.size + 1)
