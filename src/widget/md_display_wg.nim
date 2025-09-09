import illwill, base_wg, os, std/wordwrap, strutils, options, tables, re, std/sequtils, sets
import threading/channels

type
  MarkdownStyle* = object
    headerColor*: ForegroundColor
    headerBgColor*: BackgroundColor  
    boldColor*: ForegroundColor
    italicColor*: ForegroundColor
    codeColor*: ForegroundColor
    codeBgColor*: BackgroundColor
    linkColor*: ForegroundColor
    quoteColor*: ForegroundColor
    quoteBgColor*: BackgroundColor
    listColor*: ForegroundColor
    normalColor*: ForegroundColor

  MarkdownElement* = object
    text*: string
    style*: MarkdownStyle
    elementType*: string  # "header", "bold", "italic", "code", "link", "quote", "list", "normal"
    level*: int  # for headers (1-6)

  CustomMarkdownRecal* = proc(text: string, md: Markdown): seq[string]
  
  Markdown* = ref MarkdownObj

  MarkdownObj* = object of BaseWidget
    text: string = ""
    textRows: seq[string] = newSeq[string]()
    wordwrap*: bool = false
    useCustomTextRow*: bool = false
    customRowRecal*: Option[CustomMarkdownRecal]
    events*: Table[string, EventFn[Markdown]]
    keyEvents*: Table[Key, EventFn[Markdown]]
    mouseEvents*: Table[MouseButton, EventFn[Markdown]]
    mouseEnabled: bool = false
    markdownStyle*: MarkdownStyle
    showMarkdown*: bool = true  # Toggle between markdown and raw text

proc help(md: Markdown, args: varargs[string]): void
proc on*(md: Markdown, key: Key, fn: EventFn[Markdown]) {.raises: [EventKeyError].}
proc toggleWordWrap(md: Markdown, args: varargs[string]): void
proc toggleMarkdown(md: Markdown, args: varargs[string]): void

const forbiddenKeyBind = {Key.Tab, Key.Escape, Key.None, Key.Up,
                          Key.Down, Key.PageUp, Key.PageDown, Key.Home,
                          Key.End, Key.Left, Key.Right}

proc defaultMarkdownStyle*(): MarkdownStyle =
  result = MarkdownStyle(
    headerColor: fgYellow,
    headerBgColor: bgBlue,
    boldColor: fgWhite,
    italicColor: fgCyan,
    codeColor: fgGreen,
    codeBgColor: bgBlack,
    linkColor: fgBlue,
    quoteColor: fgMagenta,
    quoteBgColor: bgNone,
    listColor: fgWhite,
    normalColor: fgWhite
  )

proc newMarkdown*(px, py, w, h: int, id = "";
                  title: string = "", text: string = "", border: bool = true,
                  statusbar = true, wordwrap = false, enableHelp = false,
                  bgColor: BackgroundColor = bgNone,
                  fgColor: ForegroundColor = fgWhite,
                  mouseEnabled: bool = false,
                  markdownStyle = defaultMarkdownStyle(),
                  customRowRecal: Option[CustomMarkdownRecal] = none(CustomMarkdownRecal),
                  tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py)): Markdown =
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
  result = (Markdown)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    text: text,
    size: h - statusbarSize - py - (padding * 2),
    statusbarSize: statusbarSize,
    enableHelp: enableHelp,
    title: title,
    statusbar: statusbar,
    tb: tb,
    style: style,
    wordwrap: wordwrap,
    markdownStyle: markdownStyle,
    customRowRecal: customRowRecal,
    mouseEnabled: mouseEnabled,
    useCustomTextRow: if customRowRecal.isSome: true else: false,
    events: initTable[string, EventFn[Markdown]](),
    keyEvents: initTable[Key, EventFn[Markdown]](),
    mouseEvents: initTable[MouseButton, EventFn[Markdown]]()
  )
  result.helpText = " [W]   toggle wordwrap\n" &
                    " [M]   toggle markdown rendering\n" &
                    " [?]   for help\n" &
                    " [Tab]  to go next widget\n" & 
                    " [Esc] to exit this window"
 
  result.channel = newChan[WidgetBgEvent]()
  if enableHelp:
    result.on(Key.QuestionMark, help)
  result.on(Key.ShiftW, toggleWordWrap)
  result.on(Key.ShiftM, toggleMarkdown)
  result.keepOriginalSize()

proc newMarkdown*(px, py: int, w, h: WidgetSize, id = "";
                  title = "", text = "", border = true,
                  statusbar = true, wordwrap = false, enableHelp = false,
                  bgColor = bgNone,
                  fgColor = fgWhite,
                  mouseEnabled = false,
                  markdownStyle = defaultMarkdownStyle(),
                  customRowRecal: Option[CustomMarkdownRecal] = none(CustomMarkdownRecal),
                  tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): Markdown =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newMarkdown(px, py, width, height, id, title, text, border,
                     statusbar, wordwrap, enableHelp, bgColor, fgColor, 
                     mouseEnabled, markdownStyle, customRowRecal, tb)

proc splitBySize(val: string, size: int, rows: int, visualSkip = 2): seq[string] =
  if val.len() > size:
    var wrappedWords = val.wrapWords(maxLineWidth = size - visualSkip, splitLongWords = false)
    var lines = wrappedWords.split("\n")
    return lines
  else:
    var lines = val.split("\n")
    return lines

proc textWindow(text: string, width: int, offset: int): seq[string] =
  var formattedText = newSeq[string]()
  let lines = text.splitLines()
  for line in lines:
    if line == "": continue
    var visibleText = ""
    var currentOffset = 0
    let lineLen = line.len
    if currentOffset + lineLen <= offset:
      currentOffset += lineLen + 1 
    else:
      if currentOffset < offset and offset < lineLen:
        let startIndex = offset - currentOffset
        visibleText.add(line[startIndex..^1]) 
        currentOffset = offset
      else:
        visibleText.add(line)
      if visibleText.len >= width:
        formattedText.add(visibleText[0..max(0, width-1)]) 
        visibleText = ""
        continue
    visibleText = alignLeft(visibleText, max(width, visibleText.len), ' ')
    if visibleText.len > 0:
      formattedText.add(visibleText[0..^1])
    else:
      formattedText.add("")
  return formattedText

proc isPunct(c: char): bool =
  let punctuationChars = {'!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/',
                          ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~'}
  return c in punctuationChars
  
proc parseInlineMarkdown(text: string, style: MarkdownStyle): seq[tuple[text: string, fg: ForegroundColor, bg: BackgroundColor, textStyle: set[Style]]] =
  result = @[]
  var pos = 0
  
  while pos < text.len:
    var foundFormat = false
    
    # Look for code blocks (backticks) - single ` or ```
    if text[pos] == '`':
      var markerLen = 1
      
      # Check for triple backticks
      if pos + 2 < text.len and text[pos+1] == '`' and text[pos+2] == '`':
        markerLen = 3
      
      if markerLen == 3:
        # For triple backticks, we need to find the closing triple backticks
        var codeEnd = -1
        for j in (pos + 3)..<text.len-2:
          if text[j] == '`' and text[j+1] == '`' and text[j+2] == '`':
            codeEnd = j
            break
        
        if codeEnd > pos:
          let codeText = text[(pos + 3)..<codeEnd]
          result.add((codeText, style.codeColor, style.codeBgColor, {styleBright}))
          pos = codeEnd + 3
          foundFormat = true
        else:
          # No closing triple backticks, treat as normal text
          if result.len == 0 or result[^1].fg != style.normalColor or result[^1].bg != bgNone or result[^1].textStyle != {}:
            result.add((text[pos..pos+2], style.normalColor, bgNone, {}))
          else:
            result[^1].text &= text[pos..pos+2]
          pos += 3
          foundFormat = true
      else:
        # Single backtick
        var codeEnd = -1
        for j in (pos + 1)..<text.len:
          if text[j] == '`':
            codeEnd = j
            break
        
        if codeEnd > pos:
          let codeText = text[(pos + 1)..<codeEnd]
          result.add((codeText, style.codeColor, style.codeBgColor, {styleBright}))
          pos = codeEnd + 1
          foundFormat = true
        else:
          # No closing backtick, treat as normal text
          if result.len == 0 or result[^1].fg != style.normalColor or result[^1].bg != bgNone or result[^1].textStyle != {}:
            result.add((text[pos..pos], style.normalColor, bgNone, {}))
          else:
            result[^1].text &= text[pos]
          pos += 1
          foundFormat = true
    
    if foundFormat:
      continue
    
    # Look for bold text (**)
    if pos + 1 < text.len and text[pos] == '*' and text[pos+1] == '*':
      # Find closing **
      var boldEnd = -1
      for j in (pos + 2)..<text.len-1:
        if text[j] == '*' and text[j+1] == '*':
          boldEnd = j
          break
      
      if boldEnd > pos:
        let boldText = text[(pos + 2)..<boldEnd]
        result.add((boldText, style.boldColor, bgNone, {styleBright}))
        pos = boldEnd + 2
        foundFormat = true
      else:
        # No closing **, treat as normal text
        let boldChars = if pos + 1 < text.len: text[pos..pos+1] else: text[pos..^1]
        if result.len == 0 or result[^1].fg != style.headerColor or result[^1].bg != bgNone or result[^1].textStyle != {}:
          result.add((boldChars, style.boldColor, bgNone, {}))
        else:
          result[^1].text &= boldChars
        pos += 2
        foundFormat = true
    
    if foundFormat:
      continue
    
    # Look for italic text (*)
    if text[pos] == '*' and 
       (pos == 0 or text[pos-1] == ' ' or text[pos-1].isPunct) and
       (pos == text.len-1 or (text[pos+1] != '*' and (text[pos+1] == ' ' or text[pos+1].isPunct or pos+1 < text.len))):
      
      # Find closing *
      var italicEnd = -1
      for j in (pos + 1)..<text.len:
        if text[j] == '*' and 
           (j == text.len-1 or text[j+1] == ' ' or text[j+1].isPunct):
          italicEnd = j
          break
      
      if italicEnd > pos:
        let italicText = text[(pos + 1)..<italicEnd]
        result.add((italicText, style.italicColor, bgNone, {styleItalic}))
        pos = italicEnd + 1
        foundFormat = true
      else:
        # No closing *, treat as normal text
        if result.len == 0 or result[^1].fg != style.normalColor or result[^1].bg != bgNone or result[^1].textStyle != {}:
          result.add((text[pos..pos], style.normalColor, bgNone, {}))
        else:
          result[^1].text &= text[pos]
        pos += 1
        foundFormat = true
    
    if foundFormat:
      continue
    
    # Look for links [text](url)
    if text[pos] == '[':
      var linkTextEnd = -1
      for j in (pos + 1)..<text.len:
        if text[j] == ']':
          linkTextEnd = j
          break
      
      if linkTextEnd > pos and linkTextEnd + 1 < text.len and text[linkTextEnd + 1] == '(':
        var linkEnd = -1
        for j in (linkTextEnd + 2)..<text.len:
          if text[j] == ')':
            linkEnd = j
            break
        
        if linkEnd > linkTextEnd:
          let linkText = text[(pos + 1)..<linkTextEnd]
          result.add((linkText, style.linkColor, bgNone, {styleUnderscore}))
          pos = linkEnd + 1
          foundFormat = true
        else:
          # Malformed link, treat as normal text
          if result.len == 0 or result[^1].fg != style.normalColor or result[^1].bg != bgNone or result[^1].textStyle != {}:
            result.add((text[pos..pos], style.normalColor, bgNone, {}))
          else:
            result[^1].text &= text[pos]
          pos += 1
          foundFormat = true
      else:
        # Malformed link, treat as normal text
        if result.len == 0 or result[^1].fg != style.normalColor or result[^1].bg != bgNone or result[^1].textStyle != {}:
          result.add((text[pos..pos], style.normalColor, bgNone, {}))
        else:
          result[^1].text &= text[pos]
        pos += 1
        foundFormat = true
    else:
      # Add normal character
      if result.len == 0 or result[^1].fg != style.normalColor or result[^1].bg != bgNone or result[^1].textStyle != {}:
        result.add((text[pos..pos], style.normalColor, bgNone, {}))
      else:
        result[^1].text &= text[pos]
      pos += 1
  
  # Handle case where no formatting was found
  if result.len == 0:
    result.add((text, style.normalColor, bgNone, {}))

proc renderTableRows(tableHeaders: seq[string], tableRows: seq[seq[string]], tableAlignments: seq[string]): seq[string] =
  var tableLines = newSeq[string]()
  
  if tableHeaders.len > 0:
    # Calculate column widths based on content
    var colWidths = newSeq[int](tableHeaders.len)
    for i, header in tableHeaders:
      colWidths[i] = header.len
    
    for row in tableRows:
      for i in 0..<min(row.len, colWidths.len):
        colWidths[i] = max(colWidths[i], row[i].len)
    
    # Ensure minimum width of 3 for each column
    for i in 0..<colWidths.len:
      colWidths[i] = max(colWidths[i], 3)
    
    # Top border
    var topBorder = "+"
    for i in 0..<colWidths.len:
      topBorder &= "-".repeat(colWidths[i] + 2)  # +2 for padding
      topBorder &= "+"
    tableLines.add(topBorder)
    
    # Header row
    var headerRow = "|"
    for i in 0..<min(tableHeaders.len, colWidths.len):
      let header = tableHeaders[i]
      let alignment = if i < tableAlignments.len: tableAlignments[i] else: ""
      let padded = case alignment:
        of ":---", ":--": header.alignLeft(colWidths[i])
        of "---:", "--:": header.align(colWidths[i])
        of ":--:": header.center(colWidths[i])
        else: header.alignLeft(colWidths[i])
      headerRow &= " " & padded & " |"
    tableLines.add(headerRow)
    
    # Separator line
    var separator = "+"
    for i in 0..<colWidths.len:
      separator &= "-".repeat(colWidths[i] + 2)
      separator &= "+"
    tableLines.add(separator)
    
    # Data rows
    for row in tableRows:
      var dataRow = "|"
      for i in 0..<colWidths.len:
        let cell = if i < row.len: row[i] else: ""
        let alignment = if i < tableAlignments.len: tableAlignments[i] else: ""
        let padded = case alignment:
          of ":---", ":--": cell.alignLeft(colWidths[i])
          of "---:", "--:": cell.align(colWidths[i])
          of ":--:": cell.center(colWidths[i])
          else: cell.alignLeft(colWidths[i])
        dataRow &= " " & padded & " |"
      tableLines.add(dataRow)
    
    # Bottom border
    var bottomBorder = "+"
    for i in 0..<colWidths.len:
      bottomBorder &= "-".repeat(colWidths[i] + 2)
      bottomBorder &= "+"
    tableLines.add(bottomBorder)
  
  return tableLines

# proc parseMarkdown(text: string, style: MarkdownStyle): seq[string] =
#   result = @[]
#   let lines = text.splitLines()
#   var inCodeBlock = false
#   var codeBlockContent: seq[string] = @[]
#   var tableRows: seq[seq[string]] = @[]
#   var tableHeaders: seq[string] = @[]
#   var tableAlignments: seq[string] = @[]
#   var inTable = false
  
#   for line in lines:
#     let trimmedLine = line.strip()
    
#     # Handle code blocks - check if line starts with ``` 
#     if trimmedLine.startsWith("```"):
#       if inCodeBlock:
#         # Ending code block - now render with proper sizing
#         if codeBlockContent.len > 0:
#           # Calculate max width needed (account for padding)
#           var maxWidth = 0
#           for contentLine in codeBlockContent:
#             maxWidth = max(maxWidth, contentLine.len)
          
#           # Ensure minimum width
#           maxWidth = max(maxWidth, 4)
          
#           # Add top border
#           result.add("┌" & "─".repeat(maxWidth) & "┐")
          
#           # Add content lines
#           for contentLine in codeBlockContent:
#             let paddedLine = contentLine & " ".repeat(maxWidth - contentLine.len)
#             result.add("│" & paddedLine & "│")
          
#           # Add bottom border
#           result.add("└" & "─".repeat(maxWidth) & "┘")
        
#         codeBlockContent.setLen(0)
#       inCodeBlock = not inCodeBlock
#       continue
    
#     if inCodeBlock:
#       codeBlockContent.add(line)
#       continue
    
#     # Handle table rows
#     if trimmedLine.startsWith("|") and trimmedLine.endsWith("|") and "|" in trimmedLine[1..^1]:
#       let cells = trimmedLine[1..^1].split('|').mapIt(it.strip())
      
#       # Check if it's an alignment row
#       if cells.allIt(it.allCharsInSet({'-', ':', ' '})) and cells.anyIt(it.contains('-')):
#         tableAlignments = cells
#         inTable = true
#         continue
      
#       # If we don't have headers yet, this is the header row
#       if not inTable:
#         tableHeaders = cells
#         inTable = true
#         continue
      
#       # This is a data row
#       tableRows.add(cells)
#       continue
    
#     # If we were in a table and hit a non-table line, flush the table
#     if inTable:
#       let tableLines = renderTableRows(tableHeaders.filter(proc(x: string): bool = x.len() > 0), tableRows, tableAlignments)
#       result.add(tableLines)
#       # Reset table state
#       tableHeaders = @[]
#       tableRows = @[]
#       tableAlignments = @[]
#       inTable = false
    
#     # Handle other markdown elements
#     if trimmedLine.startsWith("#"):
#       var level = 0
#       var i = 0
#       while i < trimmedLine.len and trimmedLine[i] == '#' and level < 6:
#         level += 1
#         i += 1
      
#       if level > 0 and i < trimmedLine.len and trimmedLine[i] == ' ':
#         let headerText = "│" & "═".repeat(level) & " " & trimmedLine[(i+1)..^1]
#         result.add(headerText)
#         continue
    
#     if trimmedLine.startsWith(">"):
#       let quoteText = "┃ " & trimmedLine[1..^1].strip()
#       result.add(quoteText)
#       continue
    
#     # Handle list items - simplified approach
#     if trimmedLine.startsWith("- ") or trimmedLine.startsWith("* ") or trimmedLine.startsWith("+ "):
#       # Calculate indentation level
#       var indentLevel = 0
#       var i = 0
#       while i < line.len and line[i] == ' ':
#         indentLevel += 1
#         i += 1
      
#       # Convert indentation to visual nesting (2 spaces per level)
#       let visualIndent = "  ".repeat(indentLevel div 2)
#       let listText = visualIndent & "• " & trimmedLine[2..^1]
#       result.add(listText)
#       continue

#     # Handle numbered lists with proper nesting
#     var numListMatch = false
#     var dotPos = -1
#     # Find the dot position after digits
#     for i in 0..<min(line.len, 10):
#       if line[i].isDigit:
#         continue
#       elif line[i] == '.' and i > 0:
#         # Check if there's a space after the dot
#         if i + 1 < line.len and line[i + 1] == ' ':
#           dotPos = i
#           numListMatch = true
#           break
#         else:
#           break
#       else:
#         break

#     if numListMatch:
#       # Calculate indentation level
#       var indentLevel = 0
#       var i = 0
#       while i < line.len and line[i] == ' ':
#         indentLevel += 1
#         i += 1
      
#       # Convert indentation to visual nesting
#       let visualIndent = "  ".repeat(indentLevel div 2)
#       let listText = visualIndent & line[dotPos-1..dotPos] & " " & line[dotPos + 2..^1]
#       result.add(listText)
#       continue
    
#     # Handle numbered lists
#     # var numListMatch = false
#     # var dotPos = -1
#     # for i in 0..<min(trimmedLine.len, 10):  # Limit search to first 10 chars
#     #   if trimmedLine[i].isDigit:
#     #     continue
#     #   elif trimmedLine[i] == '.' and i > 0:
#     #     dotPos = i
#     #     numListMatch = true
#     #     break
#     #   else:
#     #     break
    
#     # if numListMatch and dotPos + 1 < trimmedLine.len and trimmedLine[dotPos + 1] == ' ':
#     #   let listText = trimmedLine[0..dotPos] & " " & trimmedLine[dotPos + 2..^1]
#     #   result.add(listText)
#     #   continue
    
#     # Regular text
#     result.add(line)
  
#   # Flush any remaining code block
#   if inCodeBlock and codeBlockContent.len > 0:
#     # Calculate max width needed
#     var maxWidth = 10  # Minimum width
#     for contentLine in codeBlockContent:
#       maxWidth = max(maxWidth, contentLine.len)
    
#     # Add top border
#     result.add("┌" & "─".repeat(maxWidth + 2) & "┐")
    
#     # Add content lines
#     for contentLine in codeBlockContent:
#       let paddedLine = contentLine & " ".repeat(maxWidth - contentLine.len)
#       result.add("│ " & paddedLine & " │")
    
#     # Add bottom border
#     result.add("└" & "─".repeat(maxWidth + 2) & "┘")
  
#   # Flush any remaining table
#   if inTable:
#     let tableLines = renderTableRows(tableHeaders.filter(proc(x: string): bool = x.len() > 0), tableRows, tableAlignments)
#     result.add(tableLines)

# Replace the parseMarkdown proc with this corrected version
proc parseMarkdown(text: string, style: MarkdownStyle): seq[string] =
  result = @[]
  let lines = text.splitLines()
  var inCodeBlock = false
  var codeBlockContent: seq[string] = @[]
  var tableRows: seq[seq[string]] = @[]
  var tableHeaders: seq[string] = @[]
  var tableAlignments: seq[string] = @[]
  var inTable = false
  var i = 0
  
  while i < lines.len:
    let line = lines[i]
    let trimmedLine = line.strip()
    
    # Handle code blocks - check if line starts with ``` 
    if trimmedLine.startsWith("```"):
      if inCodeBlock:
        # Ending code block - now render with proper sizing
        if codeBlockContent.len > 0:
          # Calculate max width needed (account for padding)
          var maxWidth = 0
          for contentLine in codeBlockContent:
            maxWidth = max(maxWidth, contentLine.len)
          
          # Ensure minimum width
          maxWidth = max(maxWidth, 4)
          
          # Add top border
          result.add("┌" & "─".repeat(maxWidth) & "┐")
          
          # Add content lines
          for contentLine in codeBlockContent:
            let paddedLine = contentLine & " ".repeat(maxWidth - contentLine.len)
            result.add("│" & paddedLine & "│")
          
          # Add bottom border
          result.add("└" & "─".repeat(maxWidth) & "┘")
        
        codeBlockContent.setLen(0)
      inCodeBlock = not inCodeBlock
      i += 1
      continue
    
    if inCodeBlock:
      codeBlockContent.add(line)
      i += 1
      continue
    
    # Handle thematic breaks (---, ***, ___) - MUST come before Setext headers
    if trimmedLine.len >= 3 and trimmedLine.allCharsInSet({'-', '*', '_'}):
      # Create a horizontal line across the width
      result.add("-".repeat(80))  # Adjust width as needed or make dynamic
      i += 1
      continue
    
    # Handle Setext-style headers (underlined with === or ---)
    if i + 1 < lines.len:
      let nextLine = lines[i + 1].strip()
      if nextLine.len > 0 and nextLine.allCharsInSet({'='}):
        # Level 1 header with ===
        let headerText = line.strip()
        let headerWidth = max(headerText.len + 4, 10)  # Minimum width
        result.add("┌" & "─".repeat(headerWidth - 2) & "┐")
        let paddedText = " " & headerText & " ".repeat(headerWidth - headerText.len - 3)
        result.add("│" & paddedText & "│")
        result.add("└" & "─".repeat(headerWidth - 2) & "┘")
        i += 2  # Skip both lines
        continue
      # elif nextLine.len > 0 and nextLine.allCharsInSet({'-'}):
      #   # Level 2 header with ---
      #   let headerText = line.strip()
      #   let headerWidth = max(headerText.len + 4, 10)  # Minimum width
      #   result.add("┌" & "╌".repeat(headerWidth - 2) & "┐")  # Different border for level 2
      #   let paddedText = " " & headerText & " ".repeat(headerWidth - headerText.len - 3)
      #   result.add("│" & paddedText & "│")
      #   result.add("└" & "╌".repeat(headerWidth - 2) & "┘")
      #   i += 2  # Skip both lines
      #   continue
    
    # Handle table rows
    if trimmedLine.startsWith("|") and trimmedLine.endsWith("|") and "|" in trimmedLine[1..^1]:
      let cells = trimmedLine[1..^1].split('|').mapIt(it.strip())
      
      # Check if it's an alignment row
      if cells.allIt(it.allCharsInSet({'-', ':', ' '})) and cells.anyIt(it.contains('-')):
        tableAlignments = cells
        inTable = true
        i += 1
        continue
      
      # If we don't have headers yet, this is the header row
      if not inTable:
        tableHeaders = cells
        inTable = true
        i += 1
        continue
      
      # This is a data row
      tableRows.add(cells)
      i += 1
      continue
    
    # If we were in a table and hit a non-table line, flush the table
    if inTable:
      let tableLines = renderTableRows(tableHeaders.filter(proc(x: string): bool = x.len() > 0), tableRows, tableAlignments)
      result.add(tableLines)
      # Reset table state
      tableHeaders = @[]
      tableRows = @[]
      tableAlignments = @[]
      inTable = false
    
    # Handle ATX-style headers (# Header)
    if trimmedLine.startsWith("#"):
      var level = 0
      var j = 0
      while j < trimmedLine.len and trimmedLine[j] == '#' and level < 6:
        level += 1
        j += 1
      
      if level > 0 and j < trimmedLine.len and trimmedLine[j] == ' ':
        let headerText = trimmedLine[(j+1)..^1]
        # Create a header with background color
        let headerWidth = max(headerText.len + 4, 10)
        let bgColor = if style.headerBgColor != bgNone: $style.headerBgColor else: ""
        let fgColor = if style.headerColor != fgWhite: $style.headerColor else: ""
        # For simplicity in terminal, we'll just add visual indicators
        result.add "+" & "=".repeat(headerWidth - 2) & "+"
        result.add "| " & headerText & " ".repeat(headerWidth - headerText.len - 3) & "|"
        result.add "+" & "=".repeat(headerWidth - 2) & "+"
        i += 1
        continue
    
    if trimmedLine.startsWith(">"):
      let quoteText = "┃ " & trimmedLine[1..^1].strip()
      result.add(quoteText)
      i += 1
      continue
    
    # Handle list items - simplified approach
    if trimmedLine.startsWith("- ") or trimmedLine.startsWith("* ") or trimmedLine.startsWith("+ "):
      # Calculate indentation level
      var indentLevel = 0
      var j = 0
      while j < line.len and line[j] == ' ':
        indentLevel += 1
        j += 1
      
      # Convert indentation to visual nesting (2 spaces per level)
      let visualIndent = "  ".repeat(indentLevel div 2)
      let listText = visualIndent & "• " & trimmedLine[2..^1]
      result.add(listText)
      i += 1
      continue

    # Handle numbered lists with proper nesting
    var numListMatch = false
    var dotPos = -1
    # Find the dot position after digits
    for j in 0..<min(line.len, 10):
      if line[j].isDigit:
        continue
      elif line[j] == '.' and j > 0:
        # Check if there's a space after the dot
        if j + 1 < line.len and line[j + 1] == ' ':
          dotPos = j
          numListMatch = true
          break
        else:
          break
      else:
        break

    if numListMatch:
      # Calculate indentation level
      var indentLevel = 0
      var j = 0
      while j < line.len and line[j] == ' ':
        indentLevel += 1
        j += 1
      
      # Convert indentation to visual nesting
      let visualIndent = "  ".repeat(indentLevel div 2)
      let listText = visualIndent & line[dotPos-1..dotPos] & " " & line[dotPos + 2..^1]
      result.add(listText)
      i += 1
      continue
    
    # Regular text
    result.add(line)
    i += 1
  
  # Flush any remaining code block
  if inCodeBlock and codeBlockContent.len > 0:
    # Calculate max width needed
    var maxWidth = 10  # Minimum width
    for contentLine in codeBlockContent:
      maxWidth = max(maxWidth, contentLine.len)
    
    # Add top border
    result.add("┌" & "─".repeat(maxWidth + 2) & "┐")

    # Add content lines
    for contentLine in codeBlockContent:
      let paddedLine = contentLine & " ".repeat(maxWidth - contentLine.len)
      result.add("│ " & paddedLine & " │")
    
    # Add bottom border
    result.add("└" & "─".repeat(maxWidth + 2) & "┘")
  
  # Flush any remaining table
  if inTable:
    let tableLines = renderTableRows(tableHeaders.filter(proc(x: string): bool = x.len() > 0), tableRows, tableAlignments)
    result.add(tableLines)

proc markdownRowReCal(md: Markdown) =
  if md.showMarkdown:
    md.textRows = parseMarkdown(md.text, md.markdownStyle)
    
    # Apply word wrapping if enabled
    if md.wordwrap:
      var wrappedRows: seq[string] = @[]
      for row in md.textRows:
        if row.len > (md.x2 - md.x1):
          let wrapped = row.wrapWords(maxLineWidth = md.x2 - md.x1, splitLongWords = true)
          for wrappedLine in wrapped.splitLines():
            wrappedRows.add(wrappedLine)
        else:
          wrappedRows.add(row)
      md.textRows = wrappedRows
  else:
    # Raw text mode
    if md.wordwrap:
      let rows = md.text.len / toInt(md.x2.toFloat() * 0.5)
      md.textRows = md.text.splitBySize(md.x2 - md.x1, toInt(rows) + md.style.paddingX2)
    else:
      md.textRows = md.text.textWindow(md.x2 - md.x1, md.cursor)

proc renderMarkdownRow(md: Markdown, text: string, row: int) =
  if md.showMarkdown:
    # Parse inline formatting for this row
    let segments = parseInlineMarkdown(text, md.markdownStyle)
    var currentX = md.x1
    
    # Handle leading spaces for indentation
    var i = 0
    while i < text.len and text[i] == ' ':
      currentX += 1
      i += 1
    
    # Render the actual content (skip leading spaces already handled)
    for segment in segments:
      let segmentText = segment.text
      if currentX + segmentText.len <= md.x2:
        # Pass style and resetStyle as separate arguments to the write macro
        if segment.textStyle.len > 0:
          md.tb.write(currentX, md.posY + row, segment.fg, segment.bg, segmentText, segment.textStyle, resetStyle)
        else:
          md.tb.write(currentX, md.posY + row, segment.fg, segment.bg, segmentText, resetStyle)
        currentX += segmentText.len
      else:
        # Truncate if too long
        let availableWidth = md.x2 - currentX
        if availableWidth > 0:
          let truncated = segmentText[0..<min(availableWidth, segmentText.len)]
          # Pass style and resetStyle as separate arguments to the write macro
          if segment.textStyle.len > 0:
            md.tb.write(currentX, md.posY + row, segment.fg, segment.bg, truncated, segment.textStyle, resetStyle)
          else:
            md.tb.write(currentX, md.posY + row, segment.fg, segment.bg, truncated, resetStyle)
        break
  else:
    md.renderRow(text, row)

## Mouse events
proc onMouse*(md: Markdown, button: MouseButton, fn: EventFn[Markdown]) =
  md.mouseEvents[button] = fn

proc handleMouseEvent*(md: Markdown, mouseInfo: MouseInfo) =
  if mouseInfo.scroll:
    case mouseInfo.scrollDir
    of sdUp:
      md.rowCursor = max(0, md.rowCursor - 3)
    of sdDown:
      md.rowCursor = min(md.rowCursor + 3, max(md.textRows.len - md.size, 0))
    else:
      discard
    md.render()
  elif mouseInfo.action == mbaPressed and md.mouseEvents.hasKey(mouseInfo.button):
    let fn = md.mouseEvents[mouseInfo.button]
    fn(md, @[$mouseInfo.x, $mouseInfo.y])

proc help(md: Markdown, args: varargs[string]) = 
  let wsize = ((md.width - md.posX).toFloat * 0.3).toInt()
  let hsize = ((md.height - md.posY).toFloat * 0.3).toInt()
  var display = newMarkdown(md.x2 - wsize, md.y2 - hsize, 
                           md.x2, md.y2, title="help",
                           bgColor=bgWhite, fgColor=fgBlack,
                           tb=md.tb, statusbar=false, 
                           enableHelp=false)
  var helpText: string = if md.helpText == "":
    " [Enter] to select\n" &
    " [M]     toggle markdown\n" &
    " [?]     for help\n" &
    " [Tab]   to go next widget\n" & 
    " [Esc]   to exit this window"
  else: md.helpText
  display.text = helpText
  display.illwillInit = true
  md.render()
  display.onControl()
  display.clear()

proc toggleWordWrap(md: Markdown, args: varargs[string]) = 
  md.wordwrap = not md.wordwrap

proc toggleMarkdown(md: Markdown, args: varargs[string]) = 
  md.showMarkdown = not md.showMarkdown

proc renderStatusbar(md: Markdown) =
  if md.events.hasKey("statusbar"):
    md.call("statusbar")
  else:
    let mode = if md.showMarkdown: "MD" else: "RAW"
    let borderSize = if md.border: 2 else: 0
    let availableWidth = (md.x2 - md.x1 ) + 1
    
    md.statusbarText = " " & $md.rowCursor & ":" & $(max(0, md.textRows.len() - md.size)) & " [" & mode & "] "
    
    if md.statusbarText.len > availableWidth:
      md.statusbarText = md.statusbarText[0..availableWidth-1]
    else:
      md.statusbarText = md.statusbarText & " ".repeat(availableWidth - md.statusbarText.len)
    
    md.renderCleanRect(md.x1, md.height, availableWidth, md.height)
    md.tb.write(md.x1, md.height - 1, bgWhite, fgBlack, md.statusbarText, resetStyle)
    
    let indicators = if md.showMarkdown: " M " else: ""
    let ww = if md.wordwrap: " W " else: ""
    let q = if md.enableHelp: "[?]" else: ""
    
    var indicatorText = indicators & ww & q
    let indicatorStartX = md.x2 - indicatorText.len - (if md.border: 1 else: 0)
    if indicatorStartX >= md.x1:
      md.tb.write(indicatorStartX, md.height - 1, bgWhite, fgBlack, indicatorText, resetStyle)
  
  if md.border: md.renderBorder()

method resize*(md: Markdown) =
  let statusbarSize = if md.statusbar: 1 else: 0
  md.size = md.height - statusbarSize - md.posY - (md.paddingY1 * 2)

proc on*(md: Markdown, event: string, fn: EventFn[Markdown]) =
  md.events[event] = fn

proc on*(md: Markdown, key: Key, fn: EventFn[Markdown]) {.raises: [EventKeyError].} =
  if key in forbiddenKeyBind: 
    raise newException(EventKeyError, $key & " is used for widget default behavior, forbidden to overwrite")
  md.keyEvents[key] = fn

method call*(md: Markdown, event: string, args: varargs[string]) =
  if md.events.hasKey(event):
    let fn = md.events[event]
    fn(md, args)

method call*(md: MarkdownObj, event: string, args: varargs[string]) =
  if md.events.hasKey(event):
    let mdRef = md.asRef()
    let fn = md.events[event]
    fn(mdRef, args)

proc call(md: Markdown, key: Key, args: varargs[string]) =
  if md.keyEvents.hasKey(key):
    let fn = md.keyEvents[key]
    fn(md, args)

method render*(md: Markdown) =
  if not md.illwillInit: return
  
  if md.useCustomTextRow: 
    let customFn = md.customRowRecal.get
    md.textRows = customFn(md.text, md)
  else: 
    md.markdownRowReCal()
  
  md.clear()
  md.renderBorder()
  md.renderTitle()
  
  var index = 1
  if md.textRows.len > 0:
    let rowStart = min(md.rowCursor, md.textRows.len - 1)
    let rowEnd = min(md.textRows.len - 1, rowStart + md.size)
    
    for i in rowStart..min(rowEnd, max(0, md.textRows.len - 1)):
      let row = md.textRows[i]
      md.renderMarkdownRow(row, index)
      inc index
  
  if md.statusbar:
    md.renderStatusbar()
  
  md.tb.display()

proc resetCursor*(md: Markdown) =
  md.rowCursor = 0
  md.cursor = 0

method poll*(md: Markdown) =
  var widgetEv: WidgetBgEvent
  if md.channel.tryRecv(widgetEv):
    md.call(widgetEv.event, widgetEv.args)
    md.render()

method onUpdate*(md: Markdown, key: Key) =
  if md.visibility == false: 
    md.cursor = 0
    md.rowCursor = 0
    return
  
  md.call("preupdate", $key) 
  
  case key
  of Key.Mouse:
    if md.mouseEnabled:
      let mouseInfo = getMouse()
      md.handleMouseEvent(mouseInfo)
  of Key.None: discard
  of Key.Up:
    md.rowCursor = max(0, md.rowCursor - 1)
  of Key.Down:
    md.rowCursor = min(md.rowCursor + 1, max(md.textRows.len - md.size, 0))
  of Key.Right:
    md.cursor += 1
    if md.cursor >= md.x2 - md.x1:
      md.cursor = md.x2 - md.x1 - 1
  of Key.Left:
    md.cursor = max(0, (md.cursor - 1))
  of Key.PageUp:
    md.rowCursor = max(0, md.rowCursor - md.size)
  of Key.PageDown:
    md.rowCursor = min(md.rowCursor + md.size, max(md.textRows.len - md.size, 0))
  of Key.Home:
    md.rowCursor = 0
  of Key.End:
    md.rowCursor = max(md.textRows.len - md.size, 0)
  of Key.Escape, Key.Tab:
    md.focus = false
  else:
    if key in forbiddenKeyBind: discard
    elif md.keyEvents.hasKey(key):
      md.call(key, "")
  
  md.render()
  md.call("postupdate", $key)

method onControl*(md: Markdown) =
  if md.visibility == false: 
    md.cursor = 0
    md.rowCursor = 0
    return
  
  md.focus = true
  if md.useCustomTextRow: 
    let customFn = md.customRowRecal.get
    md.textRows = customFn(md.text, md)
  else: 
    md.markdownRowReCal()
  
  md.clear()
  while md.focus:
    var key = getKeyWithTimeout(md.rpms)
    case key
    of Key.Mouse:
      if md.mouseEnabled:
        let mouseInfo = getMouse()
        md.handleMouseEvent(mouseInfo)
    else:
      md.onUpdate(key)
    sleep(md.rpms)

method wg*(md: Markdown): ref BaseWidget = md

proc text*(md: Markdown): string = md.text

proc val(md: Markdown, val: string) =
  md.text = val
  if md.width > 0:
    if md.useCustomTextRow: 
      let customFn = md.customRowRecal.get
      md.textRows = customFn(md.text, md)
    else: 
      md.markdownRowReCal()
    md.render()

proc `text=`*(md: Markdown, text: string) =
  md.val(text)

proc `text=`*(md: Markdown, text: string, customRowRecal: proc(text: string, md: Markdown): seq[string]) =
  md.textRows = customRowRecal(text, md)
  md.useCustomTextRow = true
  md.val(text)

proc `wordwrap=`*(md: Markdown, wrap: bool) =
  if md.visibility:
    md.wordwrap = wrap
    md.render()

proc `showMarkdown=`*(md: Markdown, show: bool) =
  if md.visibility:
    md.showMarkdown = show
    md.render()

proc add*(md: Markdown, text: string, autoScroll=false) =
  md.text &= text
  md.val(md.text)
  if autoScroll and md.textRows.len > md.size: 
    md.rowCursor = min(md.textRows.len - 1, md.rowCursor + 1)

proc `markdownStyle=`*(md: Markdown, style: MarkdownStyle) =
  md.markdownStyle = style
  if md.visibility:
    md.render()