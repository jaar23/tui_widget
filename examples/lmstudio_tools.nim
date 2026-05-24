## Shared tool layer for the lmstudio_chat* demo agents.
##
## Exposes two things:
##   - `toolSpecs*`  — JSON tool specs sent to the LLM
##   - `execTool*`   — dispatcher that runs the matching exec proc
##
## Both `examples/lmstudio_chat.nim` and `examples/lmstudio_chat_listview.nim`
## import this module so the agent's capability surface stays in sync. New
## tools added here are immediately available to both demos.
##
## Sandboxing (per the plan):
##   - File ops (read_file, list_directory, append_file, write_file) are
##     restricted to /tmp via `resolveSandboxPath`.
##   - fetch_url rejects non-http(s) schemes and any host resolving into
##     a loopback / private / link-local IP range.
##   - run_command is intentionally unrestricted — the agent already has
##     shell via that tool; tightening it everywhere else is theatre.

import json, os, osproc, strutils, uri, httpclient, net, algorithm,
       nativesockets, sets, unicode, locks, streams, times
import ../src/widget/base_wg  # getClipboardText* / setClipboardText*

# ---- Shared HTML stripper (used by web_search) -----------------------------

proc stripHtml(s: string): string =
  result = newStringOfCap(s.len)
  var inTag = false
  for c in s:
    if c == '<': inTag = true
    elif c == '>': inTag = false
    elif not inTag: result.add(c)
  result = result.multiReplace([
    ("&amp;","&"), ("&lt;","<"), ("&gt;",">"), ("&quot;","\""),
    ("&#x27;","'"), ("&#39;","'"), ("&#x2F;","/"), ("&nbsp;"," ")
  ]).strip()

# ---- File-system sandbox helper -------------------------------------------

const SandboxRoot = "/tmp"

proc resolveSandboxPath(s: string): (bool, string) =
  ## Normalises `s` to an absolute path inside SandboxRoot.
  ##   - "foo"          → "/tmp/foo"
  ##   - "/tmp/foo"     → "/tmp/foo"
  ##   - "/tmp/sub/foo" → "/tmp/sub/foo"
  ##   - "/etc/passwd"  → rejected
  ##   - "../etc/foo"   → rejected (after normalisation)
  ##   - "/tmp/../etc"  → rejected (after normalisation)
  if s.len == 0:
    return (false, "empty path")
  let raw = if s.startsWith("/"): s else: SandboxRoot / s
  let norm = absolutePath(raw).normalizedPath
  if norm != SandboxRoot and not norm.startsWith(SandboxRoot & "/"):
    return (false, "path outside sandbox (/tmp): " & norm)
  return (true, norm)

# ---- SSRF guard for fetch_url ---------------------------------------------

proc isPrivateIp(ip: IpAddress): bool =
  ## Loopback / private / link-local. Conservative.
  case ip.family
  of IpAddressFamily.IPv4:
    let b = ip.address_v4
    if b[0] == 127: return true                              # 127.0.0.0/8
    if b[0] == 10: return true                               # 10.0.0.0/8
    if b[0] == 169 and b[1] == 254: return true              # 169.254.0.0/16
    if b[0] == 172 and (b[1] >= 16 and b[1] <= 31): return true  # 172.16/12
    if b[0] == 192 and b[1] == 168: return true              # 192.168.0.0/16
    if b[0] == 0: return true                                # 0.0.0.0/8
    return false
  of IpAddressFamily.IPv6:
    let b = ip.address_v6
    # ::1
    var allZero = true
    for i in 0 ..< 15:
      if b[i] != 0: allZero = false; break
    if allZero and b[15] == 1: return true
    # fe80::/10  link-local
    if b[0] == 0xFE and (b[1] and 0xC0'u8) == 0x80'u8: return true
    # fc00::/7   unique local
    if (b[0] and 0xFE'u8) == 0xFC'u8: return true
    return false

proc hostIsSafe(host: string): (bool, string) =
  ## Resolve `host`. Return (false, reason) if it's literal localhost,
  ## 0.0.0.0, or resolves to any private IP.
  let lower = host.toLowerAscii()
  if lower == "localhost" or lower == "ip6-localhost" or lower == "0.0.0.0":
    return (false, "loopback/unspecified host rejected: " & host)
  # Literal IP?
  try:
    let ip = parseIpAddress(host)
    if isPrivateIp(ip):
      return (false, "private/loopback address rejected: " & host)
    return (true, "")
  except ValueError: discard
  # Resolve hostname.
  try:
    let info = getHostByName(host)
    for s in info.addrList:
      try:
        let ip = parseIpAddress(s)
        if isPrivateIp(ip):
          return (false, "host resolves to private address: " & host & " → " & s)
      except ValueError: discard
    return (true, "")
  except OSError as e:
    return (false, "dns lookup failed: " & e.msg)

# ---- Tool exec procs ------------------------------------------------------

proc execRunCommand(args: JsonNode): string =
  try:
    let cmd = args["command"].getStr()
    let (output, code) = execCmdEx(cmd)
    result = "$ " & cmd & "\nexit=" & $code & "\n" & output
  except CatchableError:
    result = "run_command error: " & getCurrentExceptionMsg()

proc execWebSearch(args: JsonNode): string =
  ## Scrape Brave Search HTML — no API key, no DuckDuckGo. Brave's result
  ## page is stable: each hit is an <a href="URL"> wrapping a
  ## <div class="...search-snippet-title...">TITLE</div>, followed by a
  ## <div class="generic-snippet">…snippet…</div> sibling. We walk for the
  ## title marker and pull the surrounding href/title/snippet around it.
  try:
    let q = args["query"].getStr()
    var client = newHttpClient(
      timeout = 10_000,
      userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " &
                  "(KHTML, like Gecko) Chrome/120.0 Safari/537.36",
      sslContext = newContext(verifyMode = CVerifyPeerUseEnvVars))
    client.headers = newHttpHeaders({
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9," &
                "image/avif,image/webp,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.5",
      "Cache-Control": "no-cache"})
    defer: client.close()
    let pageUrl = "https://search.brave.com/search?q=" & encodeUrl(q) &
                  "&source=web"
    let html = client.getContent(pageUrl)
    var lines = @["query: " & q]
    var n = 0
    var i = 0
    # Use a marker with a leading space so we match the *class attribute*
    # `class="title search-snippet-title ..."` but not the CSS rule
    # `.search-snippet-title{...}` that also appears in inline <style>.
    const titleMarker = " search-snippet-title"
    while n < 5:
      let titleMark = html.find(titleMarker, i)
      if titleMark < 0: break
      # Walk forward to the '>' that ends the title's <div ...> tag, then
      # read until the next '</div>'.
      let titleOpenGT = html.find('>', titleMark)
      if titleOpenGT < 0: break
      let titleCloseDiv = html.find("</div>", titleOpenGT)
      if titleCloseDiv < 0: break
      let title = stripHtml(html[titleOpenGT + 1 ..< titleCloseDiv])
      # Walk backward from the title marker to the enclosing
      # <a ... href="HTTP..."> opening tag (Brave wraps the whole hit in
      # one <a>). The nearest preceding `href="http` belongs to that <a>.
      var hitUrl = ""
      let hrefIdx = html.rfind("href=\"http", 0, titleMark)
      if hrefIdx >= 0:
        let urlStart = hrefIdx + 6                # past `href="`
        let urlEnd = html.find('"', urlStart)
        if urlEnd > urlStart: hitUrl = html[urlStart ..< urlEnd]
      # Snippet: the next `generic-snippet` div after the title.
      var snippet = ""
      let snipMark = html.find("generic-snippet", titleCloseDiv)
      let nextTitle = html.find(titleMarker, titleCloseDiv + 6)
      let snipBound = if nextTitle > 0: nextTitle else: html.len
      if snipMark > 0 and snipMark < snipBound:
        # Walk into the `content` child of the snippet wrapper — that's
        # where the visible text lives. Falls back to the wrapper if the
        # child marker is missing.
        var snipBodyStart = html.find("class=\"content", snipMark)
        if snipBodyStart < 0 or snipBodyStart > snipBound:
          snipBodyStart = snipMark
        let snipOpenGT = html.find('>', snipBodyStart)
        let snipCloseDiv = html.find("</div>", snipOpenGT)
        if snipOpenGT > 0 and snipCloseDiv > snipOpenGT:
          snippet = stripHtml(html[snipOpenGT + 1 ..< snipCloseDiv])
      if title.len > 0:
        inc n
        lines.add($n & ". " & title)
        if hitUrl.len > 0: lines.add("   " & hitUrl)
        if snippet.len > 0:
          # Truncate by *runes* not bytes — slicing at a byte boundary can
          # cut a multi-byte UTF-8 codepoint in half and produce the U+FFFD
          # replacement character (the "random char" the user sees).
          let runes = snippet.runeLen
          let s = if runes > 320: snippet.runeSubStr(0, 320) & "…" else: snippet
          lines.add("   " & s)
      i = titleCloseDiv + 6
    if n == 0: lines.add("(no results)")
    result = lines.join("\n")
  except CatchableError:
    result = "web_search error: " & getCurrentExceptionMsg()

proc execWriteFile(args: JsonNode): string =
  try:
    let filename = args["filename"].getStr().extractFilename()
    let content  = args["content"].getStr()
    if filename.len == 0: return "write_file error: empty filename"
    let (ok, p) = resolveSandboxPath(filename)
    if not ok: return "write_file error: " & p
    writeFile(p, content)
    result = "wrote " & $content.len & " bytes to " & p
  except CatchableError:
    result = "write_file error: " & getCurrentExceptionMsg()

proc execReadFile(args: JsonNode): string =
  try:
    let p0 = args{"path"}.getStr("")
    if p0.len == 0: return "read_file error: missing 'path'"
    let (ok, p) = resolveSandboxPath(p0)
    if not ok: return "read_file error: " & p
    if not fileExists(p): return "read_file error: not found: " & p
    let content = readFile(p)
    let offset = max(0, args{"offset"}.getInt(0))
    let askLimit = args{"limit"}.getInt(8192)
    let limit = clamp(askLimit, 1, 32768)
    if offset >= content.len:
      return "read " & p & " (offset " & $offset & " ≥ size " & $content.len & ")"
    let stop = min(offset + limit, content.len)
    let body = content[offset ..< stop]
    let truncated = stop < content.len
    result = "read " & p & " bytes=" & $body.len & "/" & $content.len &
             (if truncated: " (truncated; ask with offset=" & $stop & " for more)" else: "") &
             "\n" & body
  except CatchableError:
    result = "read_file error: " & getCurrentExceptionMsg()

proc execListDirectory(args: JsonNode): string =
  try:
    let p0 = args{"path"}.getStr(SandboxRoot)
    let (ok, p) = resolveSandboxPath(p0)
    if not ok: return "list_directory error: " & p
    if not dirExists(p): return "list_directory error: not a directory: " & p
    var entries: seq[(string, string)] = @[]   # (sortKey, line)
    var count = 0
    for kind, sub in walkDir(p):
      let name = sub.extractFilename()
      let line =
        case kind
        of pcFile, pcLinkToFile:
          try: "f  " & $getFileSize(sub) & "  " & name
          except OSError: "f  ?  " & name
        of pcDir, pcLinkToDir:
          "d  -  " & name & "/"
      entries.add((name, line))
      inc count
      if count >= 200: break
    entries.sort(proc(a, b: (string, string)): int = cmpIgnoreCase(a[0], b[0]))
    var lines = @[p & "  (" & $entries.len & " entries" &
                  (if count >= 200: ", first 200 only" else: "") & ")"]
    for (_, ln) in entries: lines.add(ln)
    result = lines.join("\n")
  except CatchableError:
    result = "list_directory error: " & getCurrentExceptionMsg()

proc execAppendFile(args: JsonNode): string =
  try:
    let filename = args["filename"].getStr().extractFilename()
    let content  = args["content"].getStr()
    if filename.len == 0: return "append_file error: empty filename"
    let (ok, p) = resolveSandboxPath(filename)
    if not ok: return "append_file error: " & p
    let f = open(p, fmAppend)
    f.write(content)
    f.close()
    let total = if fileExists(p): getFileSize(p).int else: -1
    result = "appended " & $content.len & " bytes to " & p &
             " (now " & $total & " bytes)"
  except CatchableError:
    result = "append_file error: " & getCurrentExceptionMsg()

proc execFetchUrl(args: JsonNode): string =
  try:
    let raw = args["url"].getStr().strip()
    if raw.len == 0: return "fetch_url error: empty url"
    var u: Uri
    try: u = parseUri(raw)
    except CatchableError: return "fetch_url error: invalid url"
    let scheme = u.scheme.toLowerAscii()
    if scheme != "http" and scheme != "https":
      return "fetch_url error: only http/https allowed (got " & scheme & ")"
    let (safe, why) = hostIsSafe(u.hostname)
    if not safe: return "fetch_url error: " & why
    var client = newHttpClient(
      timeout = 10_000,
      userAgent = "lmstudio-chat-agent/1.0",
      sslContext = newContext(verifyMode = CVerifyPeerUseEnvVars))
    defer: client.close()
    let resp = client.get(raw)
    let body = resp.body
    const Cap = 16384
    let truncated = body.len > Cap
    let shown = if truncated: body[0 ..< Cap] else: body
    result = "GET " & raw & "\nstatus=" & $resp.code.int & " bytes=" & $body.len &
             (if truncated: " (truncated to 16K)" else: "") & "\n" & shown
  except CatchableError:
    result = "fetch_url error: " & getCurrentExceptionMsg()

proc execReadClipboard(args: JsonNode): string =
  try:
    let s = getClipboardText()
    if s.len == 0: result = "clipboard is empty"
    else: result = "clipboard (" & $s.len & " bytes):\n" & s
  except CatchableError:
    result = "read_clipboard error: " & getCurrentExceptionMsg()

proc execWriteClipboard(args: JsonNode): string =
  try:
    let text = args["text"].getStr()
    setClipboardText(text)
    result = "wrote " & $text.len & " bytes to clipboard"
  except CatchableError:
    result = "write_clipboard error: " & getCurrentExceptionMsg()

# ---- Background jobs ------------------------------------------------------
#
# `run_command` is fine for fast commands but freezes the agent worker
# thread when the command takes minutes. The job subsystem decouples that:
# `start_job` returns immediately with a job id, the process runs on its
# own thread, and the agent can poll with `get_job` / `list_jobs` or stop
# it with `kill_job`. A scheduler thread enforces a wall-time cap and
# evicts long-completed jobs from the registry.

const
  JobTimeoutSec*     = 300   # hard kill after 5 min
  JobRetentionSec*   = 600   # drop finished jobs after 10 min
  JobOutputCap*      = 32 * 1024
  SchedulerTickMs    = 5_000

type
  JobStatus* = enum
    jsRunning, jsDone, jsFailed, jsKilled, jsTimeout
  JobObj* = object
    id*:         int
    cmd*:        string
    pid*:        int
    started*:    int64       # epoch seconds
    finished*:   int64
    status*:     JobStatus
    exitCode*:   int
    output*:     string
    process:     Process
  Job* = ref JobObj

var jobsLock: Lock
jobsLock.initLock()
var jobs*: seq[Job] = @[]
var nextJobId = 1
var schedulerStarted = false
var schedulerThread: Thread[void]
var jobThreads: seq[ref Thread[Job]] = @[]  # keep handles alive

proc statusLabel*(s: JobStatus): string =
  case s
  of jsRunning: "running"
  of jsDone:    "done"
  of jsFailed:  "failed"
  of jsKilled:  "killed"
  of jsTimeout: "timeout"

proc snapshotJobs*(): seq[Job] =
  ## Return a shallow copy of the current registry — safe to iterate from
  ## the UI thread without holding the lock for the whole render.
  withLock jobsLock:
    result = @jobs

proc findJob(id: int): Job =
  for j in jobs:
    if j.id == id: return j
  nil

proc runJobThread(j: Job) {.thread, gcsafe.} =
  ## Worker thread for one job. Captures output and exit code, then marks
  ## the job done/failed. Exceptions are converted into jsFailed with the
  ## exception message in the output buffer.
  try:
    let p = startProcess("/bin/sh", args = ["-c", j.cmd],
                         options = {poUsePath, poStdErrToStdOut})
    {.cast(gcsafe).}:
      withLock jobsLock:
        j.process = p
        j.pid     = p.processID
    let s = p.outputStream
    let raw = s.readAll()      # blocks until the process closes stdout
    let ec = p.waitForExit()
    {.cast(gcsafe).}:
      withLock jobsLock:
        var capped = raw
        if capped.len > JobOutputCap:
          capped = capped[0 ..< JobOutputCap] & "\n…[truncated]"
        j.output    = capped
        j.exitCode  = ec
        j.finished  = epochTime().int64
        if j.status == jsRunning:
          j.status = if ec == 0: jsDone else: jsFailed
    p.close()
  except CatchableError:
    let msg = getCurrentExceptionMsg()
    {.cast(gcsafe).}:
      withLock jobsLock:
        j.status   = jsFailed
        j.output   = "[runJobThread error: " & msg & "]"
        j.finished = epochTime().int64

proc schedulerLoop() {.thread, gcsafe.} =
  ## Tick every few seconds. Hard-kill any running job past JobTimeoutSec
  ## and evict finished jobs that have been around past JobRetentionSec.
  while true:
    sleep(SchedulerTickMs)
    let nowSec = epochTime().int64
    {.cast(gcsafe).}:
      withLock jobsLock:
        # Kill timed-out runners
        for j in jobs:
          if j.status == jsRunning and (nowSec - j.started) > JobTimeoutSec:
            try: j.process.kill()
            except CatchableError: discard
            j.status   = jsTimeout
            j.finished = nowSec
        # Drop expired completed jobs
        var i = 0
        while i < jobs.len:
          let j = jobs[i]
          if j.status != jsRunning and
             (nowSec - j.finished) > JobRetentionSec:
            jobs.del(i)
          else:
            inc i

proc ensureScheduler*() =
  ## Lazy-start the scheduler thread the first time a job is created.
  if not schedulerStarted:
    schedulerStarted = true
    createThread(schedulerThread, schedulerLoop)

proc execStartJob(args: JsonNode): string =
  try:
    let cmd = args["cmd"].getStr().strip()
    if cmd.len == 0: return "start_job error: empty cmd"
    let j = Job(cmd: cmd, started: epochTime().int64, status: jsRunning)
    {.cast(gcsafe).}:
      withLock jobsLock:
        j.id = nextJobId
        inc nextJobId
        jobs.add(j)
    ensureScheduler()
    var t = new(Thread[Job])
    createThread(t[], runJobThread, j)
    jobThreads.add(t)  # keep the Thread handle alive for the GC
    result = "started job #" & $j.id & "  (" & cmd & ")"
  except CatchableError:
    result = "start_job error: " & getCurrentExceptionMsg()

proc execListJobs(args: JsonNode): string =
  let snap = snapshotJobs()
  if snap.len == 0: return "(no jobs)"
  var lines = newSeq[string]()
  let nowSec = epochTime().int64
  for j in snap:
    let endT = if j.status == jsRunning: nowSec else: j.finished
    let runtime = max(0, endT - j.started)
    let preview = if j.cmd.len > 50: j.cmd[0 ..< 50] & "…" else: j.cmd
    lines.add("#" & $j.id & "  " & statusLabel(j.status) &
              "  " & $runtime & "s  " & preview)
  result = lines.join("\n")

proc execGetJob(args: JsonNode): string =
  let id = args["id"].getInt()
  let snap = snapshotJobs()
  for j in snap:
    if j.id == id:
      let nowSec = epochTime().int64
      let endT = if j.status == jsRunning: nowSec else: j.finished
      let runtime = max(0, endT - j.started)
      return "#" & $j.id & "  " & statusLabel(j.status) &
             "  exit=" & $j.exitCode & "  runtime=" & $runtime & "s" &
             "\ncmd: " & j.cmd &
             "\n--- output ---\n" & j.output
  result = "job #" & $id & " not found"

proc execKillJob(args: JsonNode): string =
  let id = args["id"].getInt()
  {.cast(gcsafe).}:
    withLock jobsLock:
      let j = findJob(id)
      if j == nil: return "job #" & $id & " not found"
      if j.status != jsRunning:
        return "job #" & $id & " is not running (status: " &
               statusLabel(j.status) & ")"
      try: j.process.kill()
      except CatchableError: discard
      j.status   = jsKilled
      j.finished = epochTime().int64
      return "killed job #" & $id

proc removeJob*(id: int): bool =
  ## UI helper — drop a finished job from the registry. Returns true if
  ## removed. Refuses to drop running jobs (use kill_job first).
  {.cast(gcsafe).}:
    withLock jobsLock:
      var i = 0
      while i < jobs.len:
        if jobs[i].id == id:
          if jobs[i].status == jsRunning: return false
          jobs.del(i)
          return true
        inc i
  result = false

# ---- Tool specs sent to the LLM -------------------------------------------

let toolSpecs* = %*[
  {"type": "function",
   "function": {
     "name": "run_command",
     "description": "Run a SHORT shell command (well under 30 seconds) and return its stdout+stderr. Blocks until the process exits — do NOT use this for servers, watchers, dev/build daemons, downloads, npm/pip installs, anything that runs longer than a few seconds, or anything that doesn't terminate on its own. For those, use start_job instead.",
     "parameters": {"type": "object",
                    "properties": {"command": {"type": "string"}},
                    "required": ["command"]}}},
  {"type": "function",
   "function": {
     "name": "web_search",
     "description": "Search the web for up-to-date information. Use this whenever the user asks about something that may have changed since training: current stock prices, weather, exchange rates, news, recent events, version numbers, sports scores, etc. Returns the top 5 results with title, URL and a text snippet — the snippet often already contains the direct answer.",
     "parameters": {"type": "object",
                    "properties": {"query": {"type": "string"}},
                    "required": ["query"]}}},
  {"type": "function",
   "function": {
     "name": "write_file",
     "description": "Write text to a file under /tmp (path components in filename are stripped).",
     "parameters": {"type": "object",
                    "properties": {"filename": {"type": "string"},
                                   "content":  {"type": "string"}},
                    "required": ["filename", "content"]}}},
  {"type": "function",
   "function": {
     "name": "read_file",
     "description": "Read up to 8K of a text file under /tmp. Use offset+limit to page through larger files.",
     "parameters": {"type": "object",
                    "properties": {"path":   {"type": "string"},
                                   "offset": {"type": "integer", "default": 0},
                                   "limit":  {"type": "integer", "default": 8192}},
                    "required": ["path"]}}},
  {"type": "function",
   "function": {
     "name": "list_directory",
     "description": "List entries in a directory under /tmp. Returns one line per entry (f|d  size  name).",
     "parameters": {"type": "object",
                    "properties": {"path": {"type": "string", "default": "/tmp"}},
                    "required": []}}},
  {"type": "function",
   "function": {
     "name": "append_file",
     "description": "Append text to a file under /tmp (the file is created if it doesn't exist).",
     "parameters": {"type": "object",
                    "properties": {"filename": {"type": "string"},
                                   "content":  {"type": "string"}},
                    "required": ["filename", "content"]}}},
  {"type": "function",
   "function": {
     "name": "fetch_url",
     "description": "HTTP GET a public URL (http/https only). Body is capped at 16K; private/loopback hosts are rejected.",
     "parameters": {"type": "object",
                    "properties": {"url": {"type": "string"}},
                    "required": ["url"]}}},
  {"type": "function",
   "function": {
     "name": "read_clipboard",
     "description": "Return the current OS clipboard contents.",
     "parameters": {"type": "object", "properties": {}, "required": []}}},
  {"type": "function",
   "function": {
     "name": "write_clipboard",
     "description": "Copy text into the OS clipboard.",
     "parameters": {"type": "object",
                    "properties": {"text": {"type": "string"}},
                    "required": ["text"]}}},
  {"type": "function",
   "function": {
     "name": "start_job",
     "description": "Start a shell command as a background job and return its job id immediately so you can keep working while it runs. ALWAYS use this (not run_command) for: node/npm/python/go servers, dev servers, file watchers, builds (`make`, `nim c`, `cargo build`), installs (`npm install`, `pip install`), long downloads/uploads, or anything that may take more than a few seconds. The user can see running jobs in the side panel. Hard-killed after 5 minutes if still running; query progress with list_jobs/get_job, terminate with kill_job.",
     "parameters": {"type": "object",
                    "properties": {"cmd": {"type": "string"}},
                    "required": ["cmd"]}}},
  {"type": "function",
   "function": {
     "name": "list_jobs",
     "description": "List all current background jobs with id, status, runtime in seconds, and a command preview.",
     "parameters": {"type": "object", "properties": {}, "required": []}}},
  {"type": "function",
   "function": {
     "name": "get_job",
     "description": "Get the full record for a background job by id: status, exit code, runtime, command, and captured stdout+stderr (capped at 32K).",
     "parameters": {"type": "object",
                    "properties": {"id": {"type": "integer"}},
                    "required": ["id"]}}},
  {"type": "function",
   "function": {
     "name": "kill_job",
     "description": "Terminate a running background job by id. No-op (with a message) if the job is already finished.",
     "parameters": {"type": "object",
                    "properties": {"id": {"type": "integer"}},
                    "required": ["id"]}}}
]

# ---- Dispatcher -----------------------------------------------------------

proc execTool*(name: string, args: JsonNode): string {.gcsafe.} =
  ## Route a tool_call from the LLM to its exec proc. Unknown tool names
  ## return a polite error rather than raising — keeps the agent loop
  ## resilient if the model hallucinates a tool we don't ship.
  {.cast(gcsafe).}:
    case name
    of "run_command":     execRunCommand(args)
    of "web_search":      execWebSearch(args)
    of "write_file":      execWriteFile(args)
    of "read_file":       execReadFile(args)
    of "list_directory":  execListDirectory(args)
    of "append_file":     execAppendFile(args)
    of "fetch_url":       execFetchUrl(args)
    of "read_clipboard":  execReadClipboard(args)
    of "write_clipboard": execWriteClipboard(args)
    of "start_job":       execStartJob(args)
    of "list_jobs":       execListJobs(args)
    of "get_job":         execGetJob(args)
    of "kill_job":        execKillJob(args)
    else: "unknown tool: " & name


# ---- Confirmation gating --------------------------------------------------
#
# `isDangerous` returns true for tools that should never run silently. The
# chat UI hooks this and pops a confirm/cancel dialog before forwarding to
# `execTool`. The list deliberately covers anything that mutates disk,
# spawns a process, or kills one — even when the user themselves typed the
# command. `describeTool` formats the one-line summary shown in the dialog.

const DangerousTools* = [
  "write_file", "append_file", "run_command", "start_job", "kill_job"
]

# Pattern markers that suggest extra caution within run_command/start_job
# args. Used only to upgrade the dialog wording from "Run" to "DANGER".
const DestructiveCmds* = [
  "rm ", "rm\t", "rmdir ", "del ", "dd ",
  "mkfs", "format ", "shred ", "sudo ", "doas ", "su -",
  "chmod ", "chown ", "mv ", " > ", " >> "
]

proc isDangerous*(name: string): bool =
  ## True if the tool name is in the always-prompt list.
  for d in DangerousTools:
    if name == d: return true

proc looksDestructive*(cmd: string): bool =
  ## Heuristic — does the shell command contain one of the high-risk
  ## patterns (`rm`, `dd`, `sudo`, redirection-overwrite, etc.)?
  let s = " " & cmd.toLowerAscii() & " "
  for m in DestructiveCmds:
    if m in s: return true

proc describeTool*(name: string, args: JsonNode): string =
  ## One-line human-readable summary of what the tool is about to do.
  ## Used in the confirmation dialog message.
  case name
  of "run_command", "start_job":
    let cmd = args{"cmd"}.getStr("?")
    result = name & ":\n  " & cmd
    if looksDestructive(cmd):
      result &= "\n\n⚠ command contains a destructive pattern"
  of "write_file":
    let fn = args{"filename"}.getStr("?")
    let content = args{"content"}.getStr("")
    result = "write_file:\n  " & fn & "  (" & $content.len & " bytes)"
  of "append_file":
    let fn = args{"path"}.getStr("?")
    let content = args{"content"}.getStr("")
    result = "append_file:\n  " & fn & "  (+" & $content.len & " bytes)"
  of "kill_job":
    result = "kill_job:\n  job #" & $args{"id"}.getInt()
  else:
    result = name & ":\n  " & $args


# ---- Filtering -----------------------------------------------------------

proc allToolNames*(): HashSet[string] =
  ## Set of every tool name in `toolSpecs`. Handy for initialising the
  ## "all enabled" state in a UI.
  for spec in toolSpecs:
    result.incl(spec["function"]["name"].getStr())

proc filteredToolSpecs*(enabled: HashSet[string]): JsonNode =
  ## Subset of `toolSpecs` whose function name is in `enabled`. The
  ## dashboard demo uses this so the user can toggle individual tools
  ## off at runtime via checkboxes without rebuilding spec JSON by hand.
  result = newJArray()
  for spec in toolSpecs:
    if spec["function"]["name"].getStr() in enabled:
      result.add(spec)
