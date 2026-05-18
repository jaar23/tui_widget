import ../src/tui_widget
import httpclient, json, net, os, std/tasks, strutils, times, std/wordwrap,
       options, random, std/atomics, std/parseopt, unicode
import ./lmstudio_tools   # toolSpecs* + execTool* (9 agentic tools)

# ---------------------------------------------------------------------------
# LM Studio chatbot — ListView variant
#
# Same behaviour as `lmstudio_chat.nim` (streaming replies, tool calling,
# thinking quotes, statusbar, CLI config) but the conversation transcript
# uses a `ListView` instead of a `Display`. Each logical line becomes one
# `ListRow`, so users can arrow-key through history, the selected row is
# highlighted (inverse video via `enableTextOverlay`), and auto-scroll
# pins `rowCursor` to the bottom whenever new content arrives.
#
# Run:
#   nim c -r --threads:on --d:ssl examples/lmstudio_chat_listview.nim \
#     --endpoint=URL --model=NAME [--api-key=KEY]
# ---------------------------------------------------------------------------

const Usage = """
LM Studio chatbot (ListView variant)

Usage:
  lmstudio_chat_listview [options]

Options:
  -u, --endpoint=URL   chat-completions endpoint URL
                       (default: $LMSTUDIO_URL or http://localhost:1234/v1/chat/completions)
  -m, --model=NAME     model id sent in the request body
                       (default: $LMSTUDIO_MODEL or local-model)
  -k, --api-key=KEY    bearer token (sent as Authorization: Bearer KEY)
                       (default: $LMSTUDIO_API_KEY or empty)
  -h, --help           show this help and exit
"""

var endpoint = getEnv("LMSTUDIO_URL",
                     "http://localhost:1234/v1/chat/completions")
var modelId  = getEnv("LMSTUDIO_MODEL", "local-model")
var apiKey   = getEnv("LMSTUDIO_API_KEY", "")

block parseCli:
  var p = initOptParser()
  for kind, key, val in p.getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "endpoint", "u":
        if val.len == 0: echo "missing value for --", key; quit(2)
        endpoint = val
      of "model", "m":
        if val.len == 0: echo "missing value for --", key; quit(2)
        modelId = val
      of "api-key", "k": apiKey = val
      of "help", "h": echo Usage; quit(0)
      else:
        echo "unknown option: --", key; echo Usage; quit(2)
    of cmdArgument:
      echo "unexpected positional argument: ", key; echo Usage; quit(2)
    of cmdEnd: discard

# ---- Transcript model -----------------------------------------------------

type
  MsgKind = enum mkSystem, mkUser, mkAssistant, mkToolCall, mkToolResult
  Message = object
    kind: MsgKind
    role: string
    content: string
    name: string
    args: string
    ts: DateTime

var history: seq[Message] = @[
  Message(kind: mkSystem, role: "system",
          content: "You are a concise, helpful assistant running locally " &
                   "via LM Studio. Use tools when they help. Keep answers " &
                   "short unless asked.",
          ts: now())
]

# ---- Tool layer is in `./lmstudio_tools` (see toolSpecs* / execTool*) -----

# ---- Layout / minimum size checks -----------------------------------------

const
  MinChatRows = 5
  MinHeight   = MinChatRows + 3 + 1
  MinWidth    = 40
  MaxToolHops = 5
  StreamChunkSize = 6
  StreamChunkSleepMs = 18

if consoleHeight() < MinHeight or consoleWidth() < MinWidth:
  echo "terminal too small for LM Studio chat demo"
  echo "  need at least ", MinWidth, "x", MinHeight + 2,
       " (current: ", terminalWidth(), "x", terminalHeight(), ")"
  quit(1)

# ---- Widgets --------------------------------------------------------------

var chat = newListView(id = "chat")
chat.title          = "conversation"
chat.border         = true
chat.statusbar      = false
chat.selectionStyle = Highlight
chat.enableTextOverlay()   # CJK-safe row drawing + inverse-video selection

var input = newInputBox(id = "input")
input.title     = "message (Enter to send, Tab cycles chat/input)"
input.border    = true
input.statusbar = false
input.enableTextOverlay()

var status = newLabel(id = "status")
status.border    = false
status.focusable = false

var app = newTerminalApp(title = "LM Studio Chat (ListView)",
                         border = false, rpms = 50)

app.onWidgetError = proc(widgetId, where, msg, trace: string) {.gcsafe.} =
  try:
    let f = open("lmstudio_chat_listview.log", fmAppend)
    f.writeLine("[" & widgetId & "/" & where & "] " & msg)
    if trace.len > 0: f.writeLine(trace)
    f.close()
  except CatchableError: discard

# ---- Status bar -----------------------------------------------------------

proc visibleMsgCount(): int =
  for m in history:
    if m.kind in {mkUser, mkAssistant}: inc result

proc setStatus(state: string) =
  let right = $visibleMsgCount() & " messages · " & modelId
  let w     = max(0, consoleWidth() - 4)
  let used  = state.len + right.len
  let pad   = max(1, w - used)
  status.text = " " & state & " ".repeat(pad) & right

# ---- Wrap text by visual width into individual ListRow text strings -------

proc wrapVisual(line: string, maxCells: int, indent: string): seq[string] =
  result = @[]
  if maxCells <= 0: result.add(line); return
  let indentCells = visualWidth(indent)
  var cur = ""
  var curCells = 0
  var lastSpaceLen = -1
  for r in runes(line):
    let rs = $r
    let rw = runeWidth(r)
    if curCells + rw > maxCells and cur.len > 0:
      if lastSpaceLen > 0:
        let head = cur[0 ..< lastSpaceLen]
        let tail = cur[lastSpaceLen + 1 .. ^1]
        result.add(head)
        cur = indent & tail
        curCells = indentCells + visualWidth(tail)
      else:
        result.add(cur)
        cur = indent
        curCells = indentCells
      lastSpaceLen = -1
    if r == Rune(' '): lastSpaceLen = cur.len
    cur.add(rs)
    curCells += rw
  if cur.len > 0: result.add(cur)

# ---- History → list rows --------------------------------------------------
# Each message expands to a header row + N body rows + a blank separator.
# `chat.x2 - chat.x1` gives the per-row width budget; we wrap once the
# widget is sized (after addWidget), so this proc must be called after
# layout has run.

proc rebuildRows() =
  let w = max(10, chat.x2 - chat.x1)
  var rows: seq[ListRow] = @[]
  var idx = 0
  proc add(text: string) =
    # ListRow text holds a single visual row; blank rows use a single
    # space so the overlay clears the line (overlay treats "" as no-op
    # in `clipToVisualWidth` and the row would render entirely blank).
    let t = if text.len == 0: " " else: text
    rows.add(newListRow(idx, t, t))
    inc idx
  for m in history:
    case m.kind
    of mkSystem: discard
    of mkUser, mkAssistant:
      let who   = if m.kind == mkUser: "you" else: "assistant"
      let stamp = m.ts.format("HH:mm")
      add(stamp & "  " & who)
      for line in m.content.strip().splitLines():
        let body = "  " & line
        if visualWidth(body) <= w:
          add(body)
        else:
          for piece in wrapVisual(body, w, "  "):
            add(piece)
      add("")
    of mkToolCall:
      let stamp = m.ts.format("HH:mm")
      add(stamp & "  ⚙ tool call → " & m.name)
      for line in m.args.splitLines():
        let body = "    " & line
        if visualWidth(body) <= w: add(body)
        else:
          for piece in wrapVisual(body, w, "    "): add(piece)
      add("")
    of mkToolResult:
      let stamp = m.ts.format("HH:mm")
      add(stamp & "  ⤳ result ← " & m.name)
      for line in m.content.splitLines():
        let body = "    " & line
        if visualWidth(body) <= w: add(body)
        else:
          for piece in wrapVisual(body, w, "    "): add(piece)
      add("")
  chat.rows = rows
  # Auto-scroll to the bottom. ListView's render uses a "highlight at
  # bottom while cursor moves" scroll algorithm: it only trims `rowStart`
  # past 0 when `rowCursor` itself sits in the last viewport-worth of
  # rows. Setting rowCursor to the last row index makes it show the
  # trailing window (the most recent message), with the selection on
  # the freshly arrived row.
  if rows.len > 0:
    chat.rowCursor = rows.len - 1
    chat.selectedRow = rows.len - 1
    for r in rows: r.selected = false
    rows[^1].selected = true

# ---- Quote ticker thread --------------------------------------------------

let thinkingQuotes = [
  "warming up the lobes...",
  "consulting the digital oracle...",
  "untangling thoughts...",
  "browsing the latent space...",
  "stirring the silicon soup...",
  "polling distant attention heads...",
  "shuffling probability mass...",
  "sketching answers in the dark...",
  "talking to electrons politely...",
  "weighing words..."
]

var thinking: Atomic[bool]
thinking.store(false)
var quoteThread: Thread[ptr TerminalApp]

proc quoteLoop(appPtr: ptr TerminalApp) {.thread, gcsafe.} =
  var r = initRand(getTime().toUnix())
  while true:
    if thinking.load():
      var q = ""
      {.cast(gcsafe).}:
        q = thinkingQuotes[r.rand(thinkingQuotes.high)]
      try: notify(appPtr, "status", "tick", q)
      except CatchableError: discard
    sleep(1400)

status.on("tick", proc(lb: Label, args: varargs[string]) =
  if args.len > 0: setStatus("thinking · " & args[0]))

# ---- Streaming + tool events on chat --------------------------------------

var streamBuf = ""

chat.on("reply_start", proc(lv: ListView, args: varargs[string]) =
  streamBuf = ""
  history.add(Message(kind: mkAssistant, role: "assistant",
                      content: "", ts: now()))
  rebuildRows())

chat.on("reply_chunk", proc(lv: ListView, args: varargs[string]) =
  if args.len > 0 and history.len > 0:
    streamBuf.add(args[0])
    history[^1].content = streamBuf
    rebuildRows())

chat.on("reply_end", proc(lv: ListView, args: varargs[string]) =
  thinking.store(false)
  setStatus("ready"))

chat.on("tool_call", proc(lv: ListView, args: varargs[string]) =
  if args.len >= 2:
    history.add(Message(kind: mkToolCall, role: "tool",
                        name: args[0], args: args[1], ts: now()))
    rebuildRows())

chat.on("tool_result", proc(lv: ListView, args: varargs[string]) =
  if args.len >= 2:
    history.add(Message(kind: mkToolResult, role: "tool",
                        name: args[0], content: args[1], ts: now()))
    rebuildRows())

chat.on("error", proc(lv: ListView, args: varargs[string]) =
  thinking.store(false)
  setStatus("error · " & (if args.len > 0: args[0] else: "?")))

# ---- Background agent loop ------------------------------------------------

proc llmCall(client: var HttpClient, url: string,
             msgs: JsonNode): JsonNode {.gcsafe.} =
  var bodyStr = ""
  {.cast(gcsafe).}:
    bodyStr = $(%*{
      "model": modelId,
      "messages": msgs,
      "tools": toolSpecs,
      "tool_choice": "auto",
      "stream": false,
      "temperature": 0.6
    })
  let resp = client.request(url, httpMethod = HttpPost, body = bodyStr)
  if resp.code != Http200:
    raise newException(IOError,
      "HTTP " & $resp.code.int & ": " &
      resp.body[0 .. min(200, resp.body.high)])
  result = parseJson(resp.body)

proc streamOut(appPtr: ptr TerminalApp, text: string) {.gcsafe.} =
  notify(appPtr, "chat", "reply_start")
  var i = 0
  while i < text.len:
    let nxt = min(i + StreamChunkSize, text.len)
    notify(appPtr, "chat", "reply_chunk", text[i ..< nxt])
    i = nxt
    sleep(StreamChunkSleepMs)
  notify(appPtr, "chat", "reply_end")

proc agentLoop(appPtr: ptr TerminalApp,
               url, token, msgsJson: string) {.gcsafe.} =
  var client = newHttpClient(timeout = 60_000,
                            sslContext = newContext(
                              verifyMode = CVerifyPeerUseEnvVars))
  defer: client.close()
  var headerPairs = @[("Content-Type", "application/json")]
  if token.len > 0:
    headerPairs.add(("Authorization", "Bearer " & token))
  client.headers = newHttpHeaders(headerPairs)
  try:
    var msgs = parseJson(msgsJson)
    var hops = 0
    while hops < MaxToolHops:
      inc hops
      let parsed = llmCall(client, url, msgs)
      let msg    = parsed["choices"][0]["message"]
      msgs.add(msg)
      if msg.hasKey("tool_calls") and msg["tool_calls"].len > 0:
        for tc in msg["tool_calls"]:
          let tcId   = tc["id"].getStr()
          let tName  = tc["function"]["name"].getStr()
          let tArgsS = tc["function"]["arguments"].getStr()
          notify(appPtr, "chat", "tool_call", tName, tArgsS)
          var tArgs: JsonNode
          try: tArgs = parseJson(tArgsS)
          except CatchableError: tArgs = newJObject()
          let res = execTool(tName, tArgs)
          notify(appPtr, "chat", "tool_result", tName, res)
          msgs.add(%*{
            "role": "tool",
            "tool_call_id": tcId,
            "name": tName,
            "content": res})
        continue
      else:
        let text = msg{"content"}.getStr("")
        streamOut(appPtr, text)
        return
    notify(appPtr, "chat", "error",
           "stopped after " & $MaxToolHops & " tool hops without a reply")
  except CatchableError:
    notify(appPtr, "chat", "error", getCurrentExceptionMsg())

proc apiMessages(): JsonNode =
  result = newJArray()
  for m in history:
    case m.kind
    of mkSystem, mkUser, mkAssistant:
      if m.kind == mkAssistant and m.content.len == 0: continue
      result.add(%*{"role": m.role, "content": m.content})
    of mkToolCall, mkToolResult: discard

# ---- Input handler --------------------------------------------------------

input.onEnter = proc(ib: InputBox, args: varargs[string]) =
  let userMsg = ib.value.strip()
  if userMsg.len == 0: return
  ib.value = ""
  history.add(Message(kind: mkUser, role: "user",
                      content: userMsg, ts: now()))
  rebuildRows()
  thinking.store(true)
  setStatus("thinking...")
  let msgsJson = $apiMessages()
  runInBackground(toTask agentLoop(addr app, endpoint, apiKey, msgsJson))

# ---- Wire up and run ------------------------------------------------------

app.addWidget(chat,   1.0, 0.85)
app.addWidget(input,  1.0, 0.1)
app.addWidget(status, 1.0, 0.05)

rebuildRows()
setStatus("ready")
createThread(quoteThread, quoteLoop, addr app)
app.run(nonBlocking = true)
