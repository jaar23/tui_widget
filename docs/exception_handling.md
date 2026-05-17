## <a id="top">Exception Handling</a>

`tui_widget` runs your widgets inside a single event loop. Before this
mechanism existed, any uncaught exception raised by user code — an event
callback, a mouse handler, a render override, a `poll()` channel handler, a
background task — would propagate out of the main loop and crash the entire
TUI process.

The runtime-safety layer added in 0.1.4 stops that. It has three pieces:

1. A `safeCall` template that wraps every user-code call site.
2. A per-widget `onError` method that paints a red `[!]` block inside the
   widget's bounds.
3. An optional, app-level `onWidgetError` hook for log files, telemetry,
   status banners, throttling — anything the host application needs.

The contract is: **a misbehaving widget should never take down the host.**
It will visibly show its failure, and the rest of the app keeps running.

---

### How a caught exception flows

```text
   user code throws
         |
         v
   safeCall template (src/widget/base_wg.nim)
   +---------------------------------------+
   | 1. captures e.msg and e.getStackTrace |
   | 2. if globalErrorHandler != nil:      |
   |       call it (wrapped in try/except, |
   |       cannot cascade)                 |
   | 3. call wg.onError(where & ": " & msg)|
   |       also try/except — never cascades|
   +---------------------------------------+
         |
         v
   main loop continues to the next iteration
```

`where` is a short string identifying the call site — `"onUpdate"`,
`"onMouseEvent"`, `"onControl"`, `"poll"`, `"render"`, or `"task"` for
background tasks. It prefixes the error message so you can tell which
surface failed.

---

### Wrapped call sites

These are the seams where user code runs and the framework now traps
exceptions for you. You don't have to do anything — they're protected
automatically.

| Loop      | Branch                | What `safeCall` wraps        |
|-----------|-----------------------|------------------------------|
| `go()`    | `Key.Tab`             | `onControl()` (via `nonBlockingControl`) |
| `go()`    | `Key.Mouse`           | `widget.onMouseEvent(mouseInfo)` |
| `go()`    | any other key         | `widget.onUpdate(key)`       |
| `go()`    | every iteration       | `app.pollWidgetChannel()` per widget |
| `hold()`  | `Key.Tab` / `Key.None`| `widget.onControl()`         |
| `hold()`  | `Key.Mouse`           | `widget.onMouseEvent(mouseInfo)` |
| `render()`| both passes           | `widget.rerender()`          |
| bg thread | `backgroundTasks()`   | `task.invoke()`              |

The background thread does **not** call `widget.onError` (it has no widget
reference). Errors from background tasks are routed only through
`globalErrorHandler`, with the synthetic widget id `"<background>"` and
`where = "task"`.

---

### The default error UI: `onError`

```nim
method onError*(this: ref BaseWidget, errorCode: string) {.base.}
```

The base implementation fills the widget's bounds with spaces and writes
`[!] <message>` in red-on-white, word-wrapped to fit. It does **not** call
`tb.display()` — the next `app.render()` cycle flushes via the batched
single display.

To customise the error UI for a specific widget type, override the method:

```nim
method onError*(this: MyButton, errorCode: string) =
  this.tb.fill(this.posX, this.posY, this.width, this.height, " ")
  this.tb.write(this.posX + 1, this.posY,
                bgYellow, fgBlack, "⚠ " & errorCode, resetStyle)
```

---

### The app-level hook: `onWidgetError`

For everything else — logging to a file, shipping a stack trace to
telemetry, drawing a global status banner — set `app.onWidgetError`. It
fires every time `safeCall` traps an exception, **in addition** to the
widget's `onError` paint.

```nim
app.onWidgetError = proc(widgetId, where, msg, trace: string) =
  let f = open("tui_widget_errors.log", fmAppend)
  f.writeLine("[" & widgetId & "/" & where & "] " & msg)
  if trace.len > 0:
    f.writeLine(trace)
  f.close()
```

The handler must be `{.gcsafe.}` (the type enforces this) because the same
hook is also invoked from the background-task thread. Stick to thread-safe
I/O — file appends, channels, atomic counters — and avoid touching widget
state directly from the handler.

The handler is global (process-wide, single slot). Per-widget routing is
just an `if widgetId == "...":` inside the handler.

---

### Type and signature reference

```nim
# src/widget/base_wg.nim

type
  GlobalErrorHandler* = proc(widgetId: string, where: string,
                             msg: string, trace: string) {.closure, gcsafe.}

var globalErrorHandler*: GlobalErrorHandler = nil

template safeCall*(wg: ref BaseWidget, where: string, body: untyped)

method onError*(this: ref BaseWidget, errorCode: string) {.base.}
```

```nim
# src/tui_widget.nim

proc `onWidgetError=`*(app: var TerminalApp, handler: GlobalErrorHandler)
```

---

### Demonstration

`tests/exception_test.nim` is a runnable demo that proves the loop survives
intentional widget failures.

```sh
nim c -r --threads:on tests/exception_test.nim
```

It lays out three widgets side by side:

- **Throw!** — a button whose `onEnter` deliberately raises
  `ValueError("intentional boom from bad")`.
- **Safe** — a button that increments an in-process counter.
- A status label that reflects how many times the safe button was clicked.

What you will see when you run it:

1. Click **Throw!** — its area is repainted as a red `[!] onUpdate:
   intentional boom from bad` block. The app does **not** quit.
2. Click **Safe** — the counter still increments; the status label updates.
   Proves the event loop is alive after the previous exception.
3. Tab between the widgets — focus shifts cleanly. The bad widget continues
   to show its error block (because its own render still works — only the
   user-supplied callback was throwing).
4. Click **Throw!** repeatedly — every click re-traps. The handler never
   cascades, the app never crashes.
5. While the demo runs, in another terminal: `tail -f exception_test.log`.
   Each click on **Throw!** appends an entry with the widget id, the
   `where` label (`onUpdate`), the message, and the full stack trace.
   This is the `onWidgetError` hook firing.

The demo source — including the hook installation — is short enough to read
end-to-end and adapt for your own apps:

```nim
app.onWidgetError = proc(widgetId, where, msg, trace: string) =
  try:
    let f = open("exception_test.log", fmAppend)
    f.writeLine("[" & widgetId & "/" & where & "] " & msg)
    if trace.len > 0: f.writeLine(trace)
    f.close()
  except CatchableError:
    discard

badBtn.onEnter = proc(b: Button, args: varargs[string]) =
  raise newException(ValueError, "intentional boom from " & b.id)
```

---

### Extending the safety net later

The same `safeCall` template + `onWidgetError` hook are the seams for
heavier behaviour. None of these require touching the wrapped call sites
above — they all plug in via the handler.

- **Log file rotation** — handler appends to a configured path, rotates by
  size or date.
- **Per-widget throttling** — handler maintains an
  `(id -> count, lastSeen)` table; if a widget exceeds N errors in T
  seconds, set `wg.visibility = false` so the loop skips it.
- **Status banner row** — handler writes a one-line `[!] <id>: <msg>`
  banner into a reserved row of the app frame so even tiny widgets'
  failures are visible.
- **Telemetry / Sentry** — handler ships `msg` and `trace` to a remote
  endpoint, optionally with the widget id as a tag.

---

[back to top](#top)
