import illwill, sequtils, base_wg, unicode, strformat


type
  Percent* = range[0.0..100.0]

  ProgressBar* = object of BaseWidget
    fgLoading: ForegroundColor
    fgLoaded: ForegroundColor
    percent: Percent
    loadedBlock: string
    loadingBlock: string
    showPercentage: bool
    
  
proc newProgressBar*(w, h, px, py: int,
                     tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py), 
                     bordered = true, percent: Percent = 0.0, loadedBlock = "█",
                     loadingBlock = "-", showPercentage = true): ref ProgressBar =
  result = (ref ProgressBar)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    fgLoading: fgNone,
    fgLoaded: fgGreen,
    percent: percent,
    tb: tb,
    bordered: bordered,
    paddingY: if bordered: 2 else: 1,
    paddingX: if bordered: 2 else: 1,
    loadedBlock: loadedBlock,
    loadingBlock: loadingBlock,
    showPercentage: showPercentage
  )


proc renderClearRow(pb: ref ProgressBar): void =
  pb.tb.fill(pb.posX + pb.paddingX, pb.posY, pb.width - pb.paddingX,
             pb.height, " ")

proc render*(pb: ref ProgressBar) =
  pb.renderClearRow()
  var progressLoaded: string = ""
  var progressLoading: string = ""
  var fullProgress = pb.width - pb.paddingX - 8
  var progressBarWidth = pb.width
  if fullProgress <= 10:
    fullProgress = 10
    progressBarWidth = 10 + 8 + pb.paddingX
  let pc = (pb.percent/100) * fullProgress.toFloat()
  for i in 0..<fullProgress:
    if i <= pc.toInt():
      progressLoaded &= pb.loadedBlock
    else:
      progressLoading &= pb.loadingBlock
  let percentage = fmt"{(pc / fullProgress.toFloat()) * 100.0:>3.2f}"
  #echo "\n\n\n" & percentage
  pb.tb.drawRect(progressBarWidth, pb.height, pb.posX, pb.posY)
  pb.tb.write(pb.posX + 1, pb.height - 1, pb.bgColor, pb.fgLoaded, progressLoaded, resetStyle,
              pb.bgColor, pb.fgLoading, progressLoading, percentage, "%", resetStyle)

proc move*(pb: ref ProgressBar, point: float) = 
  if pb.percent + point >= 100.0:
    pb.percent = 100.0
  else:
    pb.percent += point
  pb.render()

proc update*(pb: ref ProgressBar, point: float) =
  if point >= 100.0:
    pb.percent = 100.0
  elif point <= 0.0:
    pb.percent = 0.0
  else:
    pb.percent = point
  pb.render()

proc completed*(pb: ref ProgressBar) =
  pb.percent = 100.0
  pb.render()

proc show*(pb: ref ProgressBar): void =
  pb.render()


proc `-`*(pb: ref ProgressBar): void =
  pb.show()
