import illwill, options

type
  BaseWidget* = ref object of RootObj
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


method onControl*(this: var BaseWidget): void {.base.} =
  #child needs to implement this!
  echo ""


method onControl*(this: var BaseWidget, cb: proc(args: varargs[string])): void {.base.} =
  #child needs to implement this!
  echo ""


method onControl*(this: var BaseWidget, cb: proc(args: string)): void {.base.} =
  #child needs to implement this!
  echo ""


method onControl*(this: var BaseWidget, cb: Option[CallbackProcedure]): void {.base.} =
  #child needs to implement this!
  echo ""

#TODO: callback function

# having compilation bugs when using this method
# method merge*(this: var BaseWidget, wg: BaseWidget): void {.base.} = 
#   echo ""


