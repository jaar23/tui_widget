import ../src/tui_widget
import httpclient, net, os, std/tasks

# tui widget currently is running in synchronous
# when making http request, the screen will be freezed

var input = newInputBox(1, 1, consoleWidth(), 3, title="url")

var display = newDisplay(1, 4, consoleWidth(), consoleHeight() - 20, title="content")

let displayEv = proc(dp: ref Display, args: varargs[string]) =
  let f = open("background.txt", fmAppend)
  f.write("last part " & $args)
  dp.text = args[0]

display.on("display", displayEv)

let httpCall = proc (wg: ptr BaseWidget, url: string) {.gcsafe.} =
  var client = newHttpClient(sslContext=newContext(verifyMode=CVerifyPeerUseEnvVars))
  defer:
    client.close()
  try:
    let content = client.getContent(url)
    sleep(4000)
    notifyWidget(wg, "display", content)
  except:
    echo getCurrentExceptionMsg()


let asyncEnterEv = proc (ib: ref InputBox, args: varargs[string]) =
  let url = ib.value
  ib.value = ""
  
  let httpCallTask = toTask httpCall(addr display[], url)
  runInBackground(httpCallTask)
  #display.onControl()

input.onEnter = asyncEnterEv

var app = newTerminalApp(title="curl", border=false)

app.addWidget(input)

app.addWidget(display)

app.run()

