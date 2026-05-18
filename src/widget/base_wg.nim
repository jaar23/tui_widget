import illwill, threading/channels, unicode, std/wordwrap
import os, osproc, streams

type
  Alignment* = enum
    Left, Center, Right

  Mode* = enum
    Normal, Filter

  SelectionStyle* = enum
    Highlight, Arrow, HighlightArrow

  ViMode* = enum
    Normal, Insert, Visual

  CursorStyle* = enum 
    Block, Ibeam, Underline

  WidgetSize* = range[0.0..1.0]
  
  WidgetState* = enum
    Idle, Render, Update, Autocomplete

  WidgetStyle* = object
    fgColor*: ForegroundColor
    bgColor*: BackgroundColor
    border*: bool
    paddingX1*: int
    paddingX2*: int
    paddingY1*: int
    paddingY2*: int
    pressedBgcolor*: BackgroundColor

  WidgetBgEvent* = object
    widgetId*: string
    event*: string
    args*: seq[string]
    error*: string

  #############################
  # posX, posY-----------width
  # | 
  # |
  # |
  # |
  # |
  # height control /  mode / status
  ############################
  BaseWidget* = object of RootObj
    width*: int
    height*: int
    posX*: int
    posY*: int
    size*: int
    id*: string = ""
    title*: string
    focus*: bool = false
    tb*: TerminalBuffer
    style*: WidgetStyle
    cursor*: int = 0
    rowCursor*: int = 0
    colCursor*: int = 0
    statusbar*: bool = true
    statusbarText*: string = ""
    statusbarSize*: int = 0
    useCustomStatusbar*: bool = false
    visibility*: bool = true
    groups*: bool = false
    debug*: bool = false
    rpms*: int = 50
    illwillInit*: bool = false
    channel: Chan[WidgetBgEvent]
    blocking*: bool = false
    helpText*: string = ""
    enableHelp*: bool = true
    origWidth*: int
    origHeight*: int
    origPosX*: int
    origPosY*: int
    onMouse*: proc(wg: ref BaseWidget, mouseInfo: MouseInfo) {.closure.}
    suppressDisplay*: bool = false
    focusable*: bool = true   # Tab cycling / mouse click skip this widget when false
    postDisplay*: proc(wg: ref BaseWidget) {.closure.}
      ## Optional hook fired AFTER illwill's tb.display() flushes a frame.
      ## Used by widgets that need to write raw text directly to stdout
      ## (e.g. CJK / wide-glyph overlays) — letting the terminal handle
      ## visual width natively instead of illwill's one-cell-per-rune model.

  EventFn*[T] = proc (wg: T, args: varargs[string]): void

  BoolEventFn*[T] = proc (wg: T, arg: bool): void

  EventKeyError* = object of CatchableError

  XYInitError* = object of CatchableError

  GlobalErrorHandler* = proc(widgetId: string, where: string,
                             msg: string, trace: string) {.closure, gcsafe.}


var globalErrorHandler*: GlobalErrorHandler = nil
  ## Optional app-level hook for caught widget exceptions. nil = no-op.
  ## Must be gcsafe — also invoked from the background-task thread.
  ## Future log file / banner / throttling / telemetry plug in here without
  ## modifying any call site.


proc consoleWidth*(): int =
  return terminalWidth() - 2

proc consoleHeight*(): int =
  return terminalHeight() - 2


# ---- Visual-width helpers for East-Asian wide / fullwidth / emoji ----------
# illwill stores one Rune per TB cell and advances by one cell per rune, but
# wide glyphs actually occupy two terminal columns. Widgets that contain
# free-form text (chat displays, input boxes) need to wrap and clip by
# *visual* width so the output stays inside their bounds — and any widget
# that wants pixel-perfect CJK rendering should overlay text directly via
# stdout (see BaseWidget.postDisplay) rather than going through tb.write.

proc runeWidth*(r: Rune): int =
  ## Returns 2 for East-Asian Wide / Fullwidth / Emoji ranges, 0 for control
  ## characters, 1 otherwise.
  let cp = r.int32
  if cp == 0 or cp < 0x20 or cp == 0x7F: return 0
  if (cp >= 0x1100 and cp <= 0x115F) or   # Hangul Jamo
     (cp >= 0x2E80 and cp <= 0x303E) or   # CJK Radicals / Punctuation
     (cp >= 0x3041 and cp <= 0x33FF) or   # Hiragana / Katakana / Bopomofo / etc
     (cp >= 0x3400 and cp <= 0x4DBF) or   # CJK Ext A
     (cp >= 0x4E00 and cp <= 0x9FFF) or   # CJK Unified
     (cp >= 0xA000 and cp <= 0xA4CF) or   # Yi
     (cp >= 0xAC00 and cp <= 0xD7A3) or   # Hangul Syllables
     (cp >= 0xF900 and cp <= 0xFAFF) or   # CJK Compatibility
     (cp >= 0xFE30 and cp <= 0xFE4F) or   # CJK Compatibility Forms
     (cp >= 0xFF00 and cp <= 0xFF60) or   # Fullwidth Forms
     (cp >= 0xFFE0 and cp <= 0xFFE6) or   # Fullwidth signs
     (cp >= 0x1F300 and cp <= 0x1F9FF):   # Emoji block
    return 2
  return 1

proc visualWidth*(s: string): int =
  ## Sum of `runeWidth` over the runes in `s`.
  for r in s.runes: result += runeWidth(r)

proc clipToVisualWidth*(s: string, cells: int): string =
  ## Returns the longest rune-prefix of `s` whose total visual width is
  ## ≤ `cells`. Used to clip an overlay row to its widget's inner width.
  result = ""
  if cells <= 0: return
  var used = 0
  for r in s.runes:
    let w = runeWidth(r)
    if used + w > cells: break
    result.add($r)
    used += w


const MinWidgetSpan* = 1
  ## Minimum cells a widget needs on each axis after clamping. Set to 1 so
  ## borderless 1-row widgets (e.g. a status bar) are usable. Widgets that
  ## request a border but end up shorter than the border itself simply lose
  ## the border via the bounds guard in `renderBorder` — never stripes.


proc clampToConsole*(bw: ref BaseWidget) =
  ## Bring the widget's posX/posY/width/height inside the current console
  ## size and refuse to render inverted bounds. Inverted bounds (width <
  ## posX, height < posY) make illwill's drawRect walk across many rows
  ## drawing stripe artifacts — see lmstudio-example-render-bug.png.
  ##
  ## Policy:
  ## 1. If width < posX or height < posY, the user clearly made a mistake
  ##    (no sensible repair exists). Hide the widget.
  ## 2. Clamp end coords (width/height) DOWN to console size.
  ## 3. Clamp start coords (posX/posY) DOWN into the console — but never
  ##    move them just to make room for `MinWidgetSpan`; respect the
  ##    user's requested origin so adjacent widgets don't overlap.
  ## 4. If after clamping the live span on either axis is below
  ##    `MinWidgetSpan`, hide the widget — better gone than a degenerate
  ##    1- or 2-cell box.
  ##
  ## Does NOT touch origPosX/origPosY/origWidth/origHeight — auto-resize
  ## keeps the user's original intent so the widget reappears at its
  ## requested layout once the terminal grows back.
  if bw.width < bw.posX or bw.height < bw.posY:
    bw.visibility = false
    return
  let cw = consoleWidth()
  let ch = consoleHeight()
  bw.width  = min(bw.width,  cw)
  bw.height = min(bw.height, ch)
  bw.posX   = max(0, min(bw.posX, cw - 1))
  bw.posY   = max(0, min(bw.posY, ch - 1))
  if bw.width - bw.posX + 1 < MinWidgetSpan or
     bw.height - bw.posY + 1 < MinWidgetSpan:
    bw.visibility = false


method onControl*(this: ref BaseWidget): void {.base.} =
  #child needs to implement this!
  this.focus = false


method onUpdate*(this: ref BaseWidget, key: Key): void {.base.} =
  echo ""


method call*(this: ref BaseWidget, event: string, args: varargs[string]): void {.base.} = 
  echo ""


method call*(this: ref BaseWidget, event: string, args: bool): void {.base.} = 
  echo ""


method call*(this: BaseWidget, event: string, args: varargs[string]): void {.base.} = 
  echo ""


method call*(this: BaseWidget, event: string, args: bool): void {.base.} = 
  echo ""


method poll*(this: ref BaseWidget): void {.base.} =
  echo ""


proc `channel=`*(this: ref BaseWidget, channel: Chan[WidgetBgEvent]) = this.channel = channel


proc channel*(this: ref BaseWidget): var Chan[WidgetBgEvent] = this.channel


proc `channel=`*(this: var BaseWidget, channel: Chan[WidgetBgEvent]) = this.channel = channel


proc channel*(this: var BaseWidget): var Chan[WidgetBgEvent] = this.channel


proc asRef*[T](x: T): ref T = new(result); result[] = x


method render*(this: ref BaseWidget): void {.base.} = 
  echo ""


method wg*(this: ref BaseWidget): ref BaseWidget {.base.} = this


method setChildTb*(this: ref BaseWidget, tb: TerminalBuffer): void {.base.} =
  #child needs to implement this!
  echo ""


method onError*(this: ref BaseWidget, errorCode: string) {.base.} =
  this.tb.fill(this.posX, this.posY, this.width, this.height, " ")
  this.tb.write(this.posX +  1, this.posY, fgRed,
                bgWhite, "[!] " & wrapWords(errorCode, this.width - this.posX),
                resetStyle)


template safeCall*(wg: ref BaseWidget, where: string, body: untyped) =
  ## Run `body` with all CatchableErrors routed to wg.onError so the main
  ## loop never crashes from user widget code. `where` is a short context
  ## label ("onUpdate" / "onMouseEvent" / "poll" / "render" / "onControl")
  ## that prefixes the error so users can tell which surface failed.
  try:
    body
  except CatchableError:
    let e = getCurrentException()
    let msg = (if e.isNil: "unknown" else: e.msg)
    let trc = (if e.isNil: ""        else: e.getStackTrace())
    if not globalErrorHandler.isNil:
      try: globalErrorHandler(wg.id, where, msg, trc)
      except CatchableError: discard
    try:
      wg.onError(where & ": " & msg)
    except CatchableError:
      discard  # never cascade — swallow secondary failure


proc bg*(bw: ref BaseWidget, bgColor: BackgroundColor) =
  bw.style.bgColor = bgColor


proc fg*(bw: ref BaseWidget, fgColor: ForegroundColor) =
  bw.style.fgColor = fgColor


proc bg*(bw: ref BaseWidget): BackgroundColor = bw.style.bgColor


proc fg*(bw: ref BaseWidget): ForegroundColor = bw.style.fgColor


proc border*(bw: ref BaseWidget, bordered: bool) =
  bw.style.border = bordered


proc border*(bw: ref BaseWidget): bool = bw.style.border


proc `border=`*(bw: ref BaseWidget, bordered: bool) = 
  bw.style.border = bordered
  if bordered:
    bw.style.paddingX1 = 1
    bw.style.paddingX2 = 1
    bw.style.paddingY1 = 1
    bw.style.paddingY2 = 1 
  else:
    bw.style.paddingX1 = 0
    bw.style.paddingX2 = 0
    bw.style.paddingY1 = 0
    bw.style.paddingY2 = 0 


proc padding*(bw: ref BaseWidget, x1:int, x2: int, y1: int, y2: int) =
  bw.style.paddingX1 = x1
  bw.style.paddingX2 = x2
  bw.style.paddingY1 = y1
  bw.style.paddingY2 = y2 


proc paddingX*(bw: ref BaseWidget, x1:int, x2: int) =
  bw.style.paddingX1 = x1
  bw.style.paddingX2 = x2


proc paddingY*(bw: ref BaseWidget, y1: int, y2: int) =
  bw.style.paddingY1 = y1
  bw.style.paddingY2 = y2


proc paddingX1*(bw: ref BaseWidget): int = bw.style.paddingX1


proc paddingX2*(bw: ref BaseWidget): int = bw.style.paddingX2


proc paddingY1*(bw: ref BaseWidget): int = bw.style.paddingY1


proc paddingY2*(bw: ref BaseWidget): int = bw.style.paddingY2


####################### w
# x1,y1-------------x2,y1
# |                 |
# |                 |
# |                 |
# |                 |
# x1,y2-------------x2,y2
###################### h
proc widthPaddLeft*(bw: ref BaseWidget): int =
  result = bw.posX
  if bw.style.border:
    result = bw.posX + bw.style.paddingX1


proc widthPaddRight*(bw: ref BaseWidget): int =
  result = bw.width
  if bw.style.border:
    result = bw.width - bw.style.paddingX2


proc heightPaddTop*(bw: ref BaseWidget): int =
  result = bw.posY
  if bw.style.border:
    result = bw.posY + bw.style.paddingY1


proc heightPaddBottom*(bw: ref BaseWidget): int =
  result = bw.height
  if bw.style.border:
    result = bw.height - bw.style.paddingY2


proc offsetLeft*(bw: ref BaseWidget): int =
  result = bw.width - bw.style.paddingX1


proc offsetRight*(bw: ref BaseWidget): int =
  result = bw.width - bw.style.paddingX2


proc offsetTop*(bw: ref BaseWidget): int =
  result = bw.height - bw.style.paddingY1


proc offsetBottom*(bw: ref BaseWidget): int =
  result = bw.posY + bw.size + bw.style.paddingY2


proc x1*(bw: ref BaseWidget): int = bw.widthPaddLeft


proc y1*(bw: ref BaseWidget): int = bw.heightPaddTop


proc x2*(bw: ref BaseWidget): int = bw.widthPaddRight


proc y2*(bw: ref BaseWidget): int = bw.heightPaddBottom


proc toConsoleWidth*(w: float): int = (consoleWidth().toFloat * w).toInt


proc toConsoleHeight*(h: float): int = (consoleHeight().toFloat * h).toInt

proc wsPercent*(percent: float): WidgetSize =
  ## Create a WidgetSize from percentage (0.0 to 1.0)
  ## Example: wsPercent(0.5) = 50% of available space
  result = WidgetSize(percent)

proc wsPercent*(percent: int): WidgetSize =
  ## Create a WidgetSize from percentage (0 to 100)
  ## Example: wsPercent(50) = 50% of available space
  result = WidgetSize(percent.float / 100.0)

# Helper conversion functions
proc toConsoleWidth*(ws: WidgetSize): int = 
  toConsoleWidth(ws.float)

proc toConsoleHeight*(ws: WidgetSize): int = 
  toConsoleHeight(ws.float)

method resize*(bw: ref BaseWidget): void {.base.} =
  return


proc keepOriginalSize*(bw: ref BaseWidget) = 
  bw.origWidth = bw.width
  bw.origHeight = bw.height
  bw.origPosX = bw.posX
  bw.origPosY = bw.posY


proc fill*(tb: var TerminalBuffer, x1, y1, x2, y2: Natural, 
           bgColor: BackgroundColor, fgColor: ForegroundColor, ch: string = " ") =
  ## Override illwill fill with diff foreground and background
  ## Fills a rectangular area with the `ch` character using the current text
  ## attributes. The rectangle is clipped to the extends of the terminal
  ## buffer and the call can never fail.
  if x1 < tb.width and y1 < tb.height:
    let
      c = TerminalChar(ch: ch.runeAt(0), fg: fgColor, bg: bgColor,
                       style: tb.getStyle)

      xe = min(x2, tb.width-1)
      ye = min(y2, tb.height-1)

    for y in y1..ye:
      for x in x1..xe:
        tb[x, y] = c


proc renderBorder*(bw: ref BaseWidget) =
  if not bw.style.border: return
  # Inverted bounds make illwill's drawRect smear stripes across the screen.
  if bw.width <= bw.posX or bw.height <= bw.posY: return
  bw.tb.drawRect(bw.width, bw.height, bw.posX, bw.posY, doubleStyle = bw.focus)


proc renderTitle*(bw: ref BaseWidget, index: int = 0) =
  if bw.title != "":
    if bw.focus:
      bw.tb.write(bw.widthPaddLeft, bw.posY + index, styleBright, bw.bg, bw.fg, bw.title, resetStyle)
    else:
      bw.tb.write(bw.widthPaddLeft, bw.posY + index, styleDim, bw.title, resetStyle)



# deprecated
proc renderCleanRow*(bw: ref BaseWidget, index = 0, cleanWith=" ") =
  bw.tb.fill(bw.x1, bw.posY + index, bw.x2, bw.posY + index, cleanWith)
  # for y in bw.posY + index..bw.posY + index:
  #   for x in bw.x1..bw.x2:
  #     bw.tb[x, y] = TerminalChar(ch: " ".runeAt(0), fg: bw.tb.getForegroundColor, bg: bw.tb.getBackgroundColor, style: bw.tb.getStyle)
  #stdout.flushFile()

proc renderCleanRect*(bw: ref BaseWidget, x1, y1, x2, y2: int, cleanWith=" ") =
  bw.tb.fill(x1, y1, x2, y2, cleanWith)


proc renderRect*(bw: ref BaseWidget, x1, y1, x2, y2: int, 
                 bgColor: BackgroundColor, fgColor: ForegroundColor, fillWith=" ") =
  bw.tb.fill(x1, y1, x2, y2, bgColor, fgColor, fillWith)


proc renderRow*(bw: ref BaseWidget, content: string, index: int = 0) =
  bw.tb.write(bw.x1, bw.posY + index, bw.fg, bw.bg, content)


proc renderRow*(bw: ref BaseWidget, bgColor: BackgroundColor, fgColor: ForegroundColor, 
                content: string, index: int = 0, withoutPadding = false) =
  let x1 = if withoutPadding: bw.posX else: bw.x1
  bw.tb.write(x1, bw.posY + index, bgColor, fgColor, content, resetStyle)


proc clear*(bw: ref BaseWidget) =
  if bw.width <= bw.posX or bw.height <= bw.posY: return
  bw.tb.fill(bw.posX, bw.posY, bw.width, bw.height, bw.bg, bw.fg, " ")


proc rerender*(bw: ref BaseWidget) =
  if bw.width == 0 or bw.height == 0:
    return
  bw.clear()
  bw.render()


method resetCursor*(bw: ref BaseWidget): void {.base.} =
  bw.cursor = 0
  bw.rowCursor = 0
  bw.colCursor = 0


proc show*(bw: ref BaseWidget, resetCursor = false) = 
  if resetCursor: bw.resetCursor()
  bw.visibility = true
  bw.clear()
  bw.render()


proc hide*(bw: ref BaseWidget) = 
  bw.visibility = false
  bw.clear()


proc experimental*(bw: ref BaseWidget) =
  let text = " experimental "
  bw.tb.write(bw.x2 - len(text) - 3, bw.height - 1, bgWhite, fgBlack, text, resetStyle)


method contains*(wg: ref BaseWidget, x, y: int): bool {.base.} =
  ## Hit-test for mouse coordinates. posX/posY are top-left TB cells,
  ## width/height are bottom-right TB cells. illwill mouseInfo.x/y are
  ## already 0-indexed TB cell coordinates so they match directly.
  ## Widgets with overflow regions (e.g. expanded dropdown) override this.
  result = x >= wg.posX and x <= wg.width and
           y >= wg.posY and y <= wg.height

method onMouseEvent*(wg: ref BaseWidget, mouseInfo: MouseInfo) {.base.} =
  ## Default mouse event handler — calls user-registered onMouse callback.
  if not wg.onMouse.isNil:
    wg.onMouse(wg, mouseInfo)

proc onMouse*(wg: ref BaseWidget, handler: proc(wg: ref BaseWidget, mouseInfo: MouseInfo) {.closure.}) =
  ## Set mouse event handler
  wg.onMouse = handler

# OS-specific clipboard functions
proc getClipboardText*(): string =
  ## Get text from OS clipboard
  when defined(windows):
    try:
      let (output, _) = execCmdEx("powershell -Command \"Get-Clipboard\"")
      return output.strip()
    except:
      return ""
  elif defined(macosx):
    try:
      let (output, _) = execCmdEx("pbpaste")
      return output.strip()
    except:
      return ""
  else: # Linux/Unix
    # Try xclip first, then xsel as fallback
    try:
      let (output, exitCode) = execCmdEx("xclip -o -selection clipboard")
      if exitCode == 0:
        return output.strip()
    except:
      discard
    try:
      let (output, exitCode) = execCmdEx("xsel --clipboard --output")
      if exitCode == 0:
        return output.strip()
    except:
      discard
    return ""

proc setClipboardText*(text: string) =
  ## Set text to OS clipboard
  when defined(windows):
    try:
      # Use a temporary file approach for Windows to avoid shell escaping issues
      let tempFile = getTempDir() / "nim_clipboard.tmp"
      writeFile(tempFile, text)
      discard execCmdEx("powershell -Command \"Get-Content '" & tempFile & "' | Set-Clipboard\"")
      removeFile(tempFile)
    except:
      discard
  elif defined(macosx):
    try:
      # Use printf instead of echo to handle special characters properly
      let process = startProcess("pbcopy", options={poStdErrToStdOut, poUsePath})
      let inputStream = process.inputStream()
      inputStream.write(text)
      inputStream.close()
      discard process.waitForExit()
      process.close()
    except:
      discard
  else: # Linux/Unix
    # Try xclip first, then xsel as fallback
    try:
      let process = startProcess("xclip", args=["-selection", "clipboard"], 
                                options={poStdErrToStdOut, poUsePath})
      let inputStream = process.inputStream()
      inputStream.write(text)
      inputStream.close()
      discard process.waitForExit()
      process.close()
    except:
      try:
        let process = startProcess("xsel", args=["--clipboard", "--input"],
                                  options={poStdErrToStdOut, poUsePath})
        let inputStream = process.inputStream()
        inputStream.write(text)
        inputStream.close()
        discard process.waitForExit()
        process.close()
      except:
        discard