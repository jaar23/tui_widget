
### Event Handling

Event is now more extensible, there are default "enter" event setup for the widgets. You can:

```nim
let enterEv = proc(ib: ref InputBox, arg: varargs[string]) =
  # reset input
  inputBox.value("")

inputBox.onEnter = enterEv
```

or with a event name:

```nim
let enterEv = proc(ib: ref InputBox, arg: varargs[string]) =
  # reset input
  inputBox.value("")

inputBox.on("enter", enterEv)
```
Do note that, if "enter" is passed as the event key to `.on` proc, it will override the default behavior. 

With this changes, you can have `on("forward")`, `on("scroll")`, etc...

Nevertheless, widget also support for custom key binding, there are some key has been map for default behavior in the widgets.

You can bind an event to a key that is currently unuse. It works similarly to `on()` event. 

```nim
inputBox.on(Key.C, clertEv)
```

Further documentation is still work in progress