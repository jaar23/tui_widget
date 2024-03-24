import tui_widget

var b = newBoard(30, 15, reverse=false)

echo b.size()
echo b.print()

echo b[0, 1, true]
#b.printBoard()