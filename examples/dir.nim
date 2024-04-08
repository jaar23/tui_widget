import os, ../src/tui_widget, strutils, marshal, strformat, times

type
  File = object
    name: string
    path: string
    info: FileInfo
    hidden: bool

let fileKind: array[PathComponent, string] = [
  "file", "symlink file", "directory", "symlink directory"
]


let home = os.getHomeDir()
var currDir = home

proc folder(path: string): seq[File] =
  result = newSeq[File]()
  for f in walkDir(path):
    try:
      let filename = f.path.replace(path, "").replace("/", "")
      let fileInfo = getFileInfo(f.path)
      let hidden = if filename.startsWith("."): true else: false
      result.add(File(name: filename, info: fileInfo, hidden: hidden, path: f.path))
    except:
      continue

proc permissionStr(permissions: set[FilePermission]): string =
  result = ""
  if permissions.contains(fpUserRead): result &= "r" else: result &= "-"
  if permissions.contains(fpUserRead): result &= "w" else: result &= "-"
  if permissions.contains(fpUserExec): result &= "x" else: result &= "-"
  result &= "-"
  if permissions.contains(fpGroupRead): result &= "r" else: result &= "-"
  if permissions.contains(fpGroupWrite): result &= "w" else: result &= "-"
  if permissions.contains(fpGroupExec): result &= "x" else: result &= "-"
  result &= "-"
  if permissions.contains(fpOthersRead): result &= "r" else: result &= "-"
  if permissions.contains(fpOthersWrite): result &= "w" else: result &= "-"
  if permissions.contains(fpOthersExec): result &= "x" else: result &= "-"


proc createList(path: string, hide = false, dd = true): seq[ref ListRow] =
  result = newSeq[ref ListRow]()
  for d in folder(path):
    let visible = if d.hidden and hide: false else: true
    var lr = newListRow(0, d.name, $$d, visible=visible)
    result.add(lr)
  if dd:
    result.insert(newListRow(0, "..", ".."), 0)

var rows = createList(home)

var metadataDisplay = newDisplay(31, 1, consoleWidth(), 9, title = "File Info", statusbar=false)

var contentDisplay = newDisplay(31, 10, consoleWidth(), consoleHeight(), title = "Content")

var dirView = newListView(1, 4, 30, consoleHeight(), title=home, rows = rows, bgColor = bgBlue, selectionStyle=Highlight)

var filterCb = newCheckbox(1, 1, 30, 3, label="hide hidden files")


filterCb.onSpace = proc(val: string, checked: bool) =
  var i = 0
  for r in dirView.rows():
    if r.value == "..": continue 
    let val = to[File](r.value)
    if checked and val.hidden:
      r.visible = false
      inc i
    else:
      r.visible = true
  dirView.rows[0].visible = true
  dirView.resetCursor()
  dirView.render()


dirView.onEnter = proc (val: string) =
  if val == "..":
    currDir = parentDir(currDir)
    var crows = if currDir.len > 1: createList(currDir, filterCb.checked) 
      else: createList(currDir, filterCb.checked, false)
    dirView.rows = crows
    dirView.resetCursor()
    dirView.render()
    dirView.title = currDir.split("/")[^1]
    return

  let file = to[File](val)
  let metadata = fmt"""
  File Name   : {file.name}
  Kind        : {fileKind[file.info.kind]}
  Size        : {file.info.size / 1024}kb
  Permission  : {permissionStr(file.info.permissions)}
  Last Access : {file.info.lastAccessTime}
  Last Write  : {file.info.lastWriteTime}
  Created At  : {file.info.creationTime}
  """.dedent()
  metadataDisplay.text = metadata
  if file.info.kind == pcDir:
    var crows = createList(file.path, filterCb.checked)
    dirView.rows = crows
    currDir = file.path
    dirView.title = currDir.split("/")[^1]
    dirView.resetCursor()
    dirView.render()
  else:
    try:
      let content = readFile(file.path)
      contentDisplay.text = content
      contentDisplay.show(resetCursor=true)
    except:
      contentDisplay.hide()


var tuiapp = newTerminalApp(title = "DIR", border=false)

tuiapp.addWidget(filterCb)

tuiapp.addWidget(dirView)

tuiapp.addWidget(metadataDisplay)

tuiapp.addWidget(contentDisplay)

tuiapp.run()
