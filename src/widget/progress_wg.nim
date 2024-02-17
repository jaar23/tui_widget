import illwill, base_wg, strformat


type
  Percent* = range[0.0..100.0]

  ProgressBar* = object of BaseWidget
    fgLoading: ForegroundColor
    fgLoaded: ForegroundColor
    percent: Percent
    loadedBlock: string
    loadingBlock: string
    showPercentage: bool


proc newProgressBar*(px, py, w, h: int,
                     tb: TerminalBuffer = newTerminalBuffer(w + 2, h + py),
                     border = true, percent: Percent = 0.0,
                     fgColor: ForegroundColor = fgWhite, bgColor: BackgroundColor = bgNone,
                     loadedBlock = "█",
                     loadingBlock = "-",
                     showPercentage = true): ref ProgressBar =
  let padding = if border: 2 else: 1
  let style = WidgetStyle(
    paddingX1: padding,
    paddingX2: padding,
    paddingY1: padding,
    paddingY2: padding,
    border: border,
    fgColor: fgColor,
    bgColor: bgColor
  )

  result = (ref ProgressBar)(
    width: w,
    height: h,
    posX: px,
    posY: py,
    fgLoading: fgNone,
    fgLoaded: fgGreen,
    percent: percent,
    tb: tb,
    style: style,
    loadedBlock: loadedBlock,
    loadingBlock: loadingBlock,
    showPercentage: showPercentage
  )


proc renderClearRow(pb: ref ProgressBar): void =
  pb.tb.fill(pb.x1, pb.posY, pb.x2, pb.height, " ")


method render*(pb: ref ProgressBar) =
  pb.renderClearRow()
  var progressLoaded: string = ""
  var progressLoading: string = ""
  var fullProgress = pb.width - pb.paddingX1 - 8
  var progressBarWidth = pb.width
  if fullProgress <= 10:
    fullProgress = 10
    progressBarWidth = 10 + 8 + pb.paddingX1
  let pc = (pb.percent/100) * fullProgress.toFloat()
  for i in 0..<fullProgress:
    if i <= pc.toInt():
      progressLoaded &= pb.loadedBlock
    else:
      progressLoading &= pb.loadingBlock
  let percentage = fmt"{(pc / fullProgress.toFloat()) * 100.0:>3.2f}"
  pb.tb.drawRect(progressBarWidth, pb.height, pb.posX, pb.posY)
  pb.tb.write(pb.posX + 1, pb.height - 1, pb.bg, pb.fgLoaded, progressLoaded, resetStyle,
              pb.bg, pb.fgLoading, progressLoading, percentage, "%", resetStyle)


method wg*(pb: ref ProgressBar): ref BaseWidget = pb


proc update*(pb: ref ProgressBar, point: float) =
  if pb.percent + point >= 100.0:
    pb.percent = 100.0
  else:
    pb.percent += point
  pb.render()


proc set*(pb: ref ProgressBar, point: float) =
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


