import ../src/tui_widget
import httpclient, json, net, os, std/tasks, strutils, times, std/wordwrap,
       options, random, std/atomics, std/parseopt, unicode
import ./lmstudio_tools   # toolSpecs* + execTool* (9 agentic tools)

# ---------------------------------------------------------------------------
# LM Studio chatbot — enhanced edition
#
# Features:
#   - Slack-style transcript with timestamps and indented bodies.
#   - Streaming output: assistant replies appear chunk-by-chunk.
#   - Tool calling: the model can invoke run_command, web_search,
#     write_file. The tool call AND its result are shown inline in the
#     chat. Up to MaxToolHops iterations before bailing out.
#   - Random "thinking" quotes rotate on the status bar while the model
#     is working (separate ticker thread updates via the widget channel).
#   - Status bar shows total messages on the left and the model name on
#     the right, padded to console width.
#   - Tab cycles only between chat and input — the status bar is set
#     focusable=false and is skipped.
#   - Auto-scrolls the chat to the bottom as new chunks arrive.
#
# Prerequisites:
#   - LM Studio running with a tool-calling model loaded and the local
#     OpenAI server started on http://localhost:1234.
#
# Build:
#   nim c -r --threads:on --d:ssl examples/lmstudio_chat.nim
#
# Configuration (CLI flags > env vars > defaults):
#   --endpoint=URL   / -u URL    or env LMSTUDIO_URL
#   --model=NAME     / -m NAME   or env LMSTUDIO_MODEL
#   --api-key=KEY    / -k KEY    or env LMSTUDIO_API_KEY (optional; sent as
#                                Bearer token if non-empty)
#   --help           / -h        print this usage and exit
# ---------------------------------------------------------------------------

const Usage = """
LM Studio chatbot

Usage:
  lmstudio_chat [options]

Options:
  -u, --endpoint=URL   chat-completions endpoint URL
                       (default: $LMSTUDIO_URL or http://localhost:1234/v1/chat/completions)
  -m, --model=NAME     model id sent in the request body
                       (default: $LMSTUDIO_MODEL or local-model)
  -k, --api-key=KEY    bearer token (sent as Authorization: Bearer KEY)
                       (default: $LMSTUDIO_API_KEY or empty — header omitted)
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
        if val.len == 0:
          echo "missing value for --", key; quit(2)
        endpoint = val
      of "model", "m":
        if val.len == 0:
          echo "missing value for --", key; quit(2)
        modelId = val
      of "api-key", "k":
        apiKey = val   # empty is fine — disables Authorization header
      of "help", "h":
        echo Usage; quit(0)
      else:
        echo "unknown option: --", key
        echo Usage
        quit(2)
    of cmdArgument:
      echo "unexpected positional argument: ", key
      echo Usage
      quit(2)
    of cmdEnd: discard

# ---- Transcript model -----------------------------------------------------

type
  MsgKind = enum mkSystem, mkUser, mkAssistant, mkToolCall, mkToolResult
  Message = object
    kind: MsgKind
    role: string        # "user" | "assistant" | "tool" | "system"
    content: string
    name: string        # tool name (for mkToolCall / mkToolResult)
    callId: string      # tool_call id (for tool round-tripping)
    args: string        # JSON args (for mkToolCall display)
    ts: DateTime

var history: seq[Message] = @[
  Message(kind: mkSystem, role: "system",
          content: "You are a concise, helpful assistant running locally " &
                   "via LM Studio. Use tools when they help. Keep answers " &
                   "short unless asked.",
          ts: now())
]

# ---- Tool layer is in `./lmstudio_tools` (see toolSpecs* / execTool*) -----

# ---- Layout ----------------------------------------------------------------

const
  MinChatRows = 5
  MinHeight   = MinChatRows + 3 + 1   # chat + input + statusbar
  MinWidth    = 40
  MaxToolHops = 5
  StreamChunkSize = 6
  StreamChunkSleepMs = 18

if consoleHeight() < MinHeight or consoleWidth() < MinWidth:
  echo "terminal too small for LM Studio chat demo"
  echo "  need at least ", MinWidth, "x", MinHeight + 2,
       " (current: ", terminalWidth(), "x", terminalHeight(), ")"
  quit(1)

var chat = newDisplay(id = "chat")
chat.title     = "conversation"
chat.border    = true
chat.wordwrap  = false
chat.statusbar = false

# Wrap `line` so each output row's *visual* width (East-Asian wide chars
# counted as 2) is ≤ `maxCells`. Tries to break at the last ASCII space
# seen; falls back to a hard break at the rune that overflows (the case
# for CJK text, which has no inter-word whitespace). Continuation rows
# are prefixed with `indent` so wrapped bodies stay under their
# Slack-style header.
proc wrapVisual(line: string, maxCells: int, indent: string): seq[string] =
  result = @[]
  if maxCells <= 0:
    result.add(line); return
  let indentCells = visualWidth(indent)
  var cur          = ""   # current line buffer (raw string)
  var curCells     = 0    # visual width of cur
  var lastSpaceLen = -1   # byte length of cur at the moment we saw a space
  for r in runes(line):
    let rs = $r
    let rw = runeWidth(r)
    if curCells + rw > maxCells and cur.len > 0:
      if lastSpaceLen > 0:
        # Break at the last space: head before it, tail (incl. current
        # rune) starts the next line under the indent.
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
    if r == Rune(' '):
      lastSpaceLen = cur.len
    cur.add(rs)
    curCells += rw
  if cur.len > 0: result.add(cur)

let chatRecalc: CustomRowRecal = proc(text: string, dp: Display): seq[string] =
  let w = max(10, dp.x2 - dp.x1 - 1)
  result = @[]
  for line in text.splitLines():
    if line.len == 0:
      result.add(" ")
      continue
    if visualWidth(line) <= w:
      result.add(line)
      continue
    let leading = line.len - line.strip(leading = true).len
    let indent  = if leading > 0: " ".repeat(leading) else: ""
    for piece in wrapVisual(line, w, indent):
      result.add(piece)
chat.useCustomTextRow = true
chat.customRowRecal = some(chatRecalc)

# CJK / wide-glyph correct rendering. illwill's TB model assumes one
# terminal column per rune, so anything written after a Chinese / Japanese /
# Korean / emoji char lands at the wrong screen column. Side-step it: tell
# Display to skip drawing the text rows (border/title/status still render),
# then in a postDisplay hook write each visible row to stdout directly. The
# terminal handles wide-char advancement natively — we just position the
# cursor at the start of each row and emit the bytes.
chat.textOverlay = true
chat.postDisplay = proc(wg: ref BaseWidget) =
  let dp = Display(wg)
  if dp.textRows.len == 0: return
  let widthCells = max(1, dp.x2 - dp.x1 - 1)
  let first = max(0, dp.rowCursor)
  let last  = min(dp.textRows.len - 1, first + dp.size - 1)
  # screen positions: tui_widget's posX/posY/x1/y1 are 0-indexed TB cells,
  # the terminal uses 1-indexed coords for cursor positioning.
  let screenCol = dp.x1 + 1
  let baseRow   = dp.y1 + 1
  for i in first..last:
    let row     = dp.textRows[i]
    let clipped = clipToVisualWidth(row, widthCells)
    let used    = visualWidth(clipped)
    # Pad to widthCells so the previous frame's content doesn't bleed
    # through where this row is shorter than the widget's inner width.
    let pad = if used < widthCells: " ".repeat(widthCells - used) else: ""
    let screenRow = baseRow + (i - first)
    stdout.write("\e[", screenRow, ";", screenCol, "f", clipped, pad)

var input = newInputBox(id = "input")
input.title     = "message (Enter to send, Tab cycles chat/input)"
input.border    = true
input.statusbar = false
input.enableTextOverlay()   # CJK-correct typing via stdout overlay

var status = newLabel(id = "status")
status.border    = false
status.focusable = false   # Tab skips the status bar entirely

var app = newTerminalApp(title = "LM Studio Chat",
                         border = false, rpms = 50)

# ---- Catch-all error hook --------------------------------------------------

app.onWidgetError = proc(widgetId, where, msg, trace: string) {.gcsafe.} =
  try:
    let f = open("lmstudio_chat.log", fmAppend)
    f.writeLine("[" & widgetId & "/" & where & "] " & msg)
    if trace.len > 0: f.writeLine(trace)
    f.close()
  except CatchableError: discard

# ---- Status-bar formatting -------------------------------------------------
# Left: short state text. Right: "<N> messages · <model>". Padded to width.

proc visibleMsgCount(): int =
  for m in history:
    if m.kind in {mkUser, mkAssistant}: inc result

proc setStatus(state: string) =
  let right = $visibleMsgCount() & " messages · " & modelId
  # Label's writable area is roughly consoleWidth - 4 cells (left + right
  # framing + a margin). Pad with a left-leading space, fill the middle,
  # and pin `right` flush right without going past the truncation limit.
  let w     = max(0, consoleWidth() - 4)
  let used  = state.len + right.len
  let pad   = max(1, w - used)
  status.text = " " & state & " ".repeat(pad) & right

# ---- Chat rendering --------------------------------------------------------

proc renderHistory() =
  var buf = ""
  for m in history:
    case m.kind
    of mkSystem: discard
    of mkUser, mkAssistant:
      let who   = if m.kind == mkUser: "you" else: "assistant"
      let stamp = m.ts.format("HH:mm")
      buf.add(stamp & "  " & who & "\n")
      for line in m.content.splitLines():
        buf.add("  " & line & "\n")
      buf.add("\n")
    of mkToolCall:
      let stamp = m.ts.format("HH:mm")
      buf.add(stamp & "  ⚙ tool call → " & m.name & "\n")
      for line in m.args.splitLines():
        buf.add("    " & line & "\n")
      buf.add("\n")
    of mkToolResult:
      let stamp = m.ts.format("HH:mm")
      buf.add(stamp & "  ⤳ result ← " & m.name & "\n")
      for line in m.content.splitLines():
        buf.add("    " & line & "\n")
      buf.add("\n")
  let preRows = chatRecalc(buf, chat).len
  chat.rowCursor = max(0, preRows - chat.size)
  chat.text = buf

# ---- Quote ticker thread ---------------------------------------------------

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
      # `thinkingQuotes` is a global of immutable string literals.
      # The cast tells Nim "trust me, read-only access is safe here".
      var q = ""
      {.cast(gcsafe).}:
        q = thinkingQuotes[r.rand(thinkingQuotes.high)]
      try: notify(appPtr, "status", "tick", q)
      except CatchableError: discard
    sleep(1400)

# ---- Status widget events --------------------------------------------------

status.on("tick", proc(lb: Label, args: varargs[string]) =
  if args.len > 0:
    setStatus("thinking · " & args[0])
)

# ---- Streaming + tool events on chat ---------------------------------------

# Streamed assistant message in progress: a buffer the chunks append to.
var streamBuf = ""

chat.on("reply_start", proc(dp: Display, args: varargs[string]) =
  streamBuf = ""
  history.add(Message(kind: mkAssistant, role: "assistant",
                      content: "", ts: now()))
  renderHistory()
)

chat.on("reply_chunk", proc(dp: Display, args: varargs[string]) =
  if args.len > 0 and history.len > 0:
    streamBuf.add(args[0])
    history[^1].content = streamBuf
    renderHistory()
)

chat.on("reply_end", proc(dp: Display, args: varargs[string]) =
  thinking.store(false)
  setStatus("ready")
)

chat.on("tool_call", proc(dp: Display, args: varargs[string]) =
  if args.len >= 2:
    history.add(Message(kind: mkToolCall, role: "tool",
                        name: args[0], args: args[1], ts: now()))
    renderHistory()
)

chat.on("tool_result", proc(dp: Display, args: varargs[string]) =
  if args.len >= 2:
    history.add(Message(kind: mkToolResult, role: "tool",
                        name: args[0], content: args[1], ts: now()))
    renderHistory()
)

chat.on("error", proc(dp: Display, args: varargs[string]) =
  thinking.store(false)
  setStatus("error · " & (if args.len > 0: args[0] else: "?"))
)

# ---- Background agent loop -------------------------------------------------
# Synchronous HTTP via Nim httpclient. Tool-calling is handled here: if the
# model returns tool_calls, execute each, append the results to `msgs`, and
# loop. The final non-tool reply is fake-streamed back to the chat by
# chunking the content and notifying with small sleeps.

proc llmCall(client: var HttpClient, url: string,
             msgs: JsonNode): JsonNode {.gcsafe.} =
  # toolSpecs and modelId are module-level GC-managed globals. They're
  # read-only here, so the cast is safe — gcsafe checker just can't prove
  # it across the background-thread boundary.
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
  # Build headers; only attach Authorization if a non-empty token was set.
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
      # Track assistant message in API history regardless of tool_calls.
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
            "content": res
          })
        continue   # let the model react to the tool results
      else:
        let text = msg{"content"}.getStr("")
        streamOut(appPtr, text)
        return
    notify(appPtr, "chat", "error",
           "stopped after " & $MaxToolHops & " tool hops without a reply")
  except CatchableError:
    notify(appPtr, "chat", "error", getCurrentExceptionMsg())

# ---- Build the API message array from the display history -----------------
# Include system, user, AND finalised assistant replies so each new turn
# carries the conversation context. Without prior assistant messages the
# model loses memory of what it already did and re-runs the same tool
# calls on the next user turn (the original bug). Tool call / result
# rows are display-only — their content is already summarised inside the
# assistant's final reply, so omitting them here keeps the API payload
# small while preserving meaning.

proc apiMessages(): JsonNode =
  result = newJArray()
  for m in history:
    case m.kind
    of mkSystem, mkUser, mkAssistant:
      # Skip an empty assistant placeholder (one that's still mid-stream
      # when this is called shouldn't be sent back).
      if m.kind == mkAssistant and m.content.len == 0: continue
      result.add(%*{"role": m.role, "content": m.content})
    of mkToolCall, mkToolResult:
      discard

# ---- Input handler ---------------------------------------------------------

input.onEnter = proc(ib: InputBox, args: varargs[string]) =
  let userMsg = ib.value.strip()
  if userMsg.len == 0: return
  ib.value = ""
  history.add(Message(kind: mkUser, role: "user",
                      content: userMsg, ts: now()))
  renderHistory()
  thinking.store(true)
  setStatus("thinking...")
  let msgsJson = $apiMessages()
  runInBackground(toTask agentLoop(addr app, endpoint, apiKey, msgsJson))

# ---- Wire up and run -------------------------------------------------------

app.addWidget(chat,   1.0, 0.85)
app.addWidget(input,  1.0, 0.1)
app.addWidget(status, 1.0, 0.05)

renderHistory()
setStatus("ready")
createThread(quoteThread, quoteLoop, addr app)
app.run(nonBlocking = true)
