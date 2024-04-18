import malebolgia, os, taskpools

type
  Obj = object 
    x: int
    y: int
    z: string
    val: int


proc newObject(): ref Obj =
  var obj = (ref Obj)(
    x: 1,
    y: 2,
    z: "hello, there",
    val: 0
  )
  return obj

proc busyTask() = 
  sleep(1000)
  echo "running..."
  sleep(1000)
  echo "done"


proc addRef(o: ref Obj, args: varargs[string]) =
  var tp = Taskpool.new()
  tp.spawn busyTask()


proc uiLoop(obj: ref Obj, tp: Taskpool) =
  while true:
    echo obj.z
    obj.addRef()
    sleep(1000)
    echo obj.val


when isMainModule:
  var o = newObject()
  var tp = Taskpool.new()
  o.uiLoop(tp)
  #var m = createMaster()
  #m.awaitAll:
  #  o.uiLoop(getHandle(m))
