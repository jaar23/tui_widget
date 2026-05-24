import ../src/tui_widget
import httpclient, json, net, os, std/tasks, strutils, times, std/wordwrap,
       options, random, std/atomics, std/parseopt, unicode, algorithm
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

# ---- Chat-history persistence ---------------------------------------------
#
# Each chat is one JSON file under ./chatui/data/. Filename is
#   chat-<yyyyMMdd-HHmmss>-<slug>.json
# where `<slug>` comes from the first user message. The display name shown
# in the history sidebar is the human-readable name stored INSIDE the file
# (so renames don't have to touch the filename).

const ChatDir = "chatui/data"
const MaxContextTokens = 8192  # for the context-% in the status bar

var currentChatPath = ""   # set after the first user message is saved
var currentChatName = ""

# /yolo toggles this on (auto-accept dangerous tools), /review toggles it
# off (default — confirm dialog). Read by gatedExecTool and setStatus.
# Declared early so setStatus can read it; lives at module scope so the
# background agent thread can see it via {.cast(gcsafe).}.
var yoloMode: Atomic[bool]
yoloMode.store(false)

proc msgToJson(m: Message): JsonNode =
  %*{"kind":    $m.kind,
     "role":    m.role,
     "content": m.content,
     "name":    m.name,
     "args":    m.args,
     "ts":      m.ts.format("yyyy-MM-dd'T'HH:mm:sszzz")}

proc msgFromJson(j: JsonNode): Message =
  let kindStr = j{"kind"}.getStr("mkUser")
  var k = mkUser
  for mk in MsgKind:
    if $mk == kindStr: k = mk; break
  let ts =
    try: parse(j{"ts"}.getStr(""), "yyyy-MM-dd'T'HH:mm:sszzz")
    except CatchableError: now()
  Message(kind: k,
          role:    j{"role"}.getStr(""),
          content: j{"content"}.getStr(""),
          name:    j{"name"}.getStr(""),
          args:    j{"args"}.getStr(""),
          ts:      ts)

proc slugify(s: string): string =
  ## "Make a hello world program!" → "make-a-hello-world-program"
  result = ""
  var prevDash = true
  for r in s.toLowerAscii():
    if r in {'a'..'z', '0'..'9'}:
      result.add(r); prevDash = false
    elif not prevDash:
      result.add('-'); prevDash = true
    if result.len >= 40: break
  while result.endsWith('-'): result.setLen(result.len - 1)
  if result.len == 0: result = "chat"

proc generateChatPath(seedMsg: string): string =
  let stamp = now().format("yyyyMMdd-HHmmss")
  let slug = slugify(seedMsg)
  ChatDir / ("chat-" & stamp & "-" & slug & ".json")

proc displayNameOf(messages: seq[Message]): string =
  ## Use the first user message as the chat's display name.
  for m in messages:
    if m.kind == mkUser and m.content.len > 0:
      let trimmed = m.content.strip().replace("\n", " ")
      if trimmed.len <= 50: return trimmed
      return trimmed[0 ..< 50] & "…"
  return "(empty chat)"

proc saveCurrentChat() {.gcsafe.} =
  ## Persist the current `history` to `currentChatPath`. Called from the
  ## main thread (event handlers), so accessing the globals is safe.
  {.cast(gcsafe).}:
    if history.len <= 1: return               # nothing but the system msg
    try:
      createDir(ChatDir)
      if currentChatPath.len == 0:
        var seed = ""
        for m in history:
          if m.kind == mkUser: seed = m.content; break
        currentChatPath = generateChatPath(seed)
      if currentChatName.len == 0:
        currentChatName = displayNameOf(history)
      var msgs = newJArray()
      for m in history: msgs.add(msgToJson(m))
      let doc = %*{"name":    currentChatName,
                   "model":   modelId,
                   "created": now().format("yyyy-MM-dd'T'HH:mm:sszzz"),
                   "messages": msgs}
      writeFile(currentChatPath, doc.pretty())
    except CatchableError:
      discard  # storage failures shouldn't kill the chat loop

type
  ChatSummary = object
    path: string
    name: string
    created: string   # raw ISO string from the file

proc listSavedChats(): seq[ChatSummary] =
  ## Scan ChatDir and return summaries newest-first. Bad/missing fields
  ## fall back to filename + epoch so a partial save can still appear in
  ## the sidebar.
  result = @[]
  if not dirExists(ChatDir): return
  for kind, p in walkDir(ChatDir):
    if kind != pcFile: continue
    if not p.endsWith(".json"): continue
    var name = p.extractFilename()
    var created = ""
    try:
      let doc = parseJson(readFile(p))
      name    = doc{"name"}.getStr(name)
      created = doc{"created"}.getStr("")
    except CatchableError: discard
    result.add(ChatSummary(path: p, name: name, created: created))
  result.sort(proc(a, b: ChatSummary): int = cmp(b.created, a.created))

proc loadChat(path: string): bool =
  ## Replace `history` with the messages from `path`. Returns false on
  ## any parse / IO failure (caller can leave history untouched).
  try:
    let doc = parseJson(readFile(path))
    var newHistory: seq[Message] = @[]
    if doc.hasKey("messages"):
      for j in doc["messages"]:
        newHistory.add(msgFromJson(j))
    if newHistory.len == 0: return false
    history = newHistory
    currentChatPath = path
    currentChatName = doc{"name"}.getStr(displayNameOf(history))
    return true
  except CatchableError:
    return false

# ---- Tool layer is in `./lmstudio_tools` (see toolSpecs* / execTool*) -----

# ---- Layout / minimum size checks -----------------------------------------

const
  MinChatRows = 5
  MinHeight   = MinChatRows + 3 + 1
  MinWidth    = 70                 # need ~20 cols for the history sidebar
  MaxToolHops = 12
  StreamChunkSize = 6
  StreamChunkSleepMs = 18

if consoleHeight() < MinHeight or consoleWidth() < MinWidth:
  echo "terminal too small for LM Studio chat demo"
  echo "  need at least ", MinWidth, "x", MinHeight + 2,
       " (current: ", terminalWidth(), "x", terminalHeight(), ")"
  quit(1)

# ---- Layout (absolute coords) ---------------------------------------------
#
# The right sidebar is split into two stacked ListViews — history on top,
# jobs on bottom — which the framework's proportional auto-stack can't
# express. So all widgets get explicit `x1,y1,x2,y2` and are added via
# `app.addWidget(widget)` (no-size variant). Auto-resize still works
# because addWidget snapshots origPosX/origPosY/origWidth/origHeight.

let consoleW   = consoleWidth()
let consoleH   = consoleHeight()
let sidebarX   = max(MinWidth - 20, (consoleW.float * 0.78).int)
let chatRight  = sidebarX
let sidebarL   = sidebarX + 1
let sidebarR   = consoleW
let inputRows  = 3
let statusRows = 1
let chatBottom   = consoleH - inputRows - statusRows
let historyTop   = 1
let historyBot   = max(historyTop + 3, chatBottom div 2)
let jobsTop      = historyBot + 1
let jobsBot      = chatBottom
let inputTop     = chatBottom + 1
let inputBot     = inputTop + inputRows - 1
let statusTop    = inputBot + 1
let statusBot    = statusTop

var chat = newListView(1, 1, chatRight, chatBottom, id = "chat")
chat.title          = "conversation"
chat.border         = true
chat.statusbar      = false
chat.selectionStyle = Highlight
chat.enableTextOverlay()   # CJK-safe row drawing + inverse-video selection

# Right-side history panel (top half of sidebar). Each row's `value` is the
# on-disk path; clicking (or pressing Enter on) a row loads that chat.
var historyLv = newListView(sidebarL, historyTop, sidebarR, historyBot,
                            id = "history")
historyLv.title          = "history (Enter=load · d=del)"
historyLv.border         = true
historyLv.statusbar      = false
historyLv.selectionStyle = Highlight
historyLv.enableTextOverlay()

# Right-side jobs watch panel (bottom half of sidebar). Each row's `value`
# is the job id as a string; pressing `k` kills it, `d` removes the row
# (only allowed for finished jobs).
var jobsLv = newListView(sidebarL, jobsTop, sidebarR, jobsBot, id = "jobs")
jobsLv.title          = "jobs (k=kill · d=remove)"
jobsLv.border         = true
jobsLv.statusbar      = false
jobsLv.selectionStyle = Highlight
jobsLv.enableTextOverlay()

var input = newInputBox(1, inputTop, consoleW, inputBot,
                        title = "message (/new /stop /yolo /review /quit · Enter to send)")
input.id        = "input"
input.border    = true
input.statusbar = false
input.enableTextOverlay()

var status = newLabel(1, statusTop, consoleW, statusBot)
status.id        = "status"
status.border    = false
status.focusable = false

# ---- Confirmation popup ---------------------------------------------------
#
# Centered modal over the chat. Hidden + non-focusable by default; brought
# forward by the agent thread when it's about to invoke a dangerous tool.
# The Container draws the frame and title only — the message label and
# Confirm/Cancel buttons are top-level siblings, because the framework's
# Tab handling intercepts at the app layer and doesn't reach Container's
# internal child cycling in non-blocking mode.

let popupW  = min(64, consoleW - 4)
let popupH  = 10
let popupX1 = ((consoleW - popupW) div 2) + 1
let popupY1 = ((consoleH - popupH) div 2) + 1
let popupX2 = popupX1 + popupW
let popupY2 = popupY1 + popupH

var confirmPopup = newContainer(popupX1, popupY1, popupX2, popupY2,
                                title = " Confirm dangerous action ")
confirmPopup.id = "confirm_popup"

var confirmMsg = newLabel(popupX1 + 2, popupY1 + 2,
                          popupX2 - 2, popupY1 + 6)
confirmMsg.id        = "confirm_msg"
confirmMsg.border    = false
confirmMsg.focusable = false

let btnY1 = popupY2 - 3
let btnY2 = popupY2 - 1
let btnW  = 14
let confirmBtnX1 = popupX1 + (popupW div 2) - btnW - 2
let confirmBtnX2 = confirmBtnX1 + btnW
let cancelBtnX1  = popupX1 + (popupW div 2) + 2
let cancelBtnX2  = cancelBtnX1 + btnW

var confirmBtn = newButton(confirmBtnX1, btnY1, confirmBtnX2, btnY2,
                           label = "Confirm")
confirmBtn.id = "confirm_yes"

var cancelBtn = newButton(cancelBtnX1, btnY1, cancelBtnX2, btnY2,
                         label = "Cancel")
cancelBtn.id = "confirm_no"

# Hidden + non-focusable until showConfirm() opens the dialog.
for w in [(ref BaseWidget)(confirmPopup), (ref BaseWidget)(confirmMsg),
          (ref BaseWidget)(confirmBtn), (ref BaseWidget)(cancelBtn)]:
  w.visibility = false
  w.focusable  = false

# Cross-thread channel: agent thread sends the request via `notify`, blocks
# on `confirmCh.recv`. The button onEnter handlers `confirmCh.send(...)`.
var confirmCh: system.Channel[bool]
confirmCh.open()

# ---- Tool-details popup --------------------------------------------------
#
# The chat compacts each tool call/result to a single row; pressing Enter
# on one opens this read-only popup with the full args or content. Larger
# than the confirm dialog because tool outputs can be long.

let detailW  = min(96, consoleW - 4)
let detailH  = min(consoleH - 4, 22)
let detailX1 = ((consoleW - detailW) div 2) + 1
let detailY1 = ((consoleH - detailH) div 2) + 1
let detailX2 = detailX1 + detailW
let detailY2 = detailY1 + detailH

var detailPopup = newContainer(detailX1, detailY1, detailX2, detailY2,
                               title = " Tool details — Enter on Close to dismiss ")
detailPopup.id = "detail_popup"

var detailBody = newDisplay(detailX1 + 1, detailY1 + 1,
                            detailX2 - 1, detailY2 - 4)
detailBody.id        = "detail_body"
detailBody.border    = false
detailBody.focusable = true   # so user can scroll with arrow keys

let dBtnY1 = detailY2 - 3
let dBtnY2 = detailY2 - 1
let dBtnW  = 14
let detailCloseX1 = ((detailX1 + detailX2) div 2) - (dBtnW div 2)
let detailCloseX2 = detailCloseX1 + dBtnW
var detailCloseBtn = newButton(detailCloseX1, dBtnY1,
                               detailCloseX2, dBtnY2, label = "Close")
detailCloseBtn.id = "detail_close"

for w in [(ref BaseWidget)(detailPopup), (ref BaseWidget)(detailBody),
          (ref BaseWidget)(detailCloseBtn)]:
  w.visibility = false
  w.focusable  = false

var app = newTerminalApp(title = "LM Studio Chat (ListView)",
                         border = false, rpms = 50)
app.enableMouse()   # click rows / input / history to focus + fire events

app.onWidgetError = proc(widgetId, where, msg, trace: string) {.gcsafe.} =
  try:
    let f = open("lmstudio_chat_listview.log", fmAppend)
    f.writeLine("[" & widgetId & "/" & where & "] " & msg)
    if trace.len > 0: f.writeLine(trace)
    f.close()
  except CatchableError: discard

# ---- Confirmation dialog control -----------------------------------------

# Saved focusable state of every app.widget while the popup is open, so
# Tab can't escape to the chat / history / jobs panels mid-prompt.
var savedFocusable: seq[bool] = @[]
var inputCursorIdx = -1

proc showConfirm(promptText: string) =
  ## Open the dialog with `promptText` and grab focus on Cancel.
  # Label is single-line; literal `\n` in the text breaks the terminal to
  # column 0 and the text escapes the popup box. Flatten newlines and
  # collapse the double-blank that `describeTool` uses as a paragraph
  # break before the ⚠ warning, into a single visual separator.
  confirmMsg.text = promptText
    .replace("\n\n", "  ·  ")
    .replace("\n", "  ")
  confirmPopup.visibility = true
  confirmMsg.visibility   = true
  confirmBtn.visibility   = true
  cancelBtn.visibility    = true
  # The chat / history / jobs / input widgets all use enableTextOverlay()
  # which writes directly to stdout via postDisplay AFTER the buffer is
  # flushed. That overlay paints OVER the popup area and makes the dialog
  # unreadable. Disable each widget's overlay flag for the duration of the
  # popup — the closure exits early when textOverlay is false, and the
  # widget's normal buffer-based render still draws its content (just
  # without the CJK-safe overlay, which doesn't matter for the few
  # seconds the dialog is up).
  chat.textOverlay      = false
  historyLv.textOverlay = false
  jobsLv.textOverlay    = false
  input.textOverlay     = false
  # Snapshot every widget's focusable; clear all except the two buttons so
  # Tab inside the dialog only cycles Confirm ↔ Cancel.
  savedFocusable.setLen(app.widgets.len)
  var cancelIdx = -1
  for i, w in app.widgets:
    savedFocusable[i] = w.focusable
    if w.id == "confirm_yes" or w.id == "confirm_no":
      w.focusable = true
    else:
      w.focusable = false
    if w.id == "confirm_no": cancelIdx = i
  # Move app focus to Cancel by default (user picked: conservative default).
  if cancelIdx >= 0:
    if app.cursor < app.widgets.len:
      app.widgets[app.cursor].focus = false
    app.cursor = cancelIdx
    app.widgets[cancelIdx].focus = true

proc hideConfirm() =
  ## Tear down the dialog and restore Tab cycle.
  confirmPopup.visibility = false
  confirmMsg.visibility   = false
  confirmBtn.visibility   = false
  cancelBtn.visibility    = false
  confirmMsg.text         = ""
  # Re-enable the per-widget text overlays we disabled in showConfirm.
  chat.textOverlay      = true
  historyLv.textOverlay = true
  jobsLv.textOverlay    = true
  input.textOverlay     = true
  for i, w in app.widgets:
    if i < savedFocusable.len:
      w.focusable = savedFocusable[i]
    w.focus = false
  # Hand focus back to the input box.
  if inputCursorIdx < 0:
    for i, w in app.widgets:
      if w.id == "input": inputCursorIdx = i; break
  if inputCursorIdx >= 0:
    app.cursor = inputCursorIdx
    app.widgets[inputCursorIdx].focus = true

confirmBtn.onEnter = proc(btn: Button, args: varargs[string]) =
  hideConfirm()
  discard confirmCh.trySend(true)

cancelBtn.onEnter = proc(btn: Button, args: varargs[string]) =
  hideConfirm()
  discard confirmCh.trySend(false)

# Agent thread fires `notify(appPtr, "chat", "confirm_ask", prompt)` and
# blocks on the channel. Main thread shows the dialog here.
chat.on("confirm_ask", proc(lv: ListView, args: varargs[string]) =
  if args.len > 0:
    showConfirm(args[0]))

# ---- Tool-details dialog control -----------------------------------------

var savedFocusableDetail: seq[bool] = @[]

proc showToolDetails(bodyText: string) =
  ## Open the read-only details popup with `bodyText` shown in a Display.
  ## Same overlay/focus dance as showConfirm.
  detailBody.text = bodyText
  detailPopup.visibility    = true
  detailBody.visibility     = true
  detailCloseBtn.visibility = true
  chat.textOverlay      = false
  historyLv.textOverlay = false
  jobsLv.textOverlay    = false
  input.textOverlay     = false
  savedFocusableDetail.setLen(app.widgets.len)
  var closeIdx = -1
  for i, w in app.widgets:
    savedFocusableDetail[i] = w.focusable
    if w.id == "detail_close" or w.id == "detail_body":
      w.focusable = true
    else:
      w.focusable = false
    if w.id == "detail_close": closeIdx = i
  if closeIdx >= 0:
    if app.cursor < app.widgets.len:
      app.widgets[app.cursor].focus = false
    app.cursor = closeIdx
    app.widgets[closeIdx].focus = true

proc hideToolDetails() =
  detailPopup.visibility    = false
  detailBody.visibility     = false
  detailCloseBtn.visibility = false
  detailBody.text           = ""
  chat.textOverlay      = true
  historyLv.textOverlay = true
  jobsLv.textOverlay    = true
  input.textOverlay     = true
  for i, w in app.widgets:
    if i < savedFocusableDetail.len:
      w.focusable = savedFocusableDetail[i]
    w.focus = false
  if inputCursorIdx < 0:
    for i, w in app.widgets:
      if w.id == "input": inputCursorIdx = i; break
  if inputCursorIdx >= 0:
    app.cursor = inputCursorIdx
    app.widgets[inputCursorIdx].focus = true

detailCloseBtn.onEnter = proc(btn: Button, args: varargs[string]) =
  hideToolDetails()

# Enter on a tool-row in chat opens the details popup. Row values for
# tool rows look like "tool:N" — anything else is just text and ignored.
chat.onEnter = proc(lv: ListView, args: varargs[string]) =
  if args.len == 0: return
  let v = args[0]
  if not v.startsWith("tool:"): return
  try:
    let idx = parseInt(v[5..^1])
    if idx < 0 or idx >= history.len: return
    let m = history[idx]
    var body = ""
    case m.kind
    of mkToolCall:
      body = "tool:    " & m.name & "\n" &
             "called:  " & m.ts.format("yyyy-MM-dd HH:mm:ss") & "\n" &
             "\n--- arguments ---\n" & m.args
    of mkToolResult:
      body = "tool:    " & m.name & "\n" &
             "result:  " & m.ts.format("yyyy-MM-dd HH:mm:ss") & "\n" &
             "\n--- output ---\n" & m.content
    else: return
    showToolDetails(body)
  except CatchableError: discard

# ---- Status bar -----------------------------------------------------------

proc visibleMsgCount(): int =
  for m in history:
    if m.kind in {mkUser, mkAssistant}: inc result

proc contextPct(): int =
  ## Approximate token count via 4-chars-per-token. Capped to 100.
  var chars = 0
  for m in history: chars += m.content.len
  let tokens = (chars + 3) div 4
  result = clamp(tokens * 100 div MaxContextTokens, 0, 100)

proc setStatus(state: string) =
  let mode = if yoloMode.load(): "YOLO" else: "REVIEW"
  let right = mode & " · " & $visibleMsgCount() & " msgs · " & modelId &
              " · " & $contextPct() & "% ctx"
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
  proc add(text: string, value = "") =
    # ListRow text holds a single visual row; blank rows use a single
    # space so the overlay clears the line (overlay treats "" as no-op
    # in `clipToVisualWidth` and the row would render entirely blank).
    let t = if text.len == 0: " " else: text
    let v = if value.len == 0: t else: value
    rows.add(newListRow(idx, t, v))
    inc idx
  for i, m in history:
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
      # Compact: one row. Full args available in a popup via Enter; the
      # row's `value` is "tool:<history-index>" so the chat onEnter handler
      # can look it up.
      let stamp = m.ts.format("HH:mm")
      add(stamp & "  ⚙ → " & m.name & "   (Enter to view)",
          value = "tool:" & $i)
    of mkToolResult:
      let stamp = m.ts.format("HH:mm")
      let oneLine = m.content.replace("\n", " ").strip()
      let preview = if oneLine.len > 60: oneLine[0 ..< 60] & "…" else: oneLine
      add(stamp & "  ⤳ " & m.name & "  " & preview,
          value = "tool:" & $i)
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
  else:
    # Defensive: stale rowCursor/selectedRow from a prior frame point
    # at deleted rows. ListView's render guards against this at the
    # top, but other code paths (scrollRow / right-arrow) read
    # lv.rows[selectedRow] unconditionally.
    chat.rowCursor = 0
    chat.selectedRow = 0

# ---- History sidebar ------------------------------------------------------

proc refreshHistoryList(preferredCursor = -1) =
  ## Rebuild the sidebar from disk. `preferredCursor` lets callers (e.g.
  ## the delete handler) ask for the cursor to land near a specific row
  ## after the refresh; it's clamped into range. When the list goes empty
  ## we must reset both rowCursor and selectedRow — ListView's render
  ## reads lv.rows[selectedRow] without bounds-checking and would crash
  ## if we left a stale index pointing past the (now zero) row count.
  var rows: seq[ListRow] = @[]
  var idx = 0
  for s in listSavedChats():
    let display = if s.name.len > 40: s.name[0 ..< 40] & "…" else: s.name
    let marker = if s.path == currentChatPath: "● " else: "  "
    rows.add(newListRow(idx, marker & display, s.path))
    inc idx
  historyLv.rows = rows
  if rows.len == 0:
    historyLv.rowCursor = 0
    historyLv.selectedRow = 0
    return
  let target =
    if preferredCursor < 0: 0
    else: clamp(preferredCursor, 0, rows.len - 1)
  historyLv.rowCursor = target
  historyLv.selectedRow = target
  for r in rows: r.selected = false
  rows[target].selected = true

historyLv.onEnter = proc(lv: ListView, args: varargs[string]) =
  if args.len > 0 and args[0].len > 0:
    if loadChat(args[0]):
      rebuildRows()
      refreshHistoryList()
      setStatus("loaded · " & currentChatName)

# Press `d` on a row in the history sidebar to delete that saved chat.
# If the deleted row was the active chat, also reset the in-memory history
# so the next user message starts a fresh file.
historyLv.on(Key.D, proc(lv: ListView, args: varargs[string]) =
  if lv.rows.len == 0: return
  if lv.selectedRow < 0 or lv.selectedRow >= lv.rows.len: return
  let deletedAt = lv.selectedRow
  let path = lv.rows[deletedAt].value
  if path.len == 0: return
  let wasCurrent = path == currentChatPath
  try: removeFile(path)
  except CatchableError:
    setStatus("delete failed: " & getCurrentExceptionMsg()); return
  if wasCurrent:
    history = @[history[0]]   # keep just the system message
    currentChatPath = ""
    currentChatName = ""
    rebuildRows()
  refreshHistoryList(preferredCursor = deletedAt)
  if historyLv.rows.len == 0:
    setStatus("deleted · history empty")
  else:
    setStatus("deleted"))

# ---- Jobs sidebar ---------------------------------------------------------

proc refreshJobsList(preferredCursor = -1) =
  ## Snapshot the jobs registry and rebuild the sidebar rows. Each row's
  ## `value` is the job id as a string so the key handlers can look it up.
  var rows: seq[ListRow] = @[]
  var idx = 0
  let nowSec = epochTime().int64
  for j in snapshotJobs():
    let endT = if j.status == jsRunning: nowSec else: j.finished
    let runtime = max(0, endT - j.started)
    # Sidebar is narrow; keep the row label compact: "#3 run 12s"
    let cmdPreview =
      if j.cmd.len > 14: j.cmd[0 ..< 14] & "…" else: j.cmd
    let label = "#" & $j.id & " " & statusLabel(j.status) &
                " " & $runtime & "s " & cmdPreview
    rows.add(newListRow(idx, label, $j.id))
    inc idx
  jobsLv.rows = rows
  if rows.len == 0:
    jobsLv.rowCursor = 0
    jobsLv.selectedRow = 0
    return
  let target =
    if preferredCursor < 0: 0
    else: clamp(preferredCursor, 0, rows.len - 1)
  jobsLv.rowCursor = target
  jobsLv.selectedRow = target
  for r in rows: r.selected = false
  rows[target].selected = true

# k = kill a running job (no-op on already-finished jobs).
jobsLv.on(Key.K, proc(lv: ListView, args: varargs[string]) =
  if lv.rows.len == 0: return
  if lv.selectedRow < 0 or lv.selectedRow >= lv.rows.len: return
  let idStr = lv.rows[lv.selectedRow].value
  if idStr.len == 0: return
  try:
    let res = execTool("kill_job", %*{"id": parseInt(idStr)})
    setStatus(res)
    refreshJobsList(preferredCursor = lv.selectedRow)
  except CatchableError:
    setStatus("kill failed: " & getCurrentExceptionMsg()))

# d = remove a finished job from the watch list. Refuses for running jobs.
jobsLv.on(Key.D, proc(lv: ListView, args: varargs[string]) =
  if lv.rows.len == 0: return
  if lv.selectedRow < 0 or lv.selectedRow >= lv.rows.len: return
  let removedAt = lv.selectedRow
  let idStr = lv.rows[removedAt].value
  if idStr.len == 0: return
  try:
    let id = parseInt(idStr)
    if removeJob(id):
      setStatus("removed job #" & $id)
      refreshJobsList(preferredCursor = removedAt)
    else:
      setStatus("job #" & $id & " is running — press k first")
  except CatchableError:
    setStatus("remove failed: " & getCurrentExceptionMsg()))

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
# Set by the /stop slash command. The agent loop checks this at the top of
# every hop (and before streaming each chunk) and bails out cleanly.
var cancelled: Atomic[bool]
cancelled.store(false)
var quoteThread: Thread[ptr TerminalApp]

proc quoteLoop(appPtr: ptr TerminalApp) {.thread, gcsafe.} =
  ## Two cadences in one thread: a 1.4s "thinking..." quote refresh, and
  ## a 1.5s jobs-list tick so runtime counters in the watch panel update
  ## without spawning a second thread.
  var r = initRand(getTime().toUnix())
  var jobsTickAt = 0
  while true:
    if thinking.load():
      var q = ""
      {.cast(gcsafe).}:
        q = thinkingQuotes[r.rand(thinkingQuotes.high)]
      try: notify(appPtr, "status", "tick", q)
      except CatchableError: discard
    inc jobsTickAt
    if jobsTickAt >= 1:                # every iter ≈ 1.4s — good enough
      jobsTickAt = 0
      try: notify(appPtr, "jobs", "tick")
      except CatchableError: discard
    sleep(1400)

status.on("tick", proc(lb: Label, args: varargs[string]) =
  if args.len > 0: setStatus("thinking · " & args[0]))

jobsLv.on("tick", proc(lv: ListView, args: varargs[string]) =
  refreshJobsList(preferredCursor = lv.selectedRow))

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
  saveCurrentChat()
  refreshHistoryList()
  setStatus("ready"))

chat.on("tool_call", proc(lv: ListView, args: varargs[string]) =
  if args.len >= 2:
    history.add(Message(kind: mkToolCall, role: "tool",
                        name: args[0], args: args[1], ts: now()))
    rebuildRows()
    # If the agent just kicked off (or touched) a background job, refresh
    # the watch panel right away instead of waiting up to 1.4s for the
    # next tick — otherwise the user sees the chat say "tool: start_job"
    # but the jobs sidebar stays empty for a beat.
    if args[0] in ["start_job", "kill_job"]:
      refreshJobsList(preferredCursor = jobsLv.selectedRow))

chat.on("tool_result", proc(lv: ListView, args: varargs[string]) =
  if args.len >= 2:
    history.add(Message(kind: mkToolResult, role: "tool",
                        name: args[0], content: args[1], ts: now()))
    rebuildRows()
    if args[0] in ["start_job", "kill_job"]:
      refreshJobsList(preferredCursor = jobsLv.selectedRow))

chat.on("error", proc(lv: ListView, args: varargs[string]) =
  thinking.store(false)
  setStatus("error · " & (if args.len > 0: args[0] else: "?")))

# ---- Background agent loop ------------------------------------------------

proc llmCall(url, token: string, msgs: JsonNode,
             withTools = true): JsonNode {.gcsafe.} =
  ## Build a fresh HttpClient per request. The agent loop may sit idle
  ## for minutes while the user thinks about a confirm dialog, and the
  ## LM Studio server (or any intermediate proxy) will close keep-alive
  ## connections that idle past ~30s. Reusing a stale client gives
  ## "connection was closed before full request has been made" on the
  ## next round-trip. Per-call clients pay one extra TCP+TLS handshake
  ## (negligible vs LLM inference latency) but never go stale.
  var bodyStr = ""
  {.cast(gcsafe).}:
    var body = %*{
      "model": modelId,
      "messages": msgs,
      "stream": false,
      "temperature": 0.6}
    if withTools:
      body["tools"] = toolSpecs
      body["tool_choice"] = %"auto"
    bodyStr = $body
  var client = newHttpClient(timeout = 60_000,
                            sslContext = newContext(
                              verifyMode = CVerifyPeerUseEnvVars))
  defer: client.close()
  var headerPairs = @[("Content-Type", "application/json")]
  if token.len > 0:
    headerPairs.add(("Authorization", "Bearer " & token))
  client.headers = newHttpHeaders(headerPairs)
  let resp = client.request(url, httpMethod = HttpPost, body = bodyStr)
  if resp.code != Http200:
    raise newException(IOError,
      "HTTP " & $resp.code.int & ": " &
      resp.body[0 .. min(200, resp.body.high)])
  result = parseJson(resp.body)

proc gatedExecTool(appPtr: ptr TerminalApp, name: string,
                   args: JsonNode): string {.gcsafe.} =
  ## Run `execTool` for read-only tools. For mutating tools (see
  ## `isDangerous` in lmstudio_tools), behaviour depends on the current
  ## mode: YOLO auto-accepts; REVIEW (default) pauses the agent thread,
  ## notifies the main thread to show the confirm/cancel popup, and blocks
  ## on the channel for the user's answer. Cancel returns a literal
  ## "cancelled by user" so the LLM can react (often by picking a
  ## different tool).
  if not isDangerous(name):
    return execTool(name, args)
  if yoloMode.load():
    return execTool(name, args)
  let prompt = describeTool(name, args)
  {.cast(gcsafe).}:
    notify(appPtr, "chat", "confirm_ask", prompt)
    let approved = confirmCh.recv()
    if approved:
      return execTool(name, args)
    return "cancelled by user"

proc streamOut(appPtr: ptr TerminalApp, text: string) {.gcsafe.} =
  notify(appPtr, "chat", "reply_start")
  var i = 0
  while i < text.len:
    if cancelled.load(): break
    let nxt = min(i + StreamChunkSize, text.len)
    notify(appPtr, "chat", "reply_chunk", text[i ..< nxt])
    i = nxt
    sleep(StreamChunkSleepMs)
  notify(appPtr, "chat", "reply_end")

proc agentLoop(appPtr: ptr TerminalApp,
               url, token, msgsJson: string) {.gcsafe.} =
  try:
    var msgs = parseJson(msgsJson)
    var hops = 0
    while hops < MaxToolHops:
      if cancelled.load():
        notify(appPtr, "chat", "error", "stopped by user"); return
      inc hops
      let parsed = llmCall(url, token, msgs)
      let msg    = parsed["choices"][0]["message"]
      msgs.add(msg)
      if msg.hasKey("tool_calls") and msg["tool_calls"].len > 0:
        for tc in msg["tool_calls"]:
          if cancelled.load():
            notify(appPtr, "chat", "error", "stopped by user"); return
          let tcId   = tc["id"].getStr()
          let tName  = tc["function"]["name"].getStr()
          let tArgsS = tc["function"]["arguments"].getStr()
          notify(appPtr, "chat", "tool_call", tName, tArgsS)
          var tArgs: JsonNode
          try: tArgs = parseJson(tArgsS)
          except CatchableError: tArgs = newJObject()
          let res = gatedExecTool(appPtr, tName, tArgs)
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
    # Hop budget exceeded. Don't leave the user staring at an error — make
    # one more call with tools disabled so the model is forced to answer
    # in plain text using whatever it has already gathered.
    msgs.add(%*{"role": "user",
                "content": "You have reached the tool-call limit (" &
                  $MaxToolHops & "). Stop calling tools and write a final " &
                  "answer for the user now using the information you already " &
                  "have. If the gathered information is insufficient, say so."})
    let final = llmCall(url, token, msgs, withTools = false)
    let finalMsg = final["choices"][0]["message"]
    let finalText = finalMsg{"content"}.getStr("")
    if finalText.len > 0:
      streamOut(appPtr, finalText)
    else:
      notify(appPtr, "chat", "error",
             "stopped after " & $MaxToolHops &
             " tool hops with no final reply")
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
  # Slash commands are handled locally; they never go to the LLM.
  if userMsg.startsWith("/"):
    case userMsg.toLowerAscii()
    of "/new":
      # Cancel any in-flight agent loop FIRST — otherwise a pending reply
      # lands in the freshly-reset history and looks like /new failed.
      cancelled.store(true)
      thinking.store(false)
      saveCurrentChat()
      history = @[history[0]]   # keep only the system message
      currentChatPath = ""
      currentChatName = ""
      rebuildRows()
      refreshHistoryList()
      setStatus("new chat")
      return
    of "/stop":
      cancelled.store(true)
      setStatus("stopping…")
      return
    of "/yolo":
      yoloMode.store(true)
      setStatus("YOLO mode — dangerous tools auto-accepted")
      return
    of "/review":
      yoloMode.store(false)
      setStatus("REVIEW mode — dangerous tools require confirmation")
      return
    of "/quit", "/exit":
      saveCurrentChat()
      illwillDeinit()
      showCursor()
      quit(0)
    else:
      setStatus("unknown command: " & userMsg)
      return
  # New user-message — clear any stale stop flag from a previous turn.
  cancelled.store(false)
  history.add(Message(kind: mkUser, role: "user",
                      content: userMsg, ts: now()))
  rebuildRows()
  saveCurrentChat()
  refreshHistoryList()
  thinking.store(true)
  setStatus("thinking...")
  let msgsJson = $apiMessages()
  runInBackground(toTask agentLoop(addr app, endpoint, apiKey, msgsJson))

# ---- Wire up and run ------------------------------------------------------

app.addWidget(chat)
app.addWidget(historyLv)
app.addWidget(jobsLv)
app.addWidget(input)
app.addWidget(status)
# Confirmation popup — last so it draws on top of everything underneath.
app.addWidget(confirmPopup)
app.addWidget(confirmMsg)
app.addWidget(confirmBtn)
app.addWidget(cancelBtn)
app.addWidget(detailPopup)
app.addWidget(detailBody)
app.addWidget(detailCloseBtn)

rebuildRows()
refreshHistoryList()
setStatus("ready")
createThread(quoteThread, quoteLoop, addr app)
app.run(nonBlocking = true)
