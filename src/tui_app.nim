import illwill, os, strformat, options
import tui_widget

var tb = newTerminalBuffer(terminalWidth(), terminalHeight())

var inputBox = newInputBox(consoleWidth(), 3, 1, 1, "tui widget", tb=tb)

var display = newDisplay(consoleWidth(), 16, 1, 4, "board", tb=tb) 

var text = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Cras quis accumsan lectus. Duis vitae rhoncus ex, at rhoncus diam. Aenean rutrum non tellus vel finibus. In hac habitasse platea dictumst. Curabitur feugiat, nibh laoreet tincidunt gravida, mi ante sagittis urna, sed ultricies lectus enim et libero. Nam tristique sem tempor lectus dignissim, ac imperdiet risus auctor. Aliquam erat volutpat. In iaculis laoreet ultrices. Curabitur pellentesque eros nec erat mattis, ac semper tortor facilisis.
Morbi quis magna laoreet, lacinia libero sed, lobortis felis. Donec vitae posuere ipsum. Curabitur volutpat vel sem et fringilla. Quisque porttitor, urna nec tincidunt finibus, urna magna finibus ligula, sed cursus libero mauris ut nisi. Nulla erat nisl, blandit non tincidunt eget, bibendum at nisi. Vestibulum imperdiet nulla eu pharetra dictum. Duis vel pretium neque. Nam ac malesuada augue, quis varius purus. Vestibulum sit amet sagittis nibh. Proin in ultricies elit. Donec euismod luctus turpis, a ultrices dui dignissim eget. In mauris dui, sagittis et tortor sed, cursus sodales lectus. Aenean mollis velit nec purus blandit, eu scelerisque velit venenatis. Cras ipsum urna, hendrerit volutpat ullamcorper a, vulputate et neque.
Vestibulum placerat vel elit quis gravida. Integer non ultricies turpis. Etiam vestibulum, nunc a cursus aliquet, leo risus congue dui, vitae mattis est elit sit amet nisi. In eros orci, aliquam nec erat sed, facilisis imperdiet sem. Donec cursus urna porta dui laoreet tincidunt. Cras eu libero leo. Donec vel auctor sapien.
Aliquam egestas velit odio, in tempus sapien bibendum in. Nulla feugiat sodales justo efficitur convallis. Fusce sed eros id quam congue ultrices vitae et orci. Etiam et erat sed odio auctor interdum at vel quam. Vestibulum eget viverra ligula. Etiam sollicitudin tortor vel augue posuere pretium. Sed et tempor neque. Morbi a orci augue. Sed scelerisque urna enim, ac tristique magna congue quis. Proin efficitur eget justo vel consequat. Phasellus maximus leo quis nisi vehicula, quis vulputate nisi interdum. Donec justo sem, posuere ac ultricies non, maximus cursus nisi. Proin suscipit eros eget urna semper gravida. In sit amet ipsum posuere, mollis magna ut, tristique dolor. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas.
Morbi mi arcu, commodo eget elit quis, venenatis semper tortor. Donec nec porta ante. Morbi metus lectus, volutpat in pharetra vehicula, aliquam sed erat. Nunc tempor sagittis pretium. Aliquam vitae elementum enim, et rutrum mi. Morbi eu eros ac lorem dictum sollicitudin. Integer vel libero orci. Vivamus egestas a massa vitae accumsan. Fusce vel neque ac lectus pulvinar feugiat. Sed dapibus tortor et justo condimentum lobortis. Praesent eget odio id purus feugiat vehicula. Proin finibus eros vitae est interdum, non aliquet nisl gravida. Nulla eu blandit sem, in tempor odio.
Vivamus maximus, dolor sed mattis tincidunt, lacus leo malesuada quam, quis mollis sapien risus nec nulla. Vivamus vitae porttitor quam. Cras at facilisis justo. Aliquam tempus vehicula dolor, aliquam consequat magna tempor ac. Morbi ac arcu in massa scelerisque bibendum. Fusce bibendum rutrum lobortis. Mauris fringilla gravida lacus non tincidunt. Ut in sem varius, laoreet magna non, rutrum nunc. Donec in ante ut lacus gravida vulputate.
Suspendisse vehicula pellentesque quam, in ultricies est congue vel. Nam eget tempor lacus. Interdum et malesuada fames ac ante ipsum primis in faucibus. Fusce eu condimentum ante. Mauris venenatis enim elit, id suscipit orci mollis ut. Mauris dignissim fringilla erat, sit amet finibus enim facilisis vel. Donec suscipit tellus vel erat blandit, vulputate mattis est laoreet.
In eu tristique diam. Pellentesque luctus congue quam, eu finibus leo bibendum et. Proin egestas nunc et sollicitudin euismod. Suspendisse pellentesque vehicula urna, non pulvinar lectus hendrerit et. Nulla ultricies tristique lobortis. Etiam turpis orci, accumsan vel volutpat nec, dignissim eget libero. Phasellus in facilisis felis. Pellentesque ultrices arcu sit amet massa sollicitudin porta et sit amet lectus. Phasellus ac fringilla metus. Curabitur sed iaculis ex. Morbi iaculis, quam non viverra volutpat, ex enim vestibulum leo, at volutpat velit mi at purus. Integer id est metus. Ut commodo cursus turpis vel varius.
Nam sit amet mauris lectus. Ut eleifend magna eu nibh accumsan malesuada. Nam nunc dolor, rhoncus at risus in, convallis suscipit justo. Mauris odio erat, ultricies quis hendrerit et, vulputate in ex. Etiam quis vestibulum tellus. Aliquam nec euismod lorem, ac porta ex. Cras in faucibus justo, vel sagittis dui. Nam sit amet tempor ipsum, quis rutrum arcu.
Ut fermentum neque sit amet purus pretium mollis. Sed gravida sollicitudin metus ut tincidunt. Nulla facilisi. Vestibulum vestibulum tellus ut arcu rhoncus, et vestibulum ante ultricies. Aenean ut malesuada est. In interdum felis a convallis lobortis. Aliquam ultricies urna tellus, sit amet tincidunt nibh ultrices at.
Praesent ut consectetur purus. Curabitur placerat, ex nec interdum varius, diam quam sagittis ante, in sagittis mauris lectus in orci. Quisque sapien quam, convallis in condimentum varius, vestibulum ac odio. Morbi vitae scelerisque odio. Sed vestibulum velit et magna vulputate, sit amet volutpat sem posuere. Proin at bibendum nisi, id lacinia nunc. Mauris iaculis lectus eu mi consectetur, non cursus dui pellentesque. Suspendisse pharetra pharetra ultricies. Donec sollicitudin egestas neque, ac bibendum lectus. Donec hendrerit viverra arcu vitae interdum.
Donec eget suscipit nulla. Donec volutpat pellentesque libero, a auctor urna. Nunc auctor sed urna ac aliquam. Mauris at est eleifend, ultricies urna vitae, ullamcorper mi. Sed tincidunt vel lectus non dictum. Pellentesque posuere vehicula malesuada. Etiam ut rutrum mi.
Pellentesque finibus dignissim semper. Curabitur luctus tortor at eleifend accumsan. Pellentesque sapien tellus, vehicula eget nunc iaculis, tristique tempor lectus. Praesent nec libero in neque hendrerit mollis. Etiam et est sit amet augue viverra bibendum. Curabitur a viverra augue, ac suscipit urna. Suspendisse rutrum imperdiet ligula, at ultricies felis semper eget.
Ut feugiat rhoncus feugiat. Integer quis tempus tortor, dictum maximus nulla. Nulla feugiat convallis magna, eu finibus nisi ullamcorper id. Aenean vitae lectus ornare odio fringilla finibus. Proin a felis eu sapien lacinia blandit. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Pellentesque id elit congue, viverra elit vulputate, varius dolor. Quisque sagittis dui quis diam ornare, et molestie metus venenatis. Mauris iaculis. 
"""

display.add(text & text & text & text & text & text & text & text & text)

var checkbox = newCheckbox(20, 22, 1, 20, title="done", label="yes", value="y", tb=tb)

var checkbox2 = newCheckbox(40, 22, 21, 20, title="accept", label="yes", value="y", tb=tb)

var button = newButton(20, 26, 1, 24, label="Confirm", tb=tb)

var table = newTable(45, 34, 1, 28, title="table", tb=tb)
table.loadFromCsv("./leads-1000.csv", withHeader=true, withIndex=true)

var progress = newProgressBar(consoleWidth(), 42, 1, 40 , tb=tb, percent=0.0)
progress.render()


var list = newSeq[ref ListRow]()
var i = 0
const keys = {Key.A..Key.Z}
var listRow = newListRow(0, "rhoncus feugiat. Integer quis tempus tortor, dictum maximus nulla.Nulla feugiat convallis magna,", "ttt", align=Center)
list.add(listRow)
for key in keys:
  var listRow = newListRow(i, $key, $key)
  list.add(listRow)
var listview = newListView(45, 52, 1, 46, rows=list, title="list", tb=tb)

proc exitProc() {.noconv.} =                                                                                                                                                                                                               
  illwillDeinit()                                                                                                                                                                                                                          
  showCursor()
  quit(0)


illwillInit(fullscreen=true)
setControlCHook(exitProc)
hideCursor()


# align components in sequence according to pos Y
proc mainPanel() =
  - inputBox
  - display
  - checkbox
  - checkbox2
  - button
  - table
  - progress
  - listview

# widget implements event needs to be ref
let enterEv: EnterEventProcedure = proc(arg: string) =
  progress.move(5.0)

#let spaceEv: SpaceEventProcedure = proc(arg: string, checked: bool) =
  #echo &"\n\n\n\n\n\n\n\n\n\n\n{arg} {checked}"


#inputBox.onEnter(some(enterEv))
#checkbox.onSpace(some(spaceEv))
#checkbox2.onSpace(some(spaceEv))
button.onEnter(some(enterEv))

var currFocus = 0
var components: seq[ref BaseWidget] = @[]

components.add(inputBox)
components.add(display)
components.add(checkbox)
components.add(checkbox2)
components.add(button)
components.add(table)
components.add(listview)

while true:
  mainPanel()
  var key = getKey()
  case key
  of Key.Tab, None:
    if currFocus > components.len - 1:
      currFocus = 0
    components[currFocus].onControl()
    currFocus = currFocus + 1
  else: discard

  tb.display()

  sleep(20)
  

