import ../src/tui_widget
import httpclient, net, os, std/tasks

# tui widget can run in non blocking mode by setting nonBlocking=true in run proc
# when making http request, the screen does not freeze and render once content
# is ready.

var input = newInputBox(1, 1, consoleWidth(), 3, title="url")

var display = newDisplay(1, 5, consoleWidth(), consoleHeight(), id="display", title="content")

var app = newTerminalApp(title="curl", border=false)

display.on("display", proc(dp: Display, args: varargs[string]) =
  dp.text = args[0]
)


let httpCall = proc (appPtr: ptr TerminalApp, id: string, url: string) {.gcsafe.} =
  var client = newHttpClient(sslContext=newContext(verifyMode=CVerifyPeerUseEnvVars))
  defer:
    client.close()
  try:
    let content = client.getContent(url)
    sleep(2000)

    # notify main thread when task is done
    notify(appPtr, id, "display", content)
  except:
    let err = getCurrentExceptionMsg()
    notify(appPtr, id, "display", err)


let asyncEnterEv = proc (ib: InputBox, args: varargs[string]) =
  try:
    let url = ib.value
    ib.value = ""
    
    # create a task and passing it to the background thread
    let httpCallTask = toTask httpCall(addr app, display.id, url)

    # running the task in background
    runInBackground(httpCallTask)
  except:
    echo "task exception"
    echo getCurrentExceptionMsg()


input.on("enter", asyncEnterEv)

app.addWidget(input)

app.addWidget(display)

app.run(nonBlocking=true)
