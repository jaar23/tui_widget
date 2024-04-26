## you will need the framedata.txt file to 
## play with this example.
## https://skript-kitty.itch.io/bad-apple-on-scratch

import tui_widget
import illwill, strutils, os, std/wordwrap


proc createFrame(s: string): string =
  var frame = wrapWords(s, 120)
  return frame

var readCursor = 0
let f = readFile("framedata.txt")
let readSize = 120 * 90
var content: string

var display = newDisplay(id="panel")
display.title = "Bad Apple"
display.bg(bgBlack)
display.fg(fgWhite)
display.statusbar = false
display.wordwrap = true

var app = newTerminalApp()

let play = proc(dp: Display, args: varargs[string]) =
  while true:
    content = f.substr(readCursor, min((readCursor + readSize), f.len - 1))
    dp.text = createFrame(content)
    readCursor += readSize + 1
    #app.terminalBuffer.clear()
    sleep(30)

display.on(Key.P, play)

app.addWidget(display, 122, 90)

app.run()

