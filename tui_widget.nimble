# Package

version       = "0.1.4"
author        = "jaar23"
description   = "A terminal ui widget based on illwill"
license       = "DO WHATEVER YOU WANT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.0"
# NOTE: The released illwill 0.4.1 on Nimble registry has broken mouse parsing
# on POSIX (\e[<...M sequences are silently discarded by parseStdin). The fix is
# on git HEAD but not yet released. Install with:
#   nimble install https://github.com/johnnovak/illwill.git
requires "illwill#head"
requires "threading >= 0.2.0"
requires "malebolgia >= 0.1.0"
