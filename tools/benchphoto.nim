## Times the photo engine's everyday work on a 12-megapixel image (4000 x
## 3000): compositing many layers, a brush stroke, filters, an adjustment
## layer, a layer style, type, the views made smaller, saving and opening.
##
##   nim c -r -d:release tools/benchphoto.nim
##
## (`-d:benchW=1000`: a smaller image; `BENCH_ONLY=composite|save`: only
## the steps whose names hold one of those, e.g. to profile them.)

import std/[monotimes, times, strutils, os]
import retroui/[gfx, photo, photopaint, photofx, photoshapes, photostyles, photodevelop, textengine, photofiles, parallel]

proc ms(t: MonoTime): float = (getMonoTime() - t).inMicroseconds.float / 1000

let only = getEnv("BENCH_ONLY")          # (parts of the names, '|' between: only those timed)

proc wanted(name: string): bool =
  if only.len == 0: return true
  for part in only.split('|'):
    if part in name: return true

template bench(name: string; reps: int; body: untyped) =
  if wanted(name):
    body                                  # (once to warm up)
    let t0 = getMonoTime()
    for _ in 0 ..< reps: body
    echo alignLeft(name, 46), formatFloat(ms(t0) / reps.float, ffDecimal, 1).align(9), " ms"

const W {.intdefine: "benchW".} = 4000
const H = W * 3 div 4
const K = W / 4000

proc photoLike(d: Doc; L: Layer) =
  for y in 0 ..< H:
    for x in 0 ..< W:
      L.px[y * W + x] = argb(255, (x * 7 + y) and 255, (x + y * 3) and 255, (x xor y) and 255)
  inc L.ver

let d = newDoc(W, H, 0xFFFFFFFF'u32, dpi = 300)
d.photoLike(d.layers[0])
# ten layers: pictures, a mask, blend modes, a shape with a style, type
for i in 0 ..< 4:
  let L = d.addLayer("Photo " & $i)
  for y in 0 ..< H:
    for x in 0 ..< W:
      if (x div 400 + y div 300 + i) mod 3 != 0: L.px[y * W + x] = argb(200, (x + i * 40) and 255, y and 255, 128)
  inc L.ver
  L.mode = [bmNormal, bmMultiply, bmScreen, bmOverlay][i]
d.addLayerMask(mfRevealAll)
let sh = d.addShapeLayer(ShapeData(path: rectPath(500 * K, 500 * K, 3500 * K, 2500 * K, 60 * K), fill: solidPaint(0xFF2050C0'u32)), "Box")
sh.fx.fx[fxDropShadow] = Effect(on: true, mode: bmMultiply, opacity: 60, color: 0xFF000000'u32, angle: 120,
                                distance: 20, size: 40)
sh.fx.fx[fxStroke] = Effect(on: true, mode: bmNormal, opacity: 100, color: 0xFFFFFFFF'u32, size: 12)
sh.opacity = 80
var t = newText("The Pixel Revival", CharStyle(family: "", size: 220 * K, color: 0xFFFFFFFF'u32, hScale: 1, vScale: 1),
                600 * K, 1500 * K)
discard d.addTextLayer(t)
discard d.newAdjustmentLayer(Adjustment(kind: "Curves", args: @[3.0, 0, 0, 128, 150, 255, 255, 2, 0, 0, 255, 255,
                                                                2, 0, 0, 255, 255, 2, 0, 0, 255, 255]))
echo "layers: ", d.layers.len, ", threads: ", threadCount()

bench("composite, the whole image", 3):
  d.markAll()
  d.updateComposite()
bench("composite, a 400 x 400 part", 20):
  d.markDirty(rect(1800, 1300, 400, 400))
  d.updateComposite()
bench("views made smaller (1:4)", 5):
  d.markAll()
  d.updateComposite()
  discard d.mipLevel(2)

d.cur = 1
bench("brush stroke, 300 px soft, 40 dabs", 3):
  d.beginStep("Brush")
  var s = d.beginStroke(PaintOpts(tool: tkBrush, color: 0xFFFF0000'u32, opacity: 100), softTip(300), 400, 400)
  for k in 1 .. 40: s.strokeTo(400 + k.float * 60, 400 + k.float * 40)
  s.endStroke()
  d.endStep()
bench("brush stroke + composite of what it touched", 3):
  d.beginStep("Brush")
  var s = d.beginStroke(PaintOpts(tool: tkBrush, color: 0xFF00FF00'u32, opacity: 100), softTip(300), 400, 2400)
  for k in 1 .. 40: s.strokeTo(400 + k.float * 60, 2400 - k.float * 40)
  s.endStroke()
  d.endStep()
  d.updateComposite()
bench("Gaussian Blur 10 px, a layer", 2):
  d.beginStep("Blur")
  d.applyFilter(30, gaussianBlur(10))
  d.endStep()
bench("Add Noise, a layer", 2):
  d.beginStep("Noise")
  d.applyFilter(0, addNoise(10, true))
  d.endStep()
bench("layer style made again (shadow, stroke)", 3):
  sh.fx.fx[fxDropShadow].distance += 1     # (a changed style: made again)
  d.updateComposite()
bench("type layer drawn again", 5):
  var tt = d.layers[^2].text
  tt.x += 1
  d.setText(d.layers[^2], tt)
bench("undo + redo of a stroke", 3):
  d.undo()
  d.redo()
let tmp = getTempDir() / "retro-bench.rpd"
bench("save .rpd", 1):
  d.saveRpd(tmp)
bench("open .rpd", 1):
  discard loadRpd(tmp)
bench("flattened copy", 3):
  discard d.flattened()
removeFile(tmp)
