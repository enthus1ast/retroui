## How long the screen takes: the photo editor with a picture open, at
## 1920 x 1080 and 3840 x 2160 (100 % and 200 %), every pixel redrawn
## (a window resized, a theme changed) and a little redrawn (the cursor
## over a button).
##
##   nim c -d:release -r tests/bench_render.nim [WxH] [scale]

import std/[os, strutils, monotimes, times, algorithm]
import retro/uirelays/[coords, screen, input]
import retro

var bw = 1920
var bh = 1080
var bs = 1
if paramCount() >= 1 and 'x' in paramStr(1):
  bw = parseInt(paramStr(1).split('x')[0]); bh = parseInt(paramStr(1).split('x')[1])
if paramCount() >= 2: bs = parseInt(paramStr(2))
let noBlit = getEnv("BENCH_NOBLIT") == "1"
var blits = 0
var blitPx = 0
var screenPx = newSeq[uint32](bw * bs * bh * bs)
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
  inc blits
  blitPx += w * h
  if noBlit: return true
  for y in 0 ..< h:
    copyMem(addr screenPx[(dst.y + y) * bw * bs + dst.x], addr p[y * w], w * 4)
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

let home = getTempDir() / "retro-bench-render"
removeDir(home)
createDir(home)
putEnv("HOME", home)
setup()
startApp("photo", bw * bs, bh * bs)
let d = newDoc(3000, 2000, white, name = "bench")
let L = d.layer
for y in 0 ..< d.h:
  for x in 0 ..< d.w:
    L.px[y * d.w + x] = argb(255, x * 255 div d.w, y * 255 div d.h, (x xor y) and 255)
inc L.ver
d.markAll()
addDoc(d)

var recMs, presMs: float
proc frameOnce() =
  let t0 = getMonoTime()
  discard beginFrame()
  photoFrame()
  let t1 = getMonoTime()
  endFrame()
  recMs = float((t1 - t0).inMicroseconds) / 1000
  presMs = float((getMonoTime() - t1).inMicroseconds) / 1000
  ticks += 16

for i in 0 ..< 10: frameOnce()

proc measure(label: string; n: int; prep: proc ()) =
  var ts, rs, ps: seq[float]
  for i in 0 ..< n:
    prep()
    blits = 0; blitPx = 0
    let t0 = getMonoTime()
    frameOnce()
    ts.add float((getMonoTime() - t0).inMicroseconds) / 1000
    rs.add recMs
    ps.add presMs
  ts.sort(); rs.sort(); ps.sort()
  template f2(v: float): string = formatFloat(v, ffDecimal, 2)
  echo label.alignLeft(28), " median ", f2(ts[ts.len div 2]), " ms (building ", f2(rs[rs.len div 2]),
       ", drawing ", f2(ps[ps.len div 2]), ")  ", blitPx div 1000, " kpx sent"

echo "screen ", bw * bs, "x", bh * bs, " at ", bs * 100, " %, ", threadCount(), " threads"
measure("full redraw", 15, proc () = invalidate())
var flip = false
measure("cursor over a menu title", 30, proc () =
  flip = not flip
  queue.add Event(kind: MouseMoveEvent, x: (if flip: 40 else: 80) * bs, y: 10 * bs))
measure("nothing changed", 30, proc () = discard)
measure("zoom in and out", 16, proc () =
  if active.view.zoom == 1: active.view.setZoom(d, 2) else: active.view.setZoom(d, 1))
measure("scrolled", 16, proc () =
  active.view.offX = (if active.view.offX == 0: 40 else: 0))
measure("a dab painted (64 px)", 20, proc () =
  let x0 = 1000 + (ticks mod 500)
  for y in 800 ..< 864:
    for x in x0 ..< x0 + 64: L.px[y * d.w + x] = 0xFF2040A0'u32
  inc L.ver
  d.markDirty(rect(x0, 800, 64, 64)))

# what was drawn bit by bit is what a whole redraw draws
d.setSelection(d.rectMask(rect(500, 400, 900, 700)))
for i in 0 ..< 3: frameOnce()
for i in 0 ..< 6:
  let x0 = 600 + i * 150
  for y in 500 ..< 560:
    for x in x0 ..< x0 + 60: L.px[y * d.w + x] = 0xFFA02040'u32
  inc L.ver
  d.markDirty(rect(x0, 500, 60, 60))
  active.view.offY = active.view.offY + 7
  frameOnce()
active.view.setZoom(d, 1)
frameOnce()
active.view.offX = 333; active.view.offY = 211
frameOnce()
for i in 0 ..< 4:
  active.view.offX -= 19; active.view.offY += 23
  d.markDirty(rect(900, 700, 30, 30))
  frameOnce()
let partial = screenPx
invalidate()
let (sx, sy) = (active.view.offX, active.view.offY)
active.view.setZoom(d, active.view.zoom)    # (the view made again from nothing)
active.view.offX = sx
active.view.offY = sy

frameOnce()
doAssert partial == screenPx, "a frame drawn in parts differs from the whole frame"
echo "parts drawn = whole drawn: ok"

for z in [-3, -2, 3]:
  active.view.setZoom(d, z)
  frameOnce()
  for i in 0 ..< 5:
    let x0 = 777 + i * 211
    for y in 333 + i ..< 371 + i:
      for x in x0 ..< x0 + 37: L.px[y * d.w + x] = 0xFF30C050'u32 + uint32(i * 1234)
    inc L.ver
    d.markDirty(rect(x0, 333 + i, 37, 38))
    if i == 2: active.view.offX += 13
    frameOnce()
  let part2 = screenPx
  invalidate()
  let (qx, qy) = (active.view.offX, active.view.offY)
  active.view.setZoom(d, active.view.zoom)
  active.view.offX = qx
  active.view.offY = qy
  ticks -= 16                 # (the same moment: the ants where they were)
  frameOnce()
  if part2 != screenPx:
    var n = 0
    var first = -1
    for i in 0 ..< part2.len:
      if part2[i] != screenPx[i]:
        inc n
        if first < 0: first = i
    echo "zoom ", z, ": ", n, " pixels differ, first at ", first mod (bw * bs), ",", first div (bw * bs),
         " ", toHex(part2[first]), " vs ", toHex(screenPx[first])
    quit 1
echo "zoomed in and out: ok"
