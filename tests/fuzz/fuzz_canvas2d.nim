## Fuzzes the canvas (retroui/canvas2d): random calls of the whole API with
## good and hostile values (NaN, infinities, huge, tiny, negative), random
## colors, fonts, dash lists, transforms, paths, pictures and image data,
## on canvases of random sizes and pixel ratios; then the same in a window
## (immediate and retained) with the mouse moving and clicking over it.
## Each call must return quickly; nothing may crash.
##
##   nim c -d:release --stackTrace:on --lineTrace:on tests/fuzz/fuzz_canvas2d.nim
##   tests/fuzz/fuzz_canvas2d 20000 7        # calls, random seed
##
## FUZZ_SLOW=1 lists calls over 50 ms; FUZZ_TRACE=n prints every call from
## the n-th on (to find the one that fails).

import std/[random, strutils, os, math, times]
import retroui
import retroui/canvas2d
import retroui/uirelays/input
import ../harness

randomize(if paramCount() >= 2: parseInt(paramStr(2)) else: 7)
let rounds = if paramCount() >= 1: parseInt(paramStr(1)) else: 20000

const specials = [NaN, Inf, -Inf, 0.0, -0.0, 1e308, -1e308, 1e-308, 5e-324, 1.0, -1.0,
                  0.5, 1e15, -1e15, 1e7, -1e7, 123456789.123, 2 * PI, -2 * PI]

proc num(): float =
  ## Mostly sensible coordinates, sometimes anything.
  case rand(9)
  of 0: sample(specials)
  of 1: rand(1.0) * pow(10.0, float(rand(-20 .. 20))) * (if rand(1) == 0: 1.0 else: -1.0)
  of 2: float(rand(-50 .. 50))
  else: rand(-20.0 .. 320.0)

proc small(): float =
  case rand(7)
  of 0: sample(specials)
  of 1: rand(-5.0 .. 0.0)
  else: rand(0.0 .. 40.0)

proc angle(): float =
  case rand(5)
  of 0: sample(specials)
  of 1: rand(-100.0 .. 100.0)
  else: rand(-2 * PI .. 2 * PI)

proc colorText(): string =
  case rand(9)
  of 0: sample(["red", "navy", "transparent", "gold", "REBECCAPURPLE", "", "nonsense",
                "#", "#f", "#ff00", "#12345", "#ff00ff80", "#FFF", "#zzz"])
  of 1: "rgb(" & $rand(-300 .. 300) & ", " & $rand(255) & ", " & $num() & ")"
  of 2: "rgba(" & $rand(255) & "," & $rand(255) & "," & $rand(255) & "," & $num() & ")"
  of 3: "hsl(" & $num() & ", " & $rand(-10 .. 120) & "%, " & $rand(100) & "%)"
  of 4: "hsla(" & $rand(360) & "," & $rand(100) & "%," & $rand(100) & "%," & $rand(1.0) & ")"
  of 5: "rgb(" & "1,".repeat(rand(0 .. 8)) & ")"
  of 6:
    var s = ""
    for _ in 0 ..< rand(0 .. 12): s.add char(rand(255))
    s
  else: "#" & toHex(rand(0xFFFFFF), 6)

proc fontText(): string =
  case rand(5)
  of 0: sample(["", "garbage", "px", "12", "-5px sans", "NaNpx sans", "infpx mono",
                "1e308px sans", "0px sans", "16px/20px serif", "bold", "\xFF\xFE"])
  of 1: $rand(-10 .. 4000) & "px sans-serif"
  of 2: sample(["bold ", "italic ", "bold italic ", "", "900 "]) & $rand(1 .. 80) &
        sample(["px", "pt", "em", "rem"]) & sample([" sans-serif", " monospace", " Arial", ""])
  else: $rand(6 .. 40) & "px sans-serif"

proc textToDraw(): string =
  case rand(6)
  of 0: ""
  of 1: "x".repeat(rand(0 .. 3000))
  of 2: sample(["Hello", "مرحبا بالعالم", "αβγ", "日本語", "😀👍", "a\tb\nc", "\xFF\xFE\x00"])
  else:
    var s = ""
    for _ in 0 ..< rand(0 .. 30): s.add char(rand(32 .. 126))
    s

proc picture(): Bitmap =
  case rand(5)
  of 0: result = nil
  of 1: result = newBitmap(0, 0)
  of 2: result = newBitmap(1, 1, 0xFF00FF00'u32)
  else:
    result = newBitmap(rand(1 .. 64), rand(1 .. 64))
    for p in result.px.mitems: p = uint32(rand(int(high(uint32))))

proc imageData(c: Canvas2D): ImageData =
  case rand(4)
  of 0: result = nil
  of 1: result = ImageData(width: rand(-5 .. 50), height: rand(-5 .. 50),
                           data: newSeq[uint8](rand(0 .. 400)))
  of 2: result = c.getImageData(rand(-50 .. 300), rand(-50 .. 300), rand(-5 .. 80),
                                rand(-5 .. 80))
  else:
    result = c.createImageData(rand(-5 .. 60), rand(-5 .. 60))
    for b in result.data.mitems: b = uint8(rand(255))

var path2d = newPath2D()

proc pathCall(p: Path2D) =
  case rand(10)
  of 0: p.moveTo(num(), num())
  of 1: p.lineTo(num(), num())
  of 2: p.quadraticCurveTo(num(), num(), num(), num())
  of 3: p.bezierCurveTo(num(), num(), num(), num(), num(), num())
  of 4: p.arc(num(), num(), small(), angle(), angle(), rand(1) == 0)
  of 5: p.arcTo(num(), num(), num(), num(), small())
  of 6: p.ellipse(num(), num(), small(), small(), angle(), angle(), angle(), rand(1) == 0)
  of 7: p.rect(num(), num(), num(), num())
  of 8:
    if rand(1) == 0: p.roundRect(num(), num(), num(), num(), small())
    else:
      var radii: seq[float]
      for _ in 0 ..< rand(0 .. 6): radii.add small()
      p.roundRect(num(), num(), num(), num(), radii)
  of 9: p.closePath()
  else: p.addPath(if rand(3) == 0: nil else: path2d)

proc gradient(c: Canvas2D): CanvasGradient =
  result = case rand(2)
           of 0: c.createLinearGradient(num(), num(), num(), num())
           of 1: c.createRadialGradient(num(), num(), small(), num(), num(), small())
           else: c.createConicGradient(angle(), num(), num())
  for _ in 0 ..< rand(0 .. 5):
    if rand(4) == 0: result.addColorStop(num(), colorText())
    else: result.addColorStop(rand(1.0), color(uint8(rand(255)), uint8(rand(255)),
                                               uint8(rand(255)), uint8(rand(255))))

var callNo = 0
let traceFrom = parseInt(getEnv("FUZZ_TRACE", "-1"))

proc call(c: Canvas2D): int {.discardable.} =
  ## One random call of the API (which one is returned).
  result = rand(60)
  inc callNo
  if traceFrom >= 0 and callNo >= traceFrom:
    stderr.writeLine "call ", callNo, " kind ", result, " on ", c.pixelWidth, "x", c.pixelHeight
  case result
  of 0: c.save()
  of 1: c.restore()
  of 2: c.translate(num(), num())
  of 3: c.scale(small() / 10, small() / 10)
  of 4: c.rotate(angle())
  of 5: c.transform(num() / 100, num() / 100, num() / 100, num() / 100, num(), num())
  of 6: c.setTransform(num() / 100, num() / 100, num() / 100, num() / 100, num(), num())
  of 7: c.resetTransform()
  of 8: c.fillStyle = colorText()
  of 9: c.strokeStyle = colorText()
  of 10: c.fillStyle = c.gradient
  of 11: c.strokeStyle = c.gradient
  of 12: c.fillStyle = c.createPattern(picture(), sample(["repeat", "repeat-x",
                                         "repeat-y", "no-repeat", "", "bogus"]))
  of 13: c.lineWidth = small()
  of 14: c.lineCap = sample(["butt", "round", "square", "bogus"])
  of 15: c.lineJoin = sample(["miter", "round", "bevel", ""])
  of 16: c.miterLimit = small()
  of 17:
    var d: seq[float]
    for _ in 0 ..< rand(0 .. 7): d.add small()
    c.setLineDash(d)
  of 18: c.lineDashOffset = num()
  of 19: c.globalAlpha = (if rand(3) == 0: num() else: rand(1.0))
  of 20: c.globalCompositeOperation = CanvasCompositeOp(rand(ord(high(CanvasCompositeOp))))
  of 21: c.globalCompositeOperation = sample(["source-over", "xor", "lighter", "copy", "nope"])
  of 22: c.font = fontText()
  of 23: c.textAlign = sample(["start", "end", "left", "right", "center", "?"])
  of 24: c.textBaseline = CanvasTextBaseline(rand(ord(high(CanvasTextBaseline))))
  of 25: c.shadowColor = colorText()
  of 26: c.shadowBlur = small()
  of 27: c.shadowOffsetX = num() / 10
  of 28: c.shadowOffsetY = num() / 10
  of 29: c.imageSmoothingEnabled = rand(1) == 0
  of 30: c.beginPath()
  of 31: c.moveTo(num(), num())
  of 32, 33: c.lineTo(num(), num())
  of 34: c.quadraticCurveTo(num(), num(), num(), num())
  of 35: c.bezierCurveTo(num(), num(), num(), num(), num(), num())
  of 36: c.arc(num(), num(), small(), angle(), angle(), rand(1) == 0)
  of 37: c.arcTo(num(), num(), num(), num(), small())
  of 38: c.ellipse(num(), num(), small(), small(), angle(), angle(), angle(), rand(1) == 0)
  of 39: c.rect(num(), num(), num(), num())
  of 40: c.roundRect(num(), num(), num(), num(), small())
  of 41: c.closePath()
  of 42: c.fill(CanvasFillRule(rand(1)))
  of 43: c.stroke()
  of 44:
    if rand(5) == 0: c.clip(CanvasFillRule(rand(1)))
    else: c.fill(path2d, CanvasFillRule(rand(1)))
  of 45: c.stroke(path2d)
  of 46: c.fillRect(num(), num(), num(), num())
  of 47: c.strokeRect(num(), num(), num(), num())
  of 48: c.clearRect(num(), num(), num(), num())
  of 49: c.fillText(textToDraw(), num(), num(), if rand(3) == 0: num() else: 0.0)
  of 50: c.strokeText(textToDraw(), num(), num())
  of 51: discard c.measureText(textToDraw())
  of 52:
    case rand(2)
    of 0: c.drawImage(picture(), num(), num())
    of 1: c.drawImage(picture(), num(), num(), num(), num())
    else: c.drawImage(picture(), num(), num(), num(), num(), num(), num(), num(), num())
  of 53:
    let d = c.imageData
    if rand(1) == 0: c.putImageData(d, rand(-100 .. 400), rand(-100 .. 400))
    else: c.putImageData(d, rand(-100 .. 400), rand(-100 .. 400), rand(-20 .. 60),
                         rand(-20 .. 60), rand(-20 .. 80), rand(-20 .. 80))
  of 54: discard c.getImageData(rand(-100 .. 400), rand(-100 .. 400), rand(-10 .. 100),
                                rand(-10 .. 100))
  of 55: discard c.isPointInPath(num(), num(), CanvasFillRule(rand(1)))
  of 56: discard c.isPointInStroke(num(), num())
  of 57:
    discard c.isPointInPath(path2d, num(), num())
    discard c.isPointInStroke(path2d, num(), num())
  of 58:
    if rand(30) == 0: c.reset()
    else: discard c.getTransform
  of 59:
    pathCall(path2d)
    if rand(200) == 0: path2d = newPath2D()
  else:
    if rand(50) == 0: discard c.toBitmap
    else: c.setLineDash([rand(1 .. 9), rand(0 .. 9)])

proc newRandomCanvas(): Canvas2D =
  let w = sample([0, 1, 2, 17, 64, 200, 320, rand(-5 .. 400)])
  let h = sample([0, 1, 3, 48, 120, 240, rand(-5 .. 400)])
  let ratio = sample([1.0, 1.0, 1.0, 2.0, 3.0, 0.5, NaN, 1.5])
  newCanvas2D(w, h, ratio)

var worst = 0.0
var worstWhat = ""
let t0 = epochTime()

# ---- without a window -----------------------------------------------------------------------------

var c = newRandomCanvas()
let offscreen = rounds * 3 div 4
for i in 0 ..< offscreen:
  if i mod 400 == 0: c = newRandomCanvas()
  let s = epochTime()
  let k = c.call()
  let took = epochTime() - s
  if took > 0.05 and existsEnv("FUZZ_SLOW"):
    echo "slow: call ", i, " kind ", k, " ", formatFloat(took * 1000, ffDecimal, 1), " ms on ",
         c.pixelWidth, "x", c.pixelHeight
  if took > worst:
    worst = took
    worstWhat = "call " & $i & " on " & $c.pixelWidth & "x" & $c.pixelHeight
  doAssert took < 3.0, "call " & $i & " took " & $took & "s"
  if i mod 2000 == 0:
    let b = c.toBitmap
    doAssert b.w == c.pixelWidth and b.h == c.pixelHeight
    doAssert c.pixelWidth <= 8192 and c.pixelWidth * c.pixelHeight <= 16_777_216

# ---- in a window -----------------------------------------------------------------------------------

fakeDriver()
startApp("fuzz canvas", W, H)
var calls = 0
var r: Rect
var retained = false
var size = (300, 200)
view = proc () =
  canvas2dWith(ctx, size[0], size[1], CanvasOptions(key: "fuzz", retained: retained,
                                                    focusable: true,
                                                    captureWheel: rand(1) == 0)):
    for _ in 0 ..< rand(0 .. 12):
      ctx.call()
      inc calls
    discard ctx.input
  r = ui.lastRect
  label "below"
let inWindow = rounds - offscreen
var frames = 0
while calls < inWindow:
  case rand(9)
  of 0: down(r.x + rand(-20 .. r.w + 20), r.y + rand(-20 .. r.h + 20), clicks = rand(1 .. 2))
  of 1: up(r.x + rand(-20 .. r.w + 20), r.y + rand(-20 .. r.h + 20))
  of 2: move(r.x + rand(-20 .. r.w + 20), r.y + rand(-20 .. r.h + 20))
  of 3: queue.add Event(kind: MouseWheelEvent, y: rand(-3 .. 3))
  of 4:
    # (not Esc on a touch screen: that is the phone's back button, which
    # would end the app)
    key(sample([KeyA, KeyLeft, KeyTab, KeyEnter]))
    if not ui.touch and rand(3) == 0: key(KeyEsc)
  of 5: typeText("q")
  of 6:
    if rand(20) == 0: retained = not retained
    if rand(30) == 0: size = (rand(-5 .. 500), rand(-5 .. 400))
    if rand(10) == 0: ui.touch = not ui.touch
  else: discard
  let s = epochTime()
  run()
  inc frames
  doAssert ui.running, "the app was closed"
  doAssert epochTime() - s < 5.0, "a frame took " & $(epochTime() - s)

echo "canvas2d fuzz: ", rounds, " calls (", offscreen, " offscreen, ", calls,
     " in ", frames, " frames) in ", formatFloat(epochTime() - t0, ffDecimal, 1),
     " s; slowest call ", formatFloat(worst * 1000, ffDecimal, 1), " ms (", worstWhat, ")"
