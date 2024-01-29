import illwill

type
  BaseWidget* = object of RootObj
    width*: int
    height*: int
    posX*: int
    posY*: int
    fgColor*: ForegroundColor = fgWhite
    focus*: bool = false


