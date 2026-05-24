import illwill

## ---------------------------------------------------------------------------
## screen_bounds — centralised terminal-dimension policy
##
## Every dimension query in the framework should route through this module.
## That way the "how many rows/cols are reserved for terminal safety" decision
## lives in one place and can be tuned per-platform or per-app.
##
## Why reserve rows/cols at all?
##   Writing to the very last column or row can cause some terminals (and
##   illwill's TerminalBuffer) to auto-scroll, producing visual artifacts.
##   The reserved counts below prevent that.
##
## Current defaults (match the historical -2 convention):
##   RESERVED_COLS = 2    (1 for safety, 1 extra margin)
##   RESERVED_ROWS = 2    (1 for safety, 1 extra margin)
##
## If you want zero dead space in full-screen mode, set both to 1.
## If you see auto-scroll artifacts on your terminal, bump them up.
## ---------------------------------------------------------------------------

# ---------------------------------------------------------------------- public
# Tune these to adjust the dead zone around the renderable area.
# ---------------------------------------------------------------------------

const
  RESERVED_COLS* {.intdefine.} = 2
    ## Columns reserved at the right edge of the terminal for WIDGET LAYOUT.
    ## consoleWidth()/maxWidgetWidth() = terminalWidth() - RESERVED_COLS, so
    ## the rightmost cell a widget will draw to is at column
    ## terminalWidth()-RESERVED_COLS. Override with `-d:RESERVED_COLS=1`.
  RESERVED_ROWS* {.intdefine.} = 2
    ## Rows reserved at the bottom edge of the terminal for WIDGET LAYOUT.
    ## consoleHeight()/maxWidgetHeight() = terminalHeight() - RESERVED_ROWS,
    ## so the bottommost row a widget will draw to is at row
    ## terminalHeight()-RESERVED_ROWS. Override with `-d:RESERVED_ROWS=1`.
  BUFFER_EDGE_RESERVE* {.intdefine.} = 1
    ## Cells reserved between the buffer's last cell and the absolute
    ## terminal edge. Sizing the TerminalBuffer to
    ## (terminalWidth()-BUFFER_EDGE_RESERVE, terminalHeight()-BUFFER_EDGE_RESERVE)
    ## ensures illwill's tb.display() never flushes the absolute bottom-right
    ## terminal cell — writing there triggers terminal auto-scroll on many
    ## terminals (the "modal disappears but screen scrolls infinitely"
    ## artifact: each frame writes the corner, scrolls 1 row, and stale
    ## borders accumulate as horizontal stripes). illwill has an IRM trick
    ## for this but it doesn't work on every terminal. With this reserve
    ## the bottom-right is left untouched and every widget whose right edge
    ## is at consoleWidth() = terminalWidth()-2 still fits in the buffer
    ## (its last column = buffer.width-1).

# ------------------------------------------------------------------ functions
# Prefer these over raw terminalWidth()/terminalHeight().
# ---------------------------------------------------------------------------

proc screenWidth*(): int {.inline.} =
  ## Total terminal columns.
  terminalWidth()

proc screenHeight*(): int {.inline.} =
  ## Total terminal rows.
  terminalHeight()

proc maxWidgetWidth*(): int {.inline.} =
  ## Rightmost column a widget may render to (inclusive).
  terminalWidth() - RESERVED_COLS

proc maxWidgetHeight*(): int {.inline.} =
  ## Bottommost row a widget may render to (inclusive).
  terminalHeight() - RESERVED_ROWS

proc bufferWidth*(): int {.inline.} =
  ## Width to pass to newTerminalBuffer. One smaller than terminalWidth() so
  ## illwill never writes the absolute right column.
  terminalWidth() - BUFFER_EDGE_RESERVE

proc bufferHeight*(): int {.inline.} =
  ## Height to pass to newTerminalBuffer. One smaller than terminalHeight()
  ## so illwill never writes the absolute bottom row.
  terminalHeight() - BUFFER_EDGE_RESERVE

# ------------------------------------------------------------------- guards
# Use these at the final render call-site to clip overflow.
# ---------------------------------------------------------------------------

proc clampRow*(tb: TerminalBuffer, row: int): bool {.inline.} =
  ## Returns `true` when `row` is inside the safe renderable area.
  ## Clamped against both the buffer's actual height and the screen-level
  ## reserved-row policy — whichever is tighter.
  ## Callers should skip rendering when this returns `false`.
  row < tb.height and row < maxWidgetHeight()

proc clampCol*(tb: TerminalBuffer, col: int): bool {.inline.} =
  ## Returns `true` when `col` is inside the safe renderable area.
  ## Clamped against both the buffer's actual width and the screen-level
  ## reserved-col policy — whichever is tighter.
  col < tb.width and col < maxWidgetWidth()
