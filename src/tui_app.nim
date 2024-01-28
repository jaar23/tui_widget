import illwill, os, tui_widget/[base_wg, input_box_wg]

type
  App* = object
    widget*:  seq[BaseWidget]


var inputBox = InputBox(
  width: 20, 
  height: 2,
  size: 100, 
  posX: 0, 
  posY: 0,
)

proc exitProc() {.noconv.} =                                                                                                                                                                                                               
  illwillDeinit()                                                                                                                                                                                                                          
  showCursor()
  quit(0)


illwillInit(fullscreen=true)
setControlCHook(exitProc)
hideCursor()

## all the widget should have 1 char lesser
var tb = newTerminalBuffer(21, 20)
tb.setForegroundColor(fgWhite, true)

while true:
  var key = getKey()
  case key
  of Key.None:
    tb.write(2, 5, fgWhite, $inputBox.value().len)
    tb.display()
  of Key.Colon:
    inputBox.onInput(tb)
  of Key.Tab:
    echo "tab"
  else:
    tb.write(2, 5, fgWhite, $inputBox.value().len)
    tb.display()
  sleep(20)

