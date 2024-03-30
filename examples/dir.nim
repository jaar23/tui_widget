import os, ../src/tui_widget, strutils, marshal, strformat, times,  std/paths

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
      let filename = f.path.replace(path, "")
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


proc createList(path: string): seq[ref ListRow] =
  result = newSeq[ref ListRow]()
  result.add(newListRow(0, "..", ".."))
  for d in folder(path):
    var lr = newListRow(0, d.name, $$d)
    result.add(lr)

var rows = createList(home)

var metadataDisplay = newDisplay(31, 1, 100, 10, title = "File Info", statusbar=false)

var contentDisplay = newDisplay(31, 11, 100, 30, title = "Content")

var dirView = newListView(1, 4, 30, 30, title=home, rows = rows, bgColor = bgBlue, selectionStyle=HighlightArrow)

var filterCb = newCheckbox(1, 1, 30, 3, label="show hidden")


filterCb.onSpace = proc(val: string, checked: bool) =
    for r in dirView.rows():
      if checked and r.text.startsWith("."):
          r.visible = false
      else:
        r.visible = true
    dirView.render()


dirView.onEnter = proc (val: string) =
  if val == "..":
    currDir = parentDir(currDir)
    var crows = createList(currDir)
    dirView.rows = crows
    dirView.resetCursor()
    dirView.render()
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
    var crows = createList(file.path)
    dirView.rows = crows
    currDir = file.path
    dirView.resetCursor()
    dirView.render()
  else:
    try:
      let content = readFile(file.path)
      contentDisplay.text = content
      contentDisplay.show()
    except:
      contentDisplay.hide()


var tuiapp = newTerminalApp(title = "dir")

tuiapp.addWidget(filterCb)

tuiapp.addWidget(dirView)

tuiapp.addWidget(metadataDisplay)

tuiapp.addWidget(contentDisplay)

tuiapp.run()
