import os, ../src/tui_widget, strutils, marshal, strformat

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


var rows = newSeq[ref ListRow]()
for d in folder(home):
  var lr = newListRow(0, d.name, $$d)
  rows.add(lr)


var metadataDisplay = newDisplay(31, 1, 80, 15, title = "File Info", statusbar=false)

var contentDisplay = newDisplay(31, 16, 80, 30, title = "Content")

var dirView = newListView(1, 1, 30, 30, title = home, rows = rows, bgColor = bgBlue)

dirView.onEnter = proc (val: string) =
  let file = to[File](val)
  let metadata = fmt"""
  File Name   : {file.name}
  Kind        : {fileKind[file.info.kind]}
  Size        : {file.info.size}
  Permission  : {file.info.permissions}
  Last Access : {file.info.lastAccessTime}
  Last Write  : {file.info.lastWriteTime}
  Created At  : {file.info.creationTime}
  """.dedent()
  metadataDisplay.text = metadata
  try:
    let content = readFile(file.path)
    contentDisplay.text = content
  except:
    contentDisplay.text = "Cannot display file content"


var tuiapp = newTerminalApp(title = "dir")

tuiapp.addWidget(dirView)

tuiapp.addWidget(metadataDisplay)

tuiapp.addWidget(contentDisplay)

tuiapp.run()
