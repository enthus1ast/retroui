## How the photo editor copes with a very big picture (70 megapixels, a
## 200 MB file's worth by default): opening it, the first frames, the
## mouse over it, a brush stroke, undo, scrolling, zooming, selections,
## the Move tool, filters, layers -- each through the program, frame by
## frame, as a user would do it.
##
##   nim c -d:release -r tests/bench_big.nim [WxH of the picture] [screen scale]

import std/[os, strutils, monotimes, times, algorithm, math]
import retro/uirelays/[coords, screen, input]
import retro
import retro/[photofiles, jpeg]

var iw = 10000
var ih = 7000
var bs = 1
if paramCount() >= 1 and 'x' in paramStr(1):
  iw = parseInt(paramStr(1).split('x')[0]); ih = parseInt(paramStr(1).split('x')[1])
if paramCount() >= 2: bs = parseInt(paramStr(2))
let bw = 1920
let bh = 1200
var blitPx = 0
var queue: seq[Event]
var ticks = 1000

windowRelays.createWindow = proc (l: var ScreenLayout; icon: pointer; iconLen: int) =
  l.width = bw * bs; l.height = bh * bs; l.scaleX = 1; l.scaleY = 1; l.uiScale = 100 * bs
windowRelays.getWindowLayout = proc (): ScreenLayout =
  ScreenLayout(width: bw * bs, height: bh * bs, scaleX: 1, scaleY: 1, uiScale: 100 * bs)
windowRelays.refresh = proc () = discard
windowRelays.setWindowTitle = proc (t: string) = discard
windowRelays.setCursor = proc (c: CursorKind) = discard
drawRelays.blitRGBA = proc (p: ptr UncheckedArray[uint32]; w, h: int; dst: Rect; f: RGBAFormat): bool =
  blitPx += w * h
  true
inputRelays.pollEvent = proc (e: var Event; fl: set[InputFlag]): bool =
  if queue.len == 0: return false
  e = queue[0]
  queue.delete(0)
  true
inputRelays.waitEvent = proc (e: var Event; t: int; fl: set[InputFlag]): bool = inputRelays.pollEvent(e, fl)
inputRelays.getTicks = proc (): int = ticks
inputRelays.shutdown = proc () = discard
fontRelays.openFont = proc (path: string; size: int; style: FontStyles; metrics: var FontMetrics): Font = Font(0)
fontRelays.closeFont = proc (f: Font) = discard
fontRelays.getFontMetrics = proc (f: Font): FontMetrics = FontMetrics()
fontRelays.measureText = proc (f: Font; text: string): TextExtent = TextExtent()
fontRelays.drawText = proc (f: Font; x, y: int; text: string; fg, bg: Color): TextExtent = TextExtent()

const photoUnderTest = true
include ../examples/photo

let home = getTempDir() / "retro-bench-big"
removeDir(home)
createDir(home)
putEnv("HOME", home)
setup()
startApp("photo", bw * bs, bh * bs)

proc msSince(t: MonoTime): float = float((getMonoTime() - t).inMicroseconds) / 1000
template f1(v: float): string = formatFloat(v, ffDecimal, 1)
proc mb(n: int): string = $(n div (1024 * 1024)) & " MB"
proc phase(name: string) =
  try: writeFile("/tmp/bench_phase", name)
  except CatchableError: discard

phase("making the picture")
# a photograph's worth of detail (smooth shapes and fine grain: JPEG makes it big)
let path = home / "big.jpg"
block:
  let t0 = getMonoTime()
  let b = newBitmap(iw, ih)
  for y in 0 ..< ih:
    let fy = y.float / ih.float
    for x in 0 ..< iw:
      let fx = x.float / iw.float
      let n = int(hash2(x, y) and 31)
      let r = clamp(int(128 + 100 * sin(fx * 9 + fy * 3)) + n, 0, 255)
      let g = clamp(int(120 + 90 * sin(fy * 7 - fx * 2)) + n, 0, 255)
      let bl = clamp(int(110 + 80 * cos((fx - fy) * 11)) + n, 0, 255)
      b.px[y * iw + x] = argb(255, r, g, bl)
  writeFile(path, encodeJpeg(b, 92))
  echo "picture ", iw, " x ", ih, " (", iw * ih div 1_000_000, " Mpx), ", mb(getFileSize(path).int),
       " JPEG, made in ", f1(msSince(t0)), " ms"

var lastFrame: float
proc frameOnce() =
  let t0 = getMonoTime()
  discard beginFrame()
  photoFrame()
  endFrame()
  lastFrame = msSince(t0)
  ticks += 16

var benchLog: seq[string]
proc line(label: string; v: string) =
  echo label.alignLeft(34), v.alignLeft(42), (if getEnv("BENCH_MEM") == "1": "  " & mb(memoryUsed()) else: "")
  benchLog.add label & ": " & v

proc frames(label: string; n: int; prep: proc ()) =
  ## `n` frames, each after `prep`: the median and the slowest.
  phase(label)
  var ts: seq[float]
  for i in 0 ..< n:
    prep()
    frameOnce()
    ts.add lastFrame
  ts.sort()
  line(label, "median " & f1(ts[ts.len div 2]) & " ms, slowest " & f1(ts[^1]) & " ms")

let reps = max(1, parseInt(getEnv("BENCH_REPS", "1")))
proc once(label: string; body: proc ()) =
  ## One action and the frames until the program is quiet again.
  phase(label)
  for r in 1 ..< reps:
    body()
    frameOnce()
    while queue.len > 0: frameOnce()
    frameOnce()
  let t0 = getMonoTime()
  body()
  var n = 0
  frameOnce()
  inc n
  while queue.len > 0 and n < 400:
    frameOnce()
    inc n
  frameOnce()
  line(label, f1(msSince(t0)) & " ms (" & $(n + 1) & " frames)")

frameOnce()
frameOnce()

# ---- opening ---------------------------------------------------------------------------------------
phase("open")
block:
  let t0 = getMonoTime()
  openFile(path)
  let opened = msSince(t0)
  let t1 = getMonoTime()
  frameOnce()
  let first = lastFrame
  frameOnce()
  frameOnce()
  line("open (decode, the document)", f1(opened) & " ms")
  line("first frame", f1(first) & " ms; three frames " & f1(msSince(t1)) & " ms")
  line("memory after opening", mb(memoryUsed()))

let dw = active
let d = dw.doc
doAssert d.w == iw
for i in 0 ..< 5: frameOnce()
let v = dw.view.view
let cx = v.x + v.w div 2
let cy = v.y + v.h div 2

frames("nothing changed", 20, proc () = discard)
var flip = false
selectTool(tBrush)
frames("mouse over the picture (Brush)", 30, proc () =
  flip = not flip
  queue.add Event(kind: MouseMoveEvent, x: cx + (if flip: 7 else: 0), y: cy))

# ---- a brush stroke --------------------------------------------------------------------------------
phase("brush stroke")
block:
  queue.add Event(kind: MouseMoveEvent, x: cx - 200, y: cy)
  frameOnce()
  queue.add Event(kind: MouseDownEvent, x: cx - 200, y: cy, button: LeftButton, clicks: 1)
  frameOnce()
  let downMs = lastFrame
  var ts: seq[float]
  for i in 1 .. 40:
    queue.add Event(kind: MouseMoveEvent, x: cx - 200 + i * 10, y: cy + int(40 * sin(i.float / 5)))
    frameOnce()
    ts.add lastFrame
  queue.add Event(kind: MouseUpEvent, x: cx + 200, y: cy, button: LeftButton)
  frameOnce()
  let upMs = lastFrame
  var after = 0.0
  for i in 0 ..< 3:
    frameOnce()
    after += lastFrame
  ts.sort()
  line("brush: press", f1(downMs) & " ms")
  line("brush: each frame of the stroke", "median " & f1(ts[ts.len div 2]) & " ms, slowest " & f1(ts[^1]) & " ms")
  line("brush: release", f1(upMs) & " ms; next 3 frames " & f1(after) & " ms")

once("undo (Ctrl+Z)", proc () =
  queue.add Event(kind: KeyDownEvent, key: KeyZ, mods: {CtrlPressed})
  queue.add Event(kind: KeyUpEvent, key: KeyZ, mods: {CtrlPressed}))
once("redo (Ctrl+Shift+Z)", proc () =
  queue.add Event(kind: KeyDownEvent, key: KeyZ, mods: {CtrlPressed, ShiftPressed})
  queue.add Event(kind: KeyUpEvent, key: KeyZ, mods: {CtrlPressed, ShiftPressed}))

frames("scrolled", 20, proc () =
  dw.view.offX = dw.view.offX + (if flip: 37 else: -37)
  flip = not flip)
once("zoom to 100 %", proc () = runCommand("Actual Pixels"))
frames("scrolled at 100 %", 20, proc () =
  dw.view.offX = dw.view.offX + (if flip: 37 else: -37)
  flip = not flip)
once("fit on screen", proc () = runCommand("Fit on Screen"))
frames("zoom in and out", 10, proc () =
  if flip: runCommand("Zoom In") else: runCommand("Zoom Out")
  flip = not flip)
once("fit on screen", proc () = runCommand("Fit on Screen"))

# ---- selections --------------------------------------------------------------------------------------
once("select all", proc () = runCommand("All"))
frames("with marching ants", 20, proc () = discard)
once("deselect", proc () = runCommand("None"))
selectTool(tMarquee)
phase("marquee drag")
block:
  queue.add Event(kind: MouseMoveEvent, x: cx - 300, y: cy - 200)
  queue.add Event(kind: MouseDownEvent, x: cx - 300, y: cy - 200, button: LeftButton, clicks: 1)
  frameOnce()
  var ts: seq[float]
  for i in 1 .. 20:
    queue.add Event(kind: MouseMoveEvent, x: cx - 300 + i * 25, y: cy - 200 + i * 18)
    frameOnce()
    ts.add lastFrame
  queue.add Event(kind: MouseUpEvent, x: cx + 200, y: cy + 160, button: LeftButton)
  frameOnce()
  let upMs = lastFrame
  frameOnce()
  ts.sort()
  line("marquee: each frame of the drag", "median " & f1(ts[ts.len div 2]) & " ms, slowest " & f1(ts[^1]) & " ms")
  line("marquee: release", f1(upMs) & " ms; then " & f1(lastFrame) & " ms")
frames("a selection's ants", 20, proc () = discard)
once("invert (Ctrl+I) in the selection", proc () = runCommand("Invert"))
once("deselect", proc () = runCommand("None"))

# ---- the Move tool, layers --------------------------------------------------------------------------
once("new layer", proc () =
  d.beginStep("New Layer")
  d.touchLayers()
  discard d.addLayer("Layer 1")
  d.endStep())
selectTool(tBrush)
phase("stroke on layer")
block:
  queue.add Event(kind: MouseMoveEvent, x: cx - 100, y: cy)
  queue.add Event(kind: MouseDownEvent, x: cx - 100, y: cy, button: LeftButton, clicks: 1)
  for i in 1 .. 20: queue.add Event(kind: MouseMoveEvent, x: cx - 100 + i * 10, y: cy + i * 3)
  queue.add Event(kind: MouseUpEvent, x: cx + 100, y: cy + 60, button: LeftButton)
  let t0 = getMonoTime()
  while queue.len > 0: frameOnce()
  frameOnce()
  line("a stroke on the new layer (all)", f1(msSince(t0)) & " ms")
selectTool(tMove)
frames("Move tool: mouse over", 20, proc () =
  flip = not flip
  queue.add Event(kind: MouseMoveEvent, x: cx + (if flip: 9 else: 0), y: cy + 40))
phase("move drag")
block:
  queue.add Event(kind: MouseMoveEvent, x: cx - 50, y: cy + 20)
  queue.add Event(kind: MouseDownEvent, x: cx - 50, y: cy + 20, button: LeftButton, clicks: 1)
  frameOnce()
  let downMs = lastFrame
  var ts: seq[float]
  for i in 1 .. 20:
    queue.add Event(kind: MouseMoveEvent, x: cx - 50 + i * 6, y: cy + 20 + i * 4)
    frameOnce()
    ts.add lastFrame
  queue.add Event(kind: MouseUpEvent, x: cx + 70, y: cy + 100, button: LeftButton)
  frameOnce()
  let upMs = lastFrame
  frameOnce()
  ts.sort()
  line("Move: press", f1(downMs) & " ms")
  line("Move: each frame of the drag", "median " & f1(ts[ts.len div 2]) & " ms, slowest " & f1(ts[^1]) & " ms")
  line("Move: release", f1(upMs) & " ms; then " & f1(lastFrame) & " ms")
once("free transform (Ctrl+T)", proc () = startTransform(xkScale))
frames("free transform: frames", 10, proc () = discard)
phase("transform drag")
block:
  if xf.on:
    let (hx, hy) = dw.view.toScreen(d, xf.quad[2][0], xf.quad[2][1])
    queue.add Event(kind: MouseMoveEvent, x: hx, y: hy)
    queue.add Event(kind: MouseDownEvent, x: hx, y: hy, button: LeftButton, clicks: 1)
    frameOnce()
    var ts: seq[float]
    for i in 1 .. 15:
      queue.add Event(kind: MouseMoveEvent, x: hx + i * 5, y: hy + i * 4)
      frameOnce()
      ts.add lastFrame
    queue.add Event(kind: MouseUpEvent, x: hx + 75, y: hy + 60, button: LeftButton)
    frameOnce()
    ts.sort()
    line("free transform: dragging a corner", "median " & f1(ts[ts.len div 2]) & " ms, slowest " & f1(ts[^1]) & " ms")
    once("free transform: Enter", proc () =
      queue.add Event(kind: KeyDownEvent, key: KeyEnter)
      queue.add Event(kind: KeyUpEvent, key: KeyEnter))
once("layer opacity 50 %", proc () =
  d.beginStep("Opacity")
  d.touchLayers()
  d.current.opacity = 128
  d.endStep()
  inc d.ver
  d.markAll())
once("merge down", proc () = runCommand("Merge Down"))

# ---- filters, adjustments ------------------------------------------------------------------------------
once("Filter > Blur", proc () = runCommand("Blur"))
once("Image > Invert", proc () = runCommand("Invert"))
once("Auto Levels", proc () = runCommand("Auto Levels"))
selectTool(tWand)
wandMode = 0
once("magic wand click", proc () =
  queue.add Event(kind: MouseMoveEvent, x: cx, y: cy)
  queue.add Event(kind: MouseDownEvent, x: cx, y: cy, button: LeftButton, clicks: 1)
  queue.add Event(kind: MouseUpEvent, x: cx, y: cy, button: LeftButton))
once("deselect", proc () = runCommand("None"))
wandMode = 2
once("Object Selection: first hover", proc () =
  queue.add Event(kind: MouseMoveEvent, x: cx + 3, y: cy))
frames("Object Selection: hover", 10, proc () =
  flip = not flip
  queue.add Event(kind: MouseMoveEvent, x: cx + (if flip: 30 else: 0), y: cy))
wandMode = 0
once("history: 20 steps back", proc () = d.goToHistory(max(0, d.historyAt - 3)))
line("memory at the end", mb(memoryUsed()))
line("history in memory", f1(d.historyInMemory / 1048576) & " MB")
writeFile(getTempDir() / "bench_big.txt", benchLog.join("\n"))
