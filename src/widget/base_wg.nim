import illwill

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


  WidgetStyle* = object
    fgColor*: ForegroundColor
    bgColor*: BackgroundColor
    border*: bool
    paddingX1*: int
    paddingX2*: int
    paddingY1*: int
    paddingY2*: int

  #############################
  # posX, posY-----------width
  # | 
  # |
  # |
  # |
  # |
  # height
  ############################
  BaseWidget* = object of RootObj
    width*: int
    height*: int
    posX*: int
    posY*: int
    size*: int
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
    visibility*: bool = true
    groups*: bool = false
    debug*: bool = false
    refreshWaitTime*: int = 50
    illwillInit*: bool = false

  CallbackProcedure* = proc(x: string): void

  EnterEventProcedure* = proc(x: string): void

  SpaceEventProcedure* = proc(x: string, b: bool): void

  UpEventProcedure* = proc(bw: ref BaseWidget): void

  DownEventProcedure* = proc(bw: ref BaseWidget): void

  CommandEvent* = proc(bw: ref BaseWidget, command: string): void
  

proc consoleWidth*(): int =
  return terminalWidth() - 2

proc consoleHeight*(): int = 
  return terminalHeight() - 2


method onControl*(this: ref BaseWidget): void {.base.} =
  #child needs to implement this!
  echo ""


method onControl*(this: ref BaseWidget, cb: proc(args: varargs[string])): void {.base.} =
  #child needs to implement this!
  echo ""


method onControl*(this: ref BaseWidget, cb: SpaceEventProcedure): void {.base.} =
  #child needs to implement this!
  echo ""


# method onControl*(this: ref BaseWidget, cb: CallbackProcedure): void {.base.} =
#   #child needs to implement this!
#   echo ""


method onControl*(this: ref BaseWidget, cb: EnterEventProcedure): void {.base.} =
  #child needs to implement this!
  echo ""


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


proc renderBorder*(bw: ref BaseWidget) =
  if bw.style.border:
    bw.tb.drawRect(bw.width, bw.height, bw.posX, bw.posY, doubleStyle = bw.focus)

proc renderTitle*(bw: ref BaseWidget, index: int = 0) =
  if bw.title != "":
    bw.tb.write(bw.widthPaddLeft, bw.posY + index, bw.title, resetStyle)


proc renderCleanRow*(bw: ref BaseWidget, index = 0, cleanWith=" ") =
  bw.tb.fill(bw.x1, bw.posY + index, bw.x2, bw.posY + index, cleanWith)
  # for y in bw.posY + index..bw.posY + index:
  #   for x in bw.x1..bw.x2:
  #     bw.tb[x, y] = TerminalChar(ch: " ".runeAt(0), fg: bw.tb.getForegroundColor, bg: bw.tb.getBackgroundColor, style: bw.tb.getStyle)
  #stdout.flushFile()

proc renderCleanRect*(bw: ref BaseWidget, x1, y1, x2, y2: int, cleanWith=" ") =
  bw.tb.fill(x1, y1, x2, y2, cleanWith)


proc renderRow*(bw: ref BaseWidget, content: string, index: int = 0) =
  bw.tb.write(bw.x1, bw.posY + index, bw.style.bgColor, bw.style.fgColor, content, resetStyle)


proc renderRow*(bw: ref BaseWidget, bgColor: BackgroundColor, fgColor: ForegroundColor, 
                content: string, index: int = 0, withoutPadding = false) =
  let x1 = if withoutPadding: bw.posX else: bw.x1
  bw.tb.write(x1, bw.posY + index, bgColor, fgColor, content, resetStyle)


proc clear*(bw: ref BaseWidget) =
  bw.tb.fill(bw.posX, bw.posY, bw.width, bw.height, " ")
  #bw.tb.fill(bw.x1, bw.y1, bw.tb.width - 1, bw.tb.height - 1, "*")


proc rerender*(bw: ref BaseWidget) =
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

# proc renderStatusBar*(bw: ref BaseWidget) =
#   if bw.statusbar:
#     let status = "x: " & $bw.tb.getCursorXPos & " y:" & $bw.tb.getCursorYPos
#     bw.renderCleanRect(bw.x1, bw.height, len(status), bw.height)
#     bw.tb.write(bw.x1 + 1, bw.height, fgYellow, status, resetStyle)

