import illwill, threading/channels, unicode

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

  EventFn*[T] = proc (wg: T, args: varargs[string]): void

  BoolEventFn*[T] = proc (wg: T, arg: bool): void

  EventKeyError* = object of CatchableError

  XYInitError* = object of CatchableError


proc consoleWidth*(): int =
  return terminalWidth() - 2

proc consoleHeight*(): int = 
  return terminalHeight() - 2


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
  this.tb.write(this.posX +  1, this.posY, fgRed, bgWhite, "[!] " & errorCode, resetStyle)


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
  if bw.style.border:
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
  bw.tb.fill(bw.posX, bw.posY, bw.width, bw.height, bw.bg, bw.fg, " ")


proc rerender*(bw: ref BaseWidget)  =
  # not to render widget without valid x,y
  if bw.posX == 0 and bw.posY == 0:
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
  bw.tb.write(bw.x2 - len(text) - 3, bw.height, bgWhite, fgBlack, text, resetStyle)


