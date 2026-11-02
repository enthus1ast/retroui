## The HTML5-style canvas (retro/canvas2d): shapes, anti-aliasing, lines,
## joins, caps and dashes, transforms, clipping, colors, gradients and
## patterns, alpha and compositing, shadows, text, pictures, image data,
## hit tests, bad input, and the canvas in a window with the mouse, fingers
## and keys -- headless.

import std/[math, times, strutils]
import retro
import retro/canvas2d
import retro/uirelays/input
import harness

type Rgba = tuple[r, g, b, a: int]

proc at(c: Canvas2D; x, y: int): Rgba =
  ## One pixel of the canvas (its own pixels), not premultiplied.
  let d = c.getImageData(x, y, 1, 1)
  (int(d.data[0]), int(d.data[1]), int(d.data[2]), int(d.data[3]))

proc near(p: Rgba; q: Rgba; tol = 2): bool =
  abs(p.r - q.r) <= tol and abs(p.g - q.g) <= tol and abs(p.b - q.b) <= tol and
    abs(p.a - q.a) <= tol

proc alphaSum(c: Canvas2D): float =
  let d = c.getImageData(0, 0, c.pixelWidth, c.pixelHeight)
  for i in 0 ..< d.width * d.height: result += float(d.data[i * 4 + 3]) / 255

proc inked(c: Canvas2D; x0, y0, x1, y1: int): int =
  ## How many pixels in the box are not transparent.
  for y in y0 ..< y1:
    for x in x0 ..< x1:
      if c.at(x, y).a > 0: inc result

const red: Rgba = (255, 0, 0, 255)
const clear: Rgba = (0, 0, 0, 0)

# ---- colors ------------------------------------------------------------------------------------

block colors:
  var u: uint32
  doAssert parseColor("#f00", u) and u == 0xFFFF0000'u32
  doAssert parseColor("#FF000080", u) and u == 0x80FF0000'u32
  doAssert parseColor("#0f08", u) and u == 0x8800FF00'u32
  doAssert parseColor("rgb(1, 2, 3)", u) and u == 0xFF010203'u32
  doAssert parseColor("rgba(255,0,0,0.5)", u) and (u shr 24) in 127'u32 .. 128'u32
  doAssert parseColor("hsl(120, 100%, 50%)", u) and (u and 0xFFFFFF) == 0x00FF00
  doAssert parseColor("Navy", u) and u == 0xFF000080'u32
  doAssert parseColor("transparent", u) and u == 0
  for bad in ["", "#", "#12", "#12345", "rgb(", "nosuchcolor", "rgb(a,b,c)", "#ggg",
              "hsl()", "\xFF\xFE", "rgba(1,2,3,4,5,6)"]:
    doAssert not parseColor(bad, u), bad
  let c = newCanvas2D(10, 10)
  c.fillStyle = "blue"
  c.fillStyle = "not a color"        # ignored, as in the browser
  doAssert c.fillStyle == "#0000ff", c.fillStyle
  c.fillStyle = "rgba(0, 0, 0, 0.5)"
  doAssert c.fillStyle.startsWith("rgba("), c.fillStyle

# ---- rectangles and anti-aliasing ------------------------------------------------------------------

block rects:
  let c = newCanvas2D(100, 100)
  doAssert c.width == 100 and c.pixelWidth == 100 and c.at(0, 0) == clear
  c.fillStyle = "red"
  c.fillRect(10, 10, 20, 20)
  doAssert c.at(15, 15) == red and c.at(10, 10) == red and c.at(29, 29) == red
  doAssert c.at(9, 15) == clear and c.at(30, 15) == clear and c.at(15, 30) == clear
  # half a pixel is half covered
  c.fillRect(50.5, 50, 10, 10)
  let e = c.at(50, 55)
  doAssert e.a in 120 .. 136 and e.r == 255, $e
  doAssert c.at(51, 55) == red and c.at(60, 55).a in 120 .. 136
  # negative sizes go the other way
  c.fillRect(80, 80, -5, -5)
  doAssert c.at(77, 77) == red
  # clearRect makes them transparent; strokeRect draws the edge only
  c.clearRect(0, 0, 100, 100)
  doAssert c.alphaSum == 0
  c.strokeStyle = "black"
  c.lineWidth = 2
  c.strokeRect(20, 20, 40, 40)
  doAssert c.at(20, 40).a == 255 and c.at(40, 40) == clear and c.at(59, 40).a == 255

block circleArea:
  let c = newCanvas2D(100, 100)
  c.fillStyle = "black"
  c.beginPath()
  c.arc(50, 50, 30, 0, 2 * PI)
  c.fill()
  let area = c.alphaSum
  doAssert abs(area - PI * 900) < PI * 900 * 0.01, $area
  doAssert c.at(50, 50).a == 255 and c.at(50, 19).a < 40 and c.at(85, 50) == clear
  # an ellipse, rotated a quarter turn
  c.clearRect(0, 0, 100, 100)
  c.beginPath()
  c.ellipse(50, 50, 40, 10, PI / 2, 0, 2 * PI)
  c.fill()
  doAssert c.at(50, 85).a == 255 and c.at(85, 50) == clear
  doAssert abs(c.alphaSum - PI * 400) < PI * 400 * 0.02

block fillRules:
  let c = newCanvas2D(100, 100)
  c.fillStyle = "black"
  c.beginPath()
  c.rect(10, 10, 80, 80)
  c.rect(30, 30, 40, 40)          # the same way round: nonzero fills the middle
  c.fill()
  doAssert c.at(50, 50).a == 255
  c.clearRect(0, 0, 100, 100)
  c.fill(frEvenOdd)
  doAssert c.at(50, 50) == clear and c.at(20, 20).a == 255
  c.clearRect(0, 0, 100, 100)
  c.fill("evenodd".parseEnum[:CanvasFillRule])
  doAssert c.at(50, 50) == clear

block curves:
  let c = newCanvas2D(120, 120)
  c.fillStyle = "black"
  c.beginPath()
  c.moveTo(10, 100)
  c.quadraticCurveTo(60, -40, 110, 100)
  c.closePath()
  c.fill()
  doAssert c.at(60, 50).a == 255 and c.at(60, 20) == clear and c.at(60, 99).a == 255
  c.clearRect(0, 0, 120, 120)
  c.beginPath()
  c.moveTo(10, 60)
  c.bezierCurveTo(10, 0, 110, 0, 110, 60)
  c.bezierCurveTo(110, 120, 10, 120, 10, 60)
  c.fill()
  doAssert c.at(60, 60).a == 255 and c.at(2, 60) == clear
  # roundRect: the corner is cut off
  c.clearRect(0, 0, 120, 120)
  c.beginPath()
  c.roundRect(10, 10, 100, 100, 30)
  c.fill()
  doAssert c.at(12, 12) == clear and c.at(60, 12).a == 255 and c.at(60, 60).a == 255
  c.clearRect(0, 0, 120, 120)
  c.beginPath()
  c.roundRect(10, 10, 100, 100, [0.0, 30.0])     # top-left square, top-right round
  c.fill()
  doAssert c.at(11, 11).a == 255 and c.at(108, 11) == clear
  # arcTo makes a rounded corner
  c.clearRect(0, 0, 120, 120)
  c.lineWidth = 4
  c.beginPath()
  c.moveTo(10, 10)
  c.arcTo(100, 10, 100, 100, 40)
  c.lineTo(100, 100)
  c.stroke()
  doAssert c.at(40, 10).a > 0 and c.at(98, 12) == clear and c.at(100, 80).a > 0

# ---- lines -------------------------------------------------------------------------------------------

block lineCaps:
  let c = newCanvas2D(100, 100)
  c.strokeStyle = "black"
  c.lineWidth = 6
  c.beginPath()
  c.moveTo(20, 50)
  c.lineTo(80, 50)
  c.stroke()
  doAssert c.at(50, 48).a == 255 and c.at(50, 52).a == 255 and c.at(50, 54) == clear
  doAssert c.at(19, 50) == clear and c.at(80, 50) == clear, "butt: no further than the ends"
  c.clearRect(0, 0, 100, 100)
  c.lineCap = lcSquare
  c.stroke()
  doAssert c.at(18, 48).a == 255 and c.at(81, 52).a == 255
  c.clearRect(0, 0, 100, 100)
  c.lineCap = "round"
  doAssert c.lineCap == lcRound
  c.stroke()
  doAssert c.at(18, 50).a > 200 and c.at(17, 47).a < 100, "round: no corners"
  # a dot: a zero-length line with round caps
  c.clearRect(0, 0, 100, 100)
  c.beginPath()
  c.moveTo(50, 20)
  c.lineTo(50, 20)
  c.stroke()
  doAssert c.at(50, 20).a == 255

block lineJoins:
  proc v(join: CanvasLineJoin): Canvas2D =
    result = newCanvas2D(100, 100)
    result.lineWidth = 10
    result.lineJoin = join
    result.beginPath()
    result.moveTo(20, 80)
    result.lineTo(50, 20)
    result.lineTo(80, 80)
    result.stroke()
  let m = v(ljMiter)
  let r = v(ljRound)
  let b = v(ljBevel)
  # the miter's tip goes up to ~y 8.8, the round join to y 15, the bevel to ~17.8
  doAssert m.at(50, 11).a == 255 and r.at(50, 11) == clear and b.at(50, 11) == clear
  doAssert r.at(50, 16).a == 255 and b.at(50, 16) == clear
  doAssert b.at(50, 19).a > 0
  # a sharp corner past the miter limit is beveled
  m.miterLimit = 1
  m.clearRect(0, 0, 100, 100)
  m.stroke()
  doAssert m.at(50, 11) == clear
  # the inside of a thick line has no holes or doubled alpha
  let t = newCanvas2D(100, 100)
  t.strokeStyle = "rgba(0, 0, 0, 0.5)"
  t.lineWidth = 20
  t.beginPath()
  t.moveTo(10, 90)
  t.lineTo(50, 30)
  t.lineTo(90, 90)
  t.stroke()
  doAssert t.at(50, 40).a in 126 .. 129, "the overlap at the join is drawn once: " & $t.at(50, 40)
  doAssert t.at(50, 25).a in 126 .. 129

block dashes:
  let c = newCanvas2D(100, 20)
  c.lineWidth = 2
  c.setLineDash([10.0, 10.0])
  doAssert c.getLineDash == @[10.0, 10.0]
  c.beginPath()
  c.moveTo(0, 10)
  c.lineTo(100, 10)
  c.stroke()
  doAssert c.at(5, 10).a == 255 and c.at(15, 10) == clear and c.at(25, 10).a == 255
  c.clearRect(0, 0, 100, 20)
  c.lineDashOffset = 10
  c.stroke()
  doAssert c.at(5, 10) == clear and c.at(15, 10).a == 255
  # an odd count repeats the list; negative or non-finite lists are ignored
  c.setLineDash([5.0])
  doAssert c.getLineDash == @[5.0, 5.0]
  c.setLineDash([1.0, -1.0])
  doAssert c.getLineDash == @[5.0, 5.0]
  c.setLineDash([NaN, 1.0])
  doAssert c.getLineDash == @[5.0, 5.0]
  c.setLineDash(newSeq[float]())
  doAssert c.getLineDash.len == 0
  # dashes along a curve
  c.clearRect(0, 0, 100, 20)
  c.setLineDash([4, 4])
  c.beginPath()
  c.arc(50, 50, 45, PI, 2 * PI)
  c.stroke()
  doAssert c.alphaSum > 10

# ---- transforms, save and restore, clipping ------------------------------------------------------------

block transforms:
  let c = newCanvas2D(100, 100)
  c.fillStyle = "black"
  c.translate(50, 50)
  c.rotate(PI / 2)
  c.fillRect(0, 0, 20, 5)            # now 5 wide to the left, 20 down
  doAssert c.at(47, 60).a == 255 and c.at(60, 47) == clear
  let m = c.getTransform
  doAssert abs(m.a) < 1e-9 and abs(m.b - 1) < 1e-9 and m.e == 50 and m.f == 50
  c.resetTransform()
  doAssert c.getTransform == DOMMatrix(a: 1, d: 1)
  c.setTransform(2, 0, 0, 2, 0, 0)
  c.fillRect(0, 0, 5, 5)
  doAssert c.at(9, 9).a == 255 and c.at(11, 11) == clear
  c.transform(1, 0, 0, 1, 10, 0)       # after the scale: 20 pixels
  doAssert c.getTransform.e == 20
  # save / restore keep the transform and the styles
  c.resetTransform()
  c.fillStyle = "red"
  c.lineWidth = 3
  c.save()
  c.translate(5, 5)
  c.fillStyle = "blue"
  c.lineWidth = 9
  c.globalAlpha = 0.2
  c.restore()
  doAssert c.fillStyle == "#ff0000" and c.lineWidth == 3 and c.globalAlpha == 1
  doAssert c.getTransform.e == 0
  c.restore()                          # nothing saved: nothing happens
  # the path keeps the transform it was made with
  c.clearRect(0, 0, 100, 100)
  c.beginPath()
  c.translate(50, 0)
  c.rect(0, 0, 10, 10)
  c.resetTransform()
  c.fill()
  doAssert c.at(55, 5).a == 255 and c.at(5, 5) == clear

block clipping:
  let c = newCanvas2D(100, 100)
  c.save()
  c.beginPath()
  c.rect(0, 0, 50, 100)
  c.clip()
  c.fillStyle = "red"
  c.fillRect(0, 0, 100, 100)
  doAssert c.at(25, 50) == red and c.at(75, 50) == clear
  # clips add up
  c.beginPath()
  c.arc(50, 50, 20, 0, 2 * PI)
  c.clip()
  c.fillStyle = "blue"
  c.fillRect(0, 0, 100, 100)
  doAssert c.at(40, 50).b == 255 and c.at(60, 50) == clear and c.at(10, 10) == red
  c.restore()
  c.fillStyle = "lime"
  c.fillRect(90, 90, 10, 10)
  doAssert c.at(95, 95).g == 255, "restore drops the clip"
  # a Path2D as the clip, even-odd
  let p = newPath2D()
  p.rect(0, 0, 100, 100)
  p.rect(25, 25, 50, 50)
  c.clearRect(0, 0, 100, 100)
  c.clip(p, frEvenOdd)
  c.fillRect(0, 0, 100, 100)
  doAssert c.at(50, 50) == clear and c.at(10, 50).a == 255

# ---- paint: colors, gradients, patterns, alpha, compositing, shadows -------------------------------

block gradients:
  let c = newCanvas2D(101, 10)
  let g = c.createLinearGradient(0, 0, 100, 0)
  g.addColorStop(0, "black")
  g.addColorStop(1, "white")
  c.fillStyle = g
  c.fillRect(0, 0, 101, 10)
  doAssert c.at(0, 5).r < 4 and c.at(100, 5).r > 251
  doAssert abs(c.at(50, 5).r - 128) <= 3, $c.at(50, 5)
  # past the ends: the end colors
  let h = c.createLinearGradient(40, 0, 60, 0)
  h.addColorStop(0, "red")
  h.addColorStop(1, color(0, 0, 255))
  c.fillStyle = h
  c.fillRect(0, 0, 101, 10)
  doAssert c.at(5, 5) == red and c.at(95, 5) == (0, 0, 255, 255)
  # bad stops are ignored
  h.addColorStop(NaN, "red")
  h.addColorStop(2, "red")
  h.addColorStop(0.5, "nonsense")
  # radial: the middle is the first color
  let r = newCanvas2D(100, 100)
  let rg = r.createRadialGradient(50, 50, 0, 50, 50, 50)
  rg.addColorStop(0, "white")
  rg.addColorStop(1, "black")
  r.fillStyle = rg
  r.fillRect(0, 0, 100, 100)
  doAssert r.at(50, 50).r > 250 and r.at(50, 1).r < 10 and abs(r.at(75, 50).r - 128) < 8
  # conic: goes round
  let cg = r.createConicGradient(0, 50, 50)
  cg.addColorStop(0, "red")
  cg.addColorStop(0.5, "blue")
  cg.addColorStop(1, "red")
  r.fillStyle = cg
  r.fillRect(0, 0, 100, 100)
  doAssert r.at(10, 51).b > 200, "half way round is blue: " & $r.at(10, 51)
  doAssert r.at(90, 52).r > 200
  # a gradient for lines
  r.strokeStyle = g
  r.lineWidth = 4
  r.strokeRect(10, 10, 80, 80)

block patterns:
  let img = newBitmap(2, 2)
  img.px[0] = 0xFFFF0000'u32
  img.px[1] = 0xFF0000FF'u32
  img.px[2] = 0xFF0000FF'u32
  img.px[3] = 0xFFFF0000'u32
  let c = newCanvas2D(20, 20)
  c.fillStyle = c.createPattern(img, "repeat")
  c.fillRect(0, 0, 20, 20)
  doAssert c.at(0, 0) == red and c.at(1, 0).b == 255 and c.at(2, 0) == red and c.at(3, 1) == red
  c.clearRect(0, 0, 20, 20)
  c.fillStyle = c.createPattern(img, "no-repeat")
  c.fillRect(0, 0, 20, 20)
  doAssert c.at(0, 0) == red and c.at(5, 5) == clear
  c.clearRect(0, 0, 20, 20)
  c.fillStyle = c.createPattern(img, "repeat-x")
  c.fillRect(0, 0, 20, 20)
  doAssert c.at(10, 0) == red and c.at(10, 5) == clear
  doAssert c.createPattern(nil) == nil

block alphaAndCompositing:
  let c = newCanvas2D(10, 10)
  c.fillStyle = "white"
  c.fillRect(0, 0, 10, 10)
  c.globalAlpha = 0.5
  c.fillStyle = "red"
  c.fillRect(0, 0, 10, 10)
  doAssert c.at(5, 5).near((255, 128, 128, 255)), $c.at(5, 5)
  c.globalAlpha = 7      # out of range: ignored
  doAssert c.globalAlpha == 0.5
  c.globalAlpha = 1
  # destination-out cuts a hole
  c.globalCompositeOperation = "destination-out"
  doAssert c.globalCompositeOperation == coDestinationOut
  c.fillRect(0, 0, 5, 10)
  doAssert c.at(2, 5) == clear and c.at(7, 5).a == 255
  # copy: only the new drawing is left
  c.globalCompositeOperation = coCopy
  c.fillStyle = "blue"
  c.fillRect(0, 0, 2, 2)
  doAssert c.at(1, 1).b == 255 and c.at(7, 7) == clear
  # multiply
  c.globalCompositeOperation = coSourceOver
  c.fillStyle = "rgb(200, 100, 50)"
  c.fillRect(0, 0, 10, 10)
  c.globalCompositeOperation = "multiply"
  c.fillStyle = "rgb(128, 128, 128)"
  c.fillRect(0, 0, 10, 10)
  doAssert c.at(5, 5).near((100, 50, 25, 255), 3), $c.at(5, 5)
  # destination-over draws behind; source-in keeps only the overlap
  c.globalCompositeOperation = coCopy
  c.fillStyle = "red"
  c.fillRect(0, 0, 5, 10)
  c.globalCompositeOperation = coDestinationOver
  c.fillStyle = "blue"
  c.fillRect(0, 0, 10, 10)
  doAssert c.at(2, 5) == red and c.at(7, 5).b == 255
  c.globalCompositeOperation = coCopy
  c.fillStyle = "red"
  c.fillRect(0, 0, 5, 10)
  c.globalCompositeOperation = coSourceIn
  c.fillStyle = "lime"
  c.fillRect(0, 0, 10, 10)
  doAssert c.at(2, 5) == (0, 255, 0, 255) and c.at(7, 5) == clear
  c.globalCompositeOperation = "no-such-op"
  doAssert c.globalCompositeOperation == coSourceIn

block shadows:
  let c = newCanvas2D(60, 60)
  c.shadowColor = "black"
  c.shadowOffsetX = 10
  c.shadowOffsetY = 10
  c.fillStyle = "red"
  c.fillRect(10, 10, 20, 20)
  doAssert c.at(15, 15) == red and c.at(35, 35).a == 255 and c.at(35, 35).r == 0
  doAssert c.at(5, 5) == clear
  c.clearRect(0, 0, 60, 60)
  c.shadowBlur = 8
  c.fillRect(10, 10, 20, 20)
  let s = c.at(42, 25).a
  doAssert s > 0 and s < 200, "a blurred shadow fades out: " & $s
  # a shape off the canvas still casts its shadow on it
  c.clearRect(0, 0, 60, 60)
  c.shadowBlur = 0
  c.shadowOffsetX = 30
  c.shadowOffsetY = 0
  c.fillRect(-20, 10, 15, 10)
  doAssert c.at(15, 15) == (0, 0, 0, 255) and c.at(2, 15) == clear and c.at(26, 15) == clear
  # no shadow with a transparent color
  c.clearRect(0, 0, 60, 60)
  c.shadowColor = "transparent"
  c.fillRect(10, 10, 20, 20)
  doAssert c.at(35, 35) == clear

# ---- text ----------------------------------------------------------------------------------------

block text:
  let c = newCanvas2D(300, 100)
  c.font = "20px sans-serif"
  doAssert c.font == "20px sans-serif"
  let m = c.measureText("Hello")
  doAssert m.width > 30 and m.width < 80, $m.width
  c.font = "40px sans-serif"
  let m2 = c.measureText("Hello")
  doAssert abs(m2.width - 2 * m.width) < 2, $m2.width & " " & $m.width
  doAssert m2.actualBoundingBoxAscent > 20 and m2.fontBoundingBoxAscent > 0
  doAssert c.measureText("").width == 0
  c.fillStyle = "black"
  c.fillText("Hello", 10, 50)
  doAssert c.inked(10, 15, 10 + int(m2.width), 51) > 100
  doAssert c.inked(0, 60, 300, 100) == 0, "alphabetic: nothing well below the line"
  # center and top
  c.clearRect(0, 0, 300, 100)
  c.textAlign = "center"
  c.textBaseline = tbTop
  c.fillText("Hello", 150, 10)
  doAssert c.inked(0, 0, 300, 9) == 0, "top: below y"
  let left = c.inked(0, 0, 150, 100)
  let right = c.inked(150, 0, 300, 100)
  doAssert left > 50 and right > 50 and abs(left - right) < (left + right) div 4,
           "centered: " & $left & " " & $right
  # right aligned ends at x
  c.clearRect(0, 0, 300, 100)
  c.textAlign = taRight
  c.fillText("Hello", 150, 10)
  doAssert c.inked(152, 0, 300, 100) == 0 and c.inked(0, 0, 150, 100) > 100
  # maxWidth squeezes it
  c.clearRect(0, 0, 300, 100)
  c.textAlign = taLeft
  c.fillText("Hello world, a long text", 0, 10, 100)
  doAssert c.inked(102, 0, 300, 100) == 0
  # bold, Arabic, rotated, outlined
  c.font = "bold 24px sans-serif"
  c.fillText("مرحبا", 10, 50)
  c.rotate(0.3)
  c.fillText("Turn", 100, 10)
  c.strokeText("Edge", 200, 10)
  c.font = "garbage"            # ignored
  doAssert c.font == "bold 24px sans-serif"

# ---- pictures and image data ---------------------------------------------------------------------

block drawImage:
  let img = newBitmap(2, 2)
  img.px[0] = 0xFFFF0000'u32
  img.px[1] = 0xFF00FF00'u32
  img.px[2] = 0xFF0000FF'u32
  img.px[3] = 0xFFFFFFFF'u32
  let c = newCanvas2D(40, 40)
  c.drawImage(img, 0, 0)
  doAssert c.at(0, 0) == red and c.at(1, 0) == (0, 255, 0, 255) and c.at(2, 2) == clear
  c.imageSmoothingEnabled = false
  c.drawImage(img, 0, 0, 20, 20)
  doAssert c.at(4, 4) == red and c.at(15, 4) == (0, 255, 0, 255) and
           c.at(4, 15) == (0, 0, 255, 255) and c.at(15, 15) == (255, 255, 255, 255)
  # a part of it
  c.clearRect(0, 0, 40, 40)
  c.drawImage(img, 1, 1, 1, 1, 20, 20, 10, 10)
  doAssert c.at(25, 25) == (255, 255, 255, 255) and c.at(19, 19) == clear
  # smooth scaling blends
  c.imageSmoothingEnabled = true
  c.clearRect(0, 0, 40, 40)
  c.drawImage(img, 0, 0, 40, 40)
  let mid = c.at(20, 5)
  doAssert mid.r > 40 and mid.g > 40, $mid
  # a canvas as a picture
  let other = newCanvas2D(4, 4)
  other.fillStyle = "red"
  other.fillRect(0, 0, 4, 4)
  c.drawImage(other.toBitmap, 30, 30)
  doAssert c.at(31, 31) == red
  c.drawImage(nil, 0, 0)

block imageData:
  let c = newCanvas2D(20, 20)
  let d = c.createImageData(4, 4)
  doAssert d.width == 4 and d.data.len == 64
  for i in 0 ..< 16:
    d.data[i * 4] = 10
    d.data[i * 4 + 1] = 20
    d.data[i * 4 + 2] = 30
    d.data[i * 4 + 3] = 255
  d.data[3] = 128              # one pixel half transparent
  c.translate(5, 5)            # putImageData takes no transform
  c.globalAlpha = 0.1          # nor alpha
  c.putImageData(d, 2, 2)
  doAssert c.at(3, 3) == (10, 20, 30, 255) and c.at(1, 1) == clear
  let back = c.getImageData(2, 2, 4, 4)
  doAssert back.data[4 .. 63] == d.data[4 .. 63]
  doAssert back.data[3] == 128 and abs(int(back.data[0]) - 10) <= 1
  # outside the canvas: transparent
  let o = c.getImageData(-2, -2, 4, 4)
  doAssert o.data[3] == 0 and o.data[(3 * 4 + 3) * 4 + 3] == 0
  # the dirty rectangle only
  c.clearRect(-100, -100, 1000, 1000)
  c.resetTransform()
  c.globalAlpha = 1
  c.clearRect(0, 0, 20, 20)
  c.putImageData(d, 0, 0, 2, 2, 2, 2)
  doAssert c.at(1, 1) == clear and c.at(2, 2) == (10, 20, 30, 255)
  c.putImageData(nil, 0, 0)
  # PNG
  let png = c.encodePng
  doAssert png.len > 8 and png[1 .. 3] == "PNG"
  let b = c.toBitmap
  doAssert b.w == 20 and b.h == 20

block pixelRatio:
  let c = newCanvas2D(50, 40, pixelRatio = 2)
  doAssert c.width == 50 and c.pixelWidth == 100 and c.pixelHeight == 80 and c.pixelRatio == 2
  c.fillStyle = "red"
  c.fillRect(0, 0, 10, 10)            # logical: 20 x 20 of its own pixels
  doAssert c.at(19, 19) == red and c.at(21, 21) == clear
  doAssert c.getTransform == DOMMatrix(a: 1, d: 1), "the transform is in logical pixels"
  c.beginPath()
  c.rect(10, 10, 10, 10)
  doAssert c.isPointInPath(15, 15) and not c.isPointInPath(25, 15)

# ---- hit tests and Path2D ------------------------------------------------------------------------------

block hitTests:
  let c = newCanvas2D(100, 100)
  c.beginPath()
  c.arc(50, 50, 20, 0, 2 * PI)
  doAssert c.isPointInPath(50, 50) and c.isPointInPath(65, 50) and not c.isPointInPath(75, 50)
  doAssert not c.isPointInPath(NaN, 50) and not c.isPointInPath(Inf, Inf)
  c.lineWidth = 6
  doAssert c.isPointInStroke(70, 50) and c.isPointInStroke(72, 50) and
           not c.isPointInStroke(50, 50)
  let ring = newPath2D()
  ring.rect(0, 0, 40, 40)
  ring.rect(10, 10, 20, 20)
  doAssert c.isPointInPath(ring, 5, 5) and c.isPointInPath(ring, 20, 20)
  doAssert not c.isPointInPath(ring, 20, 20, frEvenOdd)
  c.translate(50, 50)
  doAssert c.isPointInPath(ring, 55, 55) and not c.isPointInPath(ring, 5, 5),
           "a Path2D is tested with the current transform"
  doAssert c.isPointInStroke(ring, 50, 70) and not c.isPointInStroke(ring, 70, 70)
  doAssert not c.isPointInPath(nil, 1, 1)

block path2d:
  let p = newPath2D()
  p.moveTo(10, 10)
  p.lineTo(90, 10)
  p.lineTo(50, 90)
  p.closePath()
  let a = newCanvas2D(100, 100)
  a.fill(p)
  let b = newCanvas2D(100, 100)
  b.beginPath()
  b.moveTo(10, 10)
  b.lineTo(90, 10)
  b.lineTo(50, 90)
  b.closePath()
  b.fill()
  doAssert a.getImageData(0, 0, 100, 100).data == b.getImageData(0, 0, 100, 100).data
  # added to another path, again and again
  let q = newPath2D()
  q.addPath(p)
  q.addPath(nil)
  q.arc(50, 50, 5, 0, 2 * PI)
  q.ellipse(10, 10, 3, 2, 0, 0, 2 * PI)
  q.quadraticCurveTo(1, 1, 2, 2)
  q.bezierCurveTo(1, 1, 2, 2, 3, 3)
  q.arcTo(1, 1, 5, 5, 2)
  q.roundRect(0, 0, 10, 10, 2)
  q.rect(1, 1, 2, 2)
  a.stroke(q)
  a.clip(q)
  a.stroke(p)

# ---- bad input ---------------------------------------------------------------------------------------

block hostile:
  let c = newCanvas2D(64, 64)
  let before = c.getImageData(0, 0, 64, 64).data
  # non-finite numbers are ignored (as in the browser)
  c.fillRect(NaN, 0, 10, 10)
  c.fillRect(0, Inf, 10, 10)
  c.translate(NaN, 1)
  c.scale(Inf, 1)
  c.rotate(-Inf)
  c.lineWidth = NaN
  c.lineWidth = -1
  c.lineWidth = 0
  doAssert c.lineWidth == 1
  c.beginPath()
  c.moveTo(NaN, NaN)
  c.lineTo(Inf, 0)
  c.arc(10, 10, -5, 0, 1)            # negative radius: ignored
  c.ellipse(10, 10, -1, 2, 0, 0, 1)
  c.fill()
  c.stroke()
  doAssert c.getImageData(0, 0, 64, 64).data == before
  doAssert c.getTransform == DOMMatrix(a: 1, d: 1)
  # huge numbers do not hang or crash
  let t0 = epochTime()
  c.beginPath()
  c.moveTo(-1e300, -1e300)
  c.lineTo(1e300, 5)
  c.lineTo(5, 1e300)
  c.bezierCurveTo(1e200, -1e200, -1e200, 1e200, 3, 3)
  c.arc(0, 0, 1e30, 0, 1e9)
  c.ellipse(0, 0, 1e300, 1e-300, 1e10, -1e10, 1e10)
  c.fill()
  c.lineWidth = 1e9
  c.stroke()
  c.lineWidth = 1e-9
  c.setLineDash([1e-9, 1e-9])
  c.stroke()
  c.setLineDash([1e300, 1])
  c.stroke()
  c.setLineDash(newSeq[float]())
  c.scale(1e-300, 1e-300)            # a transform that cannot be undone
  c.lineWidth = 5
  c.stroke()
  c.resetTransform()
  c.scale(1e300, 1e300)
  c.fillRect(0, 0, 1, 1)
  c.resetTransform()
  c.shadowBlur = 1e9
  c.shadowColor = "red"
  c.fillRect(0, 0, 10, 10)
  c.shadowBlur = 0
  c.font = "100000px sans-serif"
  c.fillText("x", 0, 0)
  c.font = "0px sans-serif"
  c.fillText("x", 0, 0)
  c.fillText("x".repeat(100_000), 0, 30)
  c.fillText("\xFF\xFE\x00bad utf-8", 0, 30)
  c.drawImage(newBitmap(1, 1), 0, 0, 1e300, 1e300)
  c.drawImage(newBitmap(1, 1), 0, 0, 0, 0)
  c.drawImage(newBitmap(4, 4), -1e300, 0, 1e300, 1e300, 0, 0, 10, 10)
  discard c.getImageData(1_000_000, 1_000_000, 10, 10)
  discard c.getImageData(0, 0, -5, -5)
  discard c.getImageData(0, 0, 100_000, 100_000)
  c.putImageData(ImageData(width: 100, height: 100, data: @[]), 0, 0)    # too short
  c.putImageData(c.createImageData(10, 10), high(int) div 2, low(int) div 2)
  c.arc(0, 0, 10, 0, 2 * PI, true)
  c.setTransform(DOMMatrix(a: NaN, d: 1))
  doAssert epochTime() - t0 < 5.0, "hostile numbers took " & $(epochTime() - t0)
  # a deep save stack is capped
  for i in 0 ..< 10_000: c.save()
  for i in 0 ..< 10_100: c.restore()
  # many points
  c.beginPath()
  for i in 0 ..< 100_000: c.lineTo(float(i mod 64), float((i * 7) mod 64))
  c.fill()
  c.stroke()
  # sizes: huge ones are capped, zero and negative ones are empty
  let big = newCanvas2D(100_000, 100_000)
  doAssert big.pixelWidth <= 8192 and big.pixelWidth * big.pixelHeight <= 16_777_216
  big.fillRect(0, 0, 1e9, 1e9)
  let empty = newCanvas2D(0, -5)
  empty.fillRect(0, 0, 10, 10)
  empty.stroke()
  discard empty.getImageData(0, 0, 1, 1)
  discard empty.toBitmap
  let r = newCanvas2D(10, 10, pixelRatio = NaN)
  doAssert r.pixelRatio == 1
  let r2 = newCanvas2D(10, 10, pixelRatio = 1e9)
  doAssert r2.pixelWidth <= 8192
  c.reset()
  doAssert c.alphaSum == 0 and c.fillStyle == "#000000"

# ---- speed --------------------------------------------------------------------------------------------

block speed:
  let c = newCanvas2D(800, 600)
  var best = 1e9
  for round in 0 ..< 3:
    let t0 = cpuTime()
    c.fillStyle = "white"
    c.fillRect(0, 0, 800, 600)
    c.lineWidth = 2
    for i in 0 ..< 1000:
      let x = float((i * 97) mod 760)
      let y = float((i * 61) mod 560)
      c.fillStyle = (if i mod 2 == 0: "rgba(0, 0, 128, 0.6)" else: "orange")
      c.strokeStyle = "black"
      c.beginPath()
      if i mod 3 == 0: c.arc(x + 20, y + 20, 18, 0, 2 * PI)
      elif i mod 3 == 1: c.roundRect(x, y, 40, 30, 6)
      else:
        c.moveTo(x, y + 40)
        c.lineTo(x + 20, y)
        c.lineTo(x + 40, y + 40)
        c.closePath()
      c.fill()
      c.stroke()
    best = min(best, cpuTime() - t0)
  echo "1000 filled and stroked shapes on 800x600: ", formatFloat(best * 1000, ffDecimal, 1), " ms"
  # a generous bound: debug builds and sanitizers are several times slower
  const limit = when defined(release) or defined(danger): 0.25 else: 1.5
  doAssert best < limit, "far too slow: " & $best

# ---- in a window ---------------------------------------------------------------------------------------

fakeDriver()
startApp("canvas", W, H)

block immediateMode:
  var color = "red"
  var r: Rect
  var cv: Canvas2D
  view = proc () =
    canvas2d(ctx, 200, 100):
      ctx.fillStyle = color
      ctx.fillRect(0, 0, 200, 100)
      ctx.fillStyle = "white"
      ctx.beginPath()
      ctx.arc(100, 50, 30, 0, 2 * PI)
      ctx.fill()
      cv = ctx
    r = ui.lastRect
  run(3)
  doAssert r.w == 200 and r.h == 100, $r
  doAssert px(r.x + 5, r.y + 5) == 0xFF0000 and px(r.x + 100, r.y + 50) == 0xFFFFFF
  let n = cv.timesRasterized
  run(10)
  doAssert cv.timesRasterized == n, "the same drawing is not rasterized again"
  color = "blue"
  run(2)
  doAssert cv.timesRasterized == n + 1 and px(r.x + 5, r.y + 5) == 0x0000FF
  # a full-width canvas
  view = proc () =
    canvas2d(ctx, -1, 50):
      ctx.fillStyle = "lime"
      ctx.fillRect(0, 0, ctx.width, ctx.height)
    r = ui.lastRect
  run(2)
  doAssert r.w > 400 and px(r.x + r.w - 2, r.y + 2) == 0x00FF00

block immediateClipAndImageData:
  var r: Rect
  var mid: Rgba
  view = proc () =
    canvas2dWith(ctx, 100, 100, CanvasOptions(key: "clipped")):
      ctx.beginPath()
      ctx.rect(0, 0, 50, 100)
      ctx.clip()
      ctx.fillStyle = "red"
      ctx.fillRect(0, 0, 100, 100)
      mid = ctx.at(25, 50)                # read in the middle of the frame
      ctx.fillStyle = "blue"
      ctx.fillRect(0, 50, 100, 50)        # still clipped after it
    r = ui.lastRect
  run(3)
  doAssert mid == red
  doAssert px(r.x + 25, r.y + 25) == 0xFF0000 and px(r.x + 75, r.y + 25) != 0xFF0000
  doAssert px(r.x + 25, r.y + 75) == 0x0000FF and px(r.x + 75, r.y + 75) != 0x0000FF

block retainedMode:
  var frames = 0
  var r: Rect
  view = proc () =
    canvas2dWith(ctx, 100, 100, CanvasOptions(retained: true, key: "keep")):
      if frames == 0:
        ctx.fillStyle = "navy"
        ctx.fillRect(0, 0, 50, 50)
      if frames == 3:
        ctx.fillStyle = "red"
        ctx.fillRect(50, 50, 50, 50)
      inc frames
    r = ui.lastRect
  run(6)
  doAssert px(r.x + 10, r.y + 10) == 0x000080, "what was drawn stays"
  doAssert px(r.x + 60, r.y + 60) == 0xFF0000

template seen(inp: seq[CanvasInput]; cond: untyped): bool =
  ## Some frame's input matched `cond` (about `it`).
  var found = false
  for it {.inject.} in inp:
    if cond: found = true
  found

block mouseInput:
  var inp: seq[CanvasInput]
  var r: Rect
  view = proc () =
    canvas2dWith(ctx, 200, 150, CanvasOptions(key: "in", focusable: true)):
      inp.add ctx.input
      ctx.fillStyle = "white"
      ctx.fillRect(0, 0, 200, 150)
    r = ui.lastRect
    discard button("Other")
  run(2)
  inp.setLen(0)
  down(r.x + 20, r.y + 30)
  run()
  doAssert inp.seen(it.pressed and it.down and it.x == 20 and it.y == 30 and it.over and
                    not it.finger), $inp
  doAssert inp[^1].down and not inp[^1].pressed, "pressed is for one frame"
  inp.setLen(0)
  for i in 1 .. 3:
    move(r.x + 20 + i * 10, r.y + 30 + i * 5)
    run()
  doAssert inp.seen(it.dragging and it.dx == 10 and it.dy == 5), $inp
  # leaving the canvas while held keeps reporting (outside coordinates)
  move(r.x + 300, r.y + 30)
  run()
  doAssert inp[^1].down and inp[^1].x == 300 and not inp[^1].over
  inp.setLen(0)
  up(r.x + 300, r.y + 30)
  run()
  doAssert inp.seen(it.released and not it.clicked and not it.down) and not inp[^1].down
  # a click; a double click
  inp.setLen(0)
  down(r.x + 50, r.y + 50)
  run()
  up(r.x + 50, r.y + 50)
  run()
  doAssert inp.seen(it.clicked and it.released) and inp[^1].focused
  doAssert not inp.seen(it.dragging), "a click is no drag"
  inp.setLen(0)
  down(r.x + 50, r.y + 50, clicks = 2)
  run()
  doAssert inp.seen(it.doubleClicked)
  up(r.x + 50, r.y + 50)
  run()
  # keys while it has the keyboard
  inp.setLen(0)
  key(KeyLeft, {ShiftPressed})
  run()
  doAssert inp.seen(it.key == KeyLeft and ShiftPressed in it.mods)
  inp.setLen(0)
  typeText("ab")
  run()
  var typed = ""
  for i in inp: typed.add i.typed
  doAssert typed == "ab", typed
  # the wheel; a right click
  inp.setLen(0)
  move(r.x + 50, r.y + 50)
  queue.add Event(kind: MouseWheelEvent, y: 1)
  run()
  var wheel = 0
  for i in inp: wheel += i.wheel
  doAssert wheel == 1
  inp.setLen(0)
  queue.add Event(kind: MouseDownEvent, x: r.x + 60, y: r.y + 60, button: RightButton)
  queue.add Event(kind: MouseUpEvent, x: r.x + 60, y: r.y + 60, button: RightButton)
  run()
  doAssert inp.seen(it.rightClicked)
  # a press outside does nothing
  inp.setLen(0)
  down(r.x + 300, r.y + 300)
  run()
  up(r.x + 300, r.y + 300)
  run()
  doAssert not inp.seen(it.pressed or it.clicked or it.down or it.released)
  # Tab to the button: no keys any more
  key(KeyTab)
  run()
  inp.setLen(0)
  key(KeyA)
  run()
  doAssert not inp.seen(it.key == KeyA or it.focused)

block fingerInput:
  # a canvas in a page taller than the window: a finger draws on the canvas
  # instead of scrolling the page
  var inp: seq[CanvasInput]
  var r: Rect
  var drawn: seq[(float, float)]
  view = proc () =
    canvas2dWith(ctx, 300, 200, CanvasOptions(key: "pad", retained: true)):
      inp.add ctx.input
      if ctx.input.down:
        ctx.fillStyle = "black"
        ctx.beginPath()
        ctx.arc(ctx.input.x, ctx.input.y, 3, 0, 2 * PI)
        ctx.fill()
        drawn.add (ctx.input.x, ctx.input.y)
    r = ui.lastRect
    for i in 0 ..< 40: label "line " & $i
  run(2)
  ui.touch = true
  let y0 = r.y
  inp.setLen(0)
  down(r.x + 50, r.y + 100)
  run()
  for i in 1 .. 5:
    move(r.x + 50 + i * 20, r.y + 100 - i * 10)
    run()
  up(r.x + 150, r.y + 50)
  run(2)
  doAssert r.y == y0, "the page did not scroll"
  doAssert inp.seen(it.finger and it.pressed)
  doAssert inp.seen(it.dragging) and drawn.len >= 5, $drawn.len
  doAssert px(r.x + 150, r.y + 50) == 0, "a dot where the finger was"
  # without captureDrag, the same move scrolls the page
  view = proc () =
    canvas2dWith(ctx, 300, 200, CanvasOptions(key: "free", captureDrag: false)):
      ctx.fillStyle = "white"
      ctx.fillRect(0, 0, 300, 200)
    r = ui.lastRect
    for i in 0 ..< 40: label "line " & $i
  run(3)
  let y1 = r.y
  down(r.x + 50, r.y + 150)
  run()
  for i in 1 .. 5:
    move(r.x + 50, r.y + 150 - i * 20)
    run()
  up(r.x + 50, r.y + 50)
  run(3)
  doAssert r.y < y1, "scrolled: " & $r.y & " " & $y1
  ui.touch = false

echo "canvas2d tests passed"
