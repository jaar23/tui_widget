import ../src/tui_widget
import httpclient, net, os, std/tasks, times

# tui widget currently is running in synchronous
# when making http request, the screen will be freezed

#var input = newInputBox(1, 1, consoleWidth(), 3, title="url")
var input = newTextArea(1, 1, consoleWidth(), 6, title="url", statusbar=true)

var display = newDisplay(1, 7, consoleWidth(), consoleHeight() - 20, id="display", title="content")

var app = newTerminalApp(title="curl", border=false)

let displayEv = proc(dp: ref Display, args: varargs[string]) =
  # let f = open("background.txt", fmAppend)
  # f.write($now().toTime() & "last part " & $args)
  dp.text = args[0]
  dp.render()


display.on("display", displayEv)

let httpCall = proc (appPtr: ptr TerminalApp, dpPtr: ptr Display, id: string, url: string) {.gcsafe.} =
  var client = newHttpClient(sslContext=newContext(verifyMode=CVerifyPeerUseEnvVars))
  defer:
    client.close()
  try:
    let content = client.getContent(url)
    sleep(2000)
    notify(appPtr, dpPtr, id, "display", content)
  except:
    echo getCurrentExceptionMsg()


# let asyncEnterEv = proc (ib: ref InputBox, args: varargs[string]) =
#   let url = ib.value
#   ib.value = ""
#   
#   let httpCallTask = toTask httpCall(addr app, addr display[], display.id, url)
#   runInBackground(httpCallTask)
#

let asyncEnterEv = proc (t: ref TextArea, args: varargs[string]) =
  let url = t.value
  t.value = ""
  
  let httpCallTask = toTask httpCall(addr app, addr display[], display.id, url)
  runInBackground(httpCallTask)


input.on(Key.CtrlR, asyncEnterEv)

app.addWidget(input)

app.addWidget(display)

app.go()
