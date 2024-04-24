import illwill, base_wg, strformat
import tables, threading/channels

type
  Percent* = range[0.0..100.0]

  ProgressBarObj* = object of BaseWidget
    fgLoading: ForegroundColor
    fgLoaded: ForegroundColor
    percent: Percent
    loadedBlock: string
    loadingBlock: string
    showPercentage: bool
    events*: Table[string, EventFn[ProgressBar]]

  ProgressBar* = ref ProgressBarObj

proc newProgressBar*(px, py, w, h: int, id = "",
                     border = true, percent: Percent = 0.0,
                     loadedBlock = "█",
                     loadingBlock = "-",
                     showPercentage = true,
                     bgColor = bgNone,
                     fgColor = fgWhite,                      
                     tb = newTerminalBuffer(w + 2, h + py)): ProgressBar =
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

  result = ProgressBar(
    width: w,
    height: h,
    posX: px,
    posY: py,
    id: id,
    fgLoading: fgNone,
    fgLoaded: fgGreen,
    percent: percent,
    tb: tb,
    style: style,
    loadedBlock: loadedBlock,
    loadingBlock: loadingBlock,
    showPercentage: showPercentage,
    events: initTable[string, EventFn[ProgressBar]]()
  )
  result.channel = newChan[WidgetBgEvent]()
  result.keepOriginalSize()


proc newProgressBar*(px, py: int, w, h: WidgetSize, id = "",
                     border = true, percent: Percent = 0.0,
                     loadedBlock = "█",
                     loadingBlock = "-",
                     showPercentage = true,
                     bgColor = bgNone,
                     fgColor = fgWhite,                      
                     tb = newTerminalBuffer(w.toInt + 2, h.toInt + py)): ProgressBar =
  let width = (consoleWidth().toFloat * w).toInt
  let height = (consoleHeight().toFloat * h).toInt
  return newProgressBar(px, py, width, height, id, border, percent,
                        loadedBlock, loadingBlock, showPercentage,
                        bgColor, fgColor, tb)


proc newProgressBar*(id: string): ProgressBar =
  var pb = ProgressBar(
    id: id,
    style: WidgetStyle(
      paddingX1: 1,
      paddingX2: 1,
      paddingY1: 1,
      paddingY2: 1,
      border: true,
      bgColor: bgNone,
      fgColor: fgWhite
    ),
    loadedBlock: "█",
    loadingBlock: "-",
    showPercentage: true,
    events: initTable[string, EventFn[ProgressBar]]()
  )
  pb.channel = newChan[WidgetBgEvent]()
  return pb


proc renderClearRow(pb: ProgressBar): void =
  pb.tb.fill(pb.x1, pb.posY, pb.x2, pb.height, " ")


method render*(pb: ProgressBar) =
  if not pb.illwillInit: return
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
  pb.tb.display()
  

method wg*(pb: ProgressBar): ref BaseWidget = pb


proc update*(pb: ProgressBar, point: float) =
  if pb.percent + point >= 100.0:
    pb.percent = 100.0
  else:
    pb.percent += point
  pb.render()


proc set*(pb: ProgressBar, point: float) =
  if point >= 100.0:
    pb.percent = 100.0
  elif point <= 0.0:
    pb.percent = 0.0
  else:
    pb.percent = point
  pb.render()


proc completed*(pb: ProgressBar) =
  pb.percent = 100.0
  pb.render()


proc on*(pb: ProgressBar, event: string, fn: EventFn[ProgressBar]) =
  pb.events[event] = fn


method call*(pb: ProgressBar, event: string, args: varargs[string]) =
  let fn = pb.events.getOrDefault(event, nil)
  if not fn.isNil:
    fn(pb, args)


method call*(pb: ProgressBarObj, event: string, args: varargs[string]) =
  let fn = pb.events.getOrDefault(event, nil)
  if not fn.isNil:
    # new reference will be created
    let pbRef = pb.asRef()
    fn(pbRef, args)
    

method poll*(pb: ProgressBar) =
  var widgetEv: WidgetBgEvent
  if pb.channel.tryRecv(widgetEv):
    pb.call(widgetEv.event, widgetEv.args)
    pb.render()


