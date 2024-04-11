import illwill, times, os

proc getKeysWithTimeout(timeout = 1000, numOfKey = 2): seq[Key] =
  var captured = 0
  var keyCapture = newSeq[Key]()
  let waitTime = timeout * 1000
  let startTime = now().nanosecond()
  let endTime = startTime + waitTime
  while true and now().nanosecond() < endTime:
    if captured == numOfKey: break
    let key = getKey()
    keyCapture.add(key)
    inc captured

  return keyCapture


when isMainModule:
  proc exitProc() {.noconv.} =
    illwillDeinit()
    showCursor()
    quit(0)

  illwillInit(fullscreen = true)
  setControlCHook(exitProc)
  hideCursor()

  while true:
    let keys = getKeysWithTimeout(500)
    echo $keys
    sleep(1000)
