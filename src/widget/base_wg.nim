import illwill

type
  BaseWidget* = ref object of RootObj
    width*: int
    height*: int
    posX*: int
    posY*: int
    fgColor*: ForegroundColor = fgWhite
    focus*: bool = false

proc consoleWidth*(): int =
  return terminalWidth() - 2

proc consoleHeight*(): int = 
  return terminalHeight() - 2


method onControl*(this: var BaseWidget): void {.base.} =
  echo "child needs to implement this!"
