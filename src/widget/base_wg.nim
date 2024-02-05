import illwill, options

type
  Alignment* = enum
    Left, Center, Right

  Mode* = enum
    Normal, Filter

  BaseWidget* = object of RootObj
    width*: int
    height*: int
    posX*: int
    posY*: int
    fgColor*: ForegroundColor = fgWhite
    bgColor*: BackgroundColor = bgNone
    focus*: bool = false
    tb*: TerminalBuffer
    bordered*: bool = true
    paddingX*: int = 1
    paddingY*: int = 1


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


method onControl*(this: ref BaseWidget, cb: proc(args: string)): void {.base.} =
  #child needs to implement this!
  echo ""


method onControl*(this: ref BaseWidget, cb: Option[CallbackProcedure]): void {.base.} =
  #child needs to implement this!
  echo ""



