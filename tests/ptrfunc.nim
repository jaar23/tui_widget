import std/tables

type
  fn = proc (obj: var Obj, args: varargs[string]): void
  fn2 = proc (obj: var Child, args: varargs[string]): void

  Obj = object of RootObj
    x: int
    y: int
    f: Table[string, fn]
    #f2: Table[string, fn2]

  Child = object of Obj
    z: string
    f2: Table[string, fn2]


var o = Obj(x: 1, y: 2, f: initTable[string, fn]())
#, f2: initTable[string, fn2]())

#echo $o.x

# proc on(o: var Obj, name: string, fn: fn) =
#   o.f.add(name, fn)
#

proc on(o: var Obj, name: string, fn: fn) =
  o.f.add(name, fn)


proc on(o: var Child, name: string, fn: fn2) =
  o.f2.add(name, fn)


proc call(o: var Obj, name: string, p: varargs[string]) =
  var fn = o.f.getOrDefault(name, nil)
  if fn.isNil: echo "not found"
  fn(o, p)


proc call(o: var Child, name: string, p: varargs[string]) =
  var fn = o.f2.getOrDefault(name, nil)
  if fn.isNil: echo "not found"
  fn(o, p)

var c = Child(x: 2, y: 2, f2: initTable[string, fn2](), z: "child...")

let ev = proc(o: var Obj, txt: varargs[string]) =
    echo $(o.x + o.y)
    echo txt


let ev2 = proc(c: var Child, txt: varargs[string]) =
  echo txt
  echo c.z

#o.on("click", ev)

#o.call("click", "....")

c.on("press", ev2)

c.call("press", "testing")
