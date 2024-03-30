import illwill, options

type
  Alignment* = enum
    Left, Center, Right

  Mode* = enum
    Normal, Filter

  SelectionStyle* = enum
    Highlight, Arrow, HighlightArrow


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
    statusbar*: bool = true
    statusbarText*: string = ""
    statusbarSize*: int = 0
    visibility*: bool = true
    debug*: bool = false

  CallbackProcedure* = proc(x: string): void

  EnterEventProcedure* = proc(x: string): void

  SpaceEventProcedure* = proc(x: string, b: bool): void
  

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


method onControl*(this: ref BaseWidget, cb: CallbackProcedure): void {.base.} =
  #child needs to implement this!
  echo ""


method render*(this: ref BaseWidget): void {.base.} = 
  echo ""


method wg*(this: ref BaseWidget): ref BaseWidget {.base.} = this


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


proc renderCleanRow*(bw: ref BaseWidget, index = 0) =
  bw.tb.fill(bw.x1, bw.posY + index, bw.x2, bw.posY + index, " ")


proc renderCleanRect*(bw: ref BaseWidget, x1, y1, x2, y2: int) =
  bw.tb.fill(x1, y1, x2, y2, " ")


proc renderRow*(bw: ref BaseWidget, content: string, index: int = 0) =
  bw.tb.write(bw.widthPaddLeft, bw.posY + index, bw.style.bgColor, bw.style.fgColor, content, resetStyle)


proc clear*(bw: ref BaseWidget) =
  bw.tb.fill(bw.posX, bw.posY, bw.width, bw.height, " ")


proc rerender*(bw: ref BaseWidget) =
  bw.clear()
  bw.render()


proc show*(bw: ref BaseWidget) = 
  bw.visibility = true
  bw.render()

proc hide*(bw: ref BaseWidget) = 
  bw.visibility = false
  bw.clear()

# proc renderStatusBar*(bw: ref BaseWidget) =
#   if bw.statusbar:
#     let status = "x: " & $bw.tb.getCursorXPos & " y:" & $bw.tb.getCursorYPos
#     bw.renderCleanRect(bw.x1, bw.height, len(status), bw.height)
#     bw.tb.write(bw.x1 + 1, bw.height, fgYellow, status, resetStyle)

