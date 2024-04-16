import ../src/tui_widget
import httpclient, net, os

# tui widget currently is running in synchronous
# when making http request, the screen will be freezed

proc httpCall(url: string): (bool, string) =
  var client = newHttpClient(sslContext=newContext(verifyMode=CVerifyPeerUseEnvVars))
  defer:
    client.close()
  try:
    let content = client.getContent(url)
    return (true, content)
  except:
    return (false, getCurrentExceptionMsg())


var input = newInputBox(1, 1, consoleWidth(), 3, title="url")

var display = newDisplay(1, 4, consoleWidth(), consoleHeight(), title="content")

let asyncEnterEv = proc (ib: ref InputBox, args: varargs[string]) =
  let url = ib.value
  var curlResult: (bool, string) = httpCall(url)
  ib.value = ""
  let (success, content) = curlResult
  if not success:
    display.text = "failed to curl this url"
  else:
    display.text = content

input.onEnter = asyncEnterEv

var app = newTerminalApp(title="curl", border=false)

app.addWidget(input)

app.addWidget(display)

app.run()

