import tui_widget

# ---------------------------------------------------------------------------
# Bounds-clamping verification
#
# Build & run: nim c -r --threads:on tests/bounds_test.nim
#
# Three widgets are intentionally constructed with bad bounds. With the
# framework's clampToConsole pass in place, none of them should produce
# the stripe rendering artifact that previously happened on inverted /
# off-screen rects (see lmstudio-example-render-bug.png):
#
#   hugeY  - posY far below the terminal      → clamped or hidden
#   hugeW  - width 3x consoleWidth             → width clamped to console
#   inv    - width < posX (inverted)          → hidden (visibility=false)
#
# A real, well-bounded widget is also added so it's obvious the loop
# itself still works.
# ---------------------------------------------------------------------------

var hugeY = newDisplay(1, consoleHeight() + 10,
                       consoleWidth(), consoleHeight() + 20,
                       id = "hugeY", title = "off-bottom",
                       border = true, statusbar = false)

var hugeW = newDisplay(1, 1, consoleWidth() * 3, 6,
                       id = "hugeW", title = "too-wide",
                       border = true, statusbar = false)
hugeW.text = "this widget was constructed wider than the console"

var inv = newLabel(50, 10, 20, 5,
                   id = "inv", text = "inverted bounds — hidden",
                   border = true)

var ok = newLabel(1, 8, consoleWidth(), 11,
                  id = "ok",
                  text = "ok — this label proves the loop is still alive",
                  border = true)

var app = newTerminalApp(title = "bounds clamp test", border = true,
                         rpms = 30)

app.addWidget(hugeY)
app.addWidget(hugeW)
app.addWidget(inv)
app.addWidget(ok)

# Print clamped values to stdout BEFORE running the TUI so a reader can
# inspect what the framework did. Comment out to run interactively.
echo "after clampToConsole:"
echo "  hugeY: pos=(", hugeY.posX, ",", hugeY.posY, ") wh=(",
     hugeY.width, ",", hugeY.height, ") vis=", hugeY.visibility
echo "  hugeW: pos=(", hugeW.posX, ",", hugeW.posY, ") wh=(",
     hugeW.width, ",", hugeW.height, ") vis=", hugeW.visibility
echo "  inv  : pos=(", inv.posX, ",", inv.posY, ") wh=(",
     inv.width, ",", inv.height, ") vis=", inv.visibility
echo "  ok   : pos=(", ok.posX, ",", ok.posY, ") wh=(",
     ok.width, ",", ok.height, ") vis=", ok.visibility
echo "console: ", consoleWidth(), "x", consoleHeight()

app.run(nonBlocking = true)
