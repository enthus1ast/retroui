## Tests of `retro/edgetrace`: the edges of a picture linked into chains,
## for Retro Photo's tracing tool.
##
## - A filled circle: one chain, round, on the circle to a fraction of a
##   pixel, its points in order; `fitPath` makes it a closed path of a few
##   points; `chainAt` near and far; `chainPart` a quarter of it, in order.
## - A rectangle whose color differs and lightness does not: found by
##   color alone, its corners kept (by `simplify` and by `fitPath`).
## - An edge from the top of the picture to the bottom: an open chain in
##   order; `chainPart` along it both ways.
## - A T where three colors meet: split into three chains at the branch.
## - A noisy gradient: few or no chains at a low detail, more at a high one.
## - A square on a transparent picture whose hidden colors are noise.
## - A 4000 x 3000 picture: traced on a copy of half the size, the points
##   in the picture's pixels; how long it takes.

import std/[math, random, times, strutils, algorithm]
import retro/[gfx, edgetrace, photo, photopaint]

proc dist(a, b: (float, float)): float = hypot(a[0] - b[0], a[1] - b[1])

proc ordered(pts: seq[(float, float)]; closed: bool; gap = 1.6) =
  ## (each point next to the one before: in order along the edge)
  for k in 1 ..< pts.len:
    doAssert dist(pts[k], pts[k - 1]) <= gap, "points " & $(k - 1) & " and " & $k & " apart: " & $pts[k - 1] & " " & $pts[k]
  if closed: doAssert dist(pts[0], pts[^1]) <= 2 * gap

proc nearest(pts: seq[(float, float)]; q: (float, float)): float =
  result = Inf
  for p in pts: result = min(result, dist(p, q))

proc picture(w, h: int; color: proc (x, y: int): uint32): Bitmap =
  result = newBitmap(w, h)
  for y in 0 ..< h:
    for x in 0 ..< w: result.px[y * w + x] = color(x, y)

# ---- a circle ------------------------------------------------------------------------------------------

proc circle() =
  const cx = 200.0
  const cy = 150.0
  const rad = 80.0
  let b = picture(400, 300, proc (x, y: int): uint32 =
    if hypot(x.float + 0.5 - cx, y.float + 0.5 - cy) <= rad: 0xFFE0C040'u32 else: 0xFF3050A0'u32)
  let m = newEdgeMap(b)
  doAssert m.w == 400 and m.h == 300 and m.scale == 1 and m.gw == 400 and m.gh == 300
  doAssert m.strength.len == 400 * 300 and m.index.len == 400 * 300
  doAssert m.chains.len == 1, $m.chains.len & " chains"
  let i = m.chainAt(cx + rad, cy, 4)
  doAssert i == 0
  doAssert m.chainClosed(i)
  let pts = m.chainPoints(i)
  doAssert pts.len > 400 and pts.len < 600, $pts.len    # (one a pixel round: 2 pi 80 = 503 long)
  var sum, worst = 0.0
  for p in pts:
    let e = abs(hypot(p[0] - cx, p[1] - cy) - rad)
    sum += e
    worst = max(worst, e)
  doAssert sum / pts.len.float < 0.3 and worst < 0.8, "off the circle by " & $(sum / pts.len.float) & ", at most " & $worst
  pts.ordered(closed = true)
  var turn = 0.0                                       # (the same way round all along: once round)
  for k in 0 ..< pts.len:
    let a = arctan2(pts[k][1] - cy, pts[k][0] - cx)
    let b = arctan2(pts[(k + 1) mod pts.len][1] - cy, pts[(k + 1) mod pts.len][0] - cx)
    var d = b - a
    if d > PI: d -= 2 * PI
    if d < -PI: d += 2 * PI
    doAssert d * (if turn == 0: d else: turn) > 0, "back the other way at point " & $k
    turn += d
  doAssert abs(abs(turn) - 2 * PI) < 1e-6
  # the strength: strong on the edge, none in the middle
  doAssert m.strength[150 * 400 + 280] > 50 and m.strength[150 * 400 + 200] == 0
  # a path of a few points, closed, on the circle
  let sp = fitPath(pts, 2.0, closed = true)
  doAssert sp.closed and sp.pts.len >= 4 and sp.pts.len <= 24, $sp.pts.len & " points"
  for q in sp.pts: doAssert abs(hypot(q.p[0] - cx, q.p[1] - cy) - rad) < 1.5
  # near and far
  doAssert m.chainAt(cx + rad + 0.4, cy - 0.3, 2) == 0
  doAssert m.chainAt(cx - rad - 3, cy, 5) == 0
  doAssert m.chainAt(cx + rad + 7, cy, 4) == -1        # (7 pixels off, 4 asked)
  doAssert m.chainAt(cx + rad + 7, cy, 9) == 0
  doAssert m.chainAt(cx, cy, 30) == -1                 # (the middle: 80 away)
  doAssert m.chainAt(-40, -40, 10) == -1 and m.chainAt(1e6, 5, 10) == -1
  doAssert m.chainPoints(1).len == 0 and m.chainPoints(-1).len == 0 and not m.chainClosed(7)
  # a quarter of it, from the right to the bottom: the short way round, in order
  let part = m.chainPart(i, cx + rad, cy, cx, cy + rad)
  doAssert dist(part[0], (cx + rad, cy)) < 1.0 and dist(part[^1], (cx, cy + rad)) < 1.0
  doAssert part.len > 100 and part.len < 150, $part.len  # (a quarter of 503)
  part.ordered(closed = false)
  for p in part: doAssert p[0] >= cx - 1 and p[1] >= cy - 1, "the long way round: " & $p
  let back = m.chainPart(i, cx, cy + rad, cx + rad, cy)
  doAssert back.len == part.len and back[0] == part[^1] and back[^1] == part[0]
  let up = m.chainPart(i, cx + rad, cy, cx, cy - rad)    # (the other way round: still the short way)
  doAssert up.len > 100 and up.len < 150
  for p in up: doAssert p[0] >= cx - 1 and p[1] <= cy + 1
  echo "  circle: one chain of ", pts.len, " points, off it by ", formatFloat(sum / pts.len.float, ffDecimal, 2),
       " px on average; fitPath: ", sp.pts.len, " points"

# ---- a rectangle, found by color alone -------------------------------------------------------------------

proc rectangle() =
  # (red-brown on green of the same lightness: 0.299 R + 0.587 G + 0.114 B about 82 both)
  let b = picture(320, 240, proc (x, y: int): uint32 =
    if x >= 60 and x < 260 and y >= 50 and y < 190: 0xFFB42828'u32 else: 0xFF286E28'u32)
  let m = newEdgeMap(b)
  doAssert m.chains.len == 1, $m.chains.len & " chains"
  doAssert m.chainClosed(0)
  let pts = m.chainPoints(0)
  pts.ordered(closed = true)
  let corners = [(60.0, 50.0), (260.0, 50.0), (260.0, 190.0), (60.0, 190.0)]
  for p in pts:
    var near = Inf
    for c in corners: near = min(near, dist(p, c))
    if near > 5:
      let off = min(min(abs(p[0] - 60), abs(p[0] - 260)), min(abs(p[1] - 50), abs(p[1] - 190)))
      doAssert off < 0.5, "off the side by " & $off & ": " & $p
  for c in corners: doAssert pts.nearest(c) < 3.0, "corner " & $c & ": " & $pts.nearest(c)
  let few = simplify(pts, 1.5)
  doAssert few.len >= 4 and few.len <= 9, $few.len & " points: " & $few
  for c in corners: doAssert few.nearest(c) < 3.0, "simplified, corner " & $c
  let sp = fitPath(pts, 2.0, closed = true, cornerAngle = 60)
  var sharp = 0
  for c in corners:
    var best = Inf
    var at = -1
    for k, q in sp.pts:
      if dist(q.p, c) < best:
        best = dist(q.p, c)
        at = k
    doAssert best < 3.0, "fitPath, corner " & $c & ": " & $best
    if sp.pts[at].inH == sp.pts[at].p and sp.pts[at].outH == sp.pts[at].p: inc sharp
  doAssert sharp == 4, $sharp & " of the corners made corners"
  echo "  rectangle (by color alone): one chain, ", few.len, " points simplified, the corners kept"

# ---- an edge across, top to bottom: an open chain --------------------------------------------------------

proc across() =
  proc side(y: float): float = 150 + 30 * sin(y / 25)
  let b = picture(300, 200, proc (x, y: int): uint32 =
    if x.float + 0.5 > side(y.float + 0.5): 0xFF202020'u32 else: 0xFFD0D0D0'u32)
  let m = newEdgeMap(b, 50)
  doAssert m.chains.len == 1, $m.chains.len & " chains"
  doAssert not m.chainClosed(0)
  var pts = m.chainPoints(0)
  if pts[0][1] > pts[^1][1]: pts.reverse()
  doAssert pts[0][1] < 3 and pts[^1][1] > 197, $pts[0] & " .. " & $pts[^1]
  pts.ordered(closed = false)
  for k, p in pts:
    # (on the edge, but by the picture's border: the blur takes the row there as going on)
    if p[1] > 5 and p[1] < 195:
      var off = Inf                                  # (across the edge: to its nearest point)
      for j in -300 .. 300: off = min(off, dist(p, (side(p[1] + j / 100), p[1] + j / 100)))
      doAssert off < 0.5, "off the edge by " & $off & ": " & $p
    if k > 0: doAssert p[1] >= pts[k - 1][1] - 0.5, "back up at " & $p
  let down = m.chainPart(0, side(20), 20, side(180), 180)
  doAssert abs(down[0][1] - 20) < 1.5 and abs(down[^1][1] - 180) < 1.5
  for k in 1 ..< down.len: doAssert down[k][1] >= down[k - 1][1] - 0.5
  let up = m.chainPart(0, side(180), 180, side(20), 20)
  doAssert up.len == down.len and up[0] == down[^1] and up[^1] == down[0]
  let sp = fitPath(m.chainPoints(0), 1.0)
  doAssert not sp.closed and sp.pts.len >= 4 and sp.pts.len <= 30, $sp.pts.len
  echo "  an edge top to bottom: an open chain of ", pts.len, " points in order; fitPath: ", sp.pts.len, " points"

# ---- a T: three chains ------------------------------------------------------------------------------------

proc branch() =
  # (blue on the left; on the right, yellow above red: the line down the middle
  # branches where the one across meets it)
  let b = picture(240, 200, proc (x, y: int): uint32 =
    if x < 100: 0xFF2040C0'u32 elif y < 90: 0xFFF0E040'u32 else: 0xFFC02020'u32)
  let m = newEdgeMap(b)
  doAssert m.chains.len == 3, $m.chains.len & " chains"
  var vertical, horizontal = 0
  for i in 0 ..< 3:
    let pts = m.chainPoints(i)
    pts.ordered(closed = false, gap = 2.0)        # (where the colors meet, a point is less sure)
    doAssert not m.chainClosed(i)
    let near = min(dist(pts[0], (100.0, 90.0)), dist(pts[^1], (100.0, 90.0)))
    doAssert near < 6, "chain " & $i & " ends " & $near & " from the branch"
    if abs(pts[0][0] - pts[^1][0]) < 3: inc vertical else: inc horizontal
  doAssert vertical == 2 and horizontal == 1
  doAssert m.chainAt(100, 30, 3) != m.chainAt(100, 160, 3)
  doAssert m.chainAt(180, 90, 3) notin [-1, m.chainAt(100, 30, 3), m.chainAt(100, 160, 3)]
  echo "  a T: three chains, split at the branch"

# ---- noise ------------------------------------------------------------------------------------------------

proc noise() =
  var r = initRand(11)
  var b = newBitmap(300, 200)
  for y in 0 ..< 200:
    for x in 0 ..< 300:
      let v = clamp(40 + x * 175 div 300 + r.rand(-12 .. 12), 0, 255)
      b.px[y * 300 + x] = 0xFF000000'u32 or (uint32(v) * 0x010101'u32)
  let low = newEdgeMap(b, 1)
  let mid = newEdgeMap(b, 50)
  let high = newEdgeMap(b, 100)
  doAssert low.chains.len <= 2, $low.chains.len & " chains at detail 1"
  doAssert high.chains.len > low.chains.len + 20 and high.chains.len >= mid.chains.len,
           $low.chains.len & ", " & $mid.chains.len & ", " & $high.chains.len
  echo "  a noisy gradient: ", low.chains.len, " chains at detail 1, ", mid.chains.len, " at 50, ",
       high.chains.len, " at 100"

# ---- transparency -----------------------------------------------------------------------------------------

proc transparent() =
  var r = initRand(3)
  var b = newBitmap(200, 150)
  for y in 0 ..< 150:
    for x in 0 ..< 200:
      b.px[y * 200 + x] =
        if x >= 50 and x < 150 and y >= 40 and y < 110: 0xFF808080'u32
        else: uint32(r.rand(0xFFFFFF))                     # (alpha 0: its color noise)
  let m = newEdgeMap(b)
  doAssert m.chains.len == 1 and m.chainClosed(0), $m.chains.len & " chains"
  doAssert m.chainPoints(0).nearest((50.0, 75.0)) <= 0.51 and m.chainPoints(0).nearest((150.0, 75.0)) <= 0.51
  echo "  a square on a transparent picture (its hidden colors noise): one chain"

# ---- nothing to trace -------------------------------------------------------------------------------------

proc empty() =
  for b in [nil, newBitmap(0, 0), newBitmap(2, 2, 0xFF000000'u32), newBitmap(50, 40, 0xFF336699'u32)]:
    let m = newEdgeMap(b)
    doAssert m != nil and m.chains.len == 0
    doAssert m.chainAt(10, 10, 100) == -1 and m.chainPoints(0).len == 0 and m.chainPart(0, 0, 0, 5, 5).len == 0
  doAssert simplify(@[(0.0, 0.0), (5.0, 0.1), (10.0, 0.0), (10.0, 10.0)], 0.5) == @[(0.0, 0.0), (10.0, 0.0), (10.0, 10.0)]
  doAssert simplify(@[(1.0, 2.0)], 1).len == 1

# ---- a big picture ----------------------------------------------------------------------------------------

proc big() =
  const w = 4000
  const h = 3000
  var r = initRand(5)
  var b = newBitmap(w, h)
  let circles = [(1200.0, 1100.0, 600.0), (2900.0, 1700.0, 800.0), (2000.0, 2600.0, 250.0)]
  for y in 0 ..< h:
    for x in 0 ..< w:
      var c = 0xFF000000'u32 or (uint32(60 + x * 90 div w + r.rand(10)) shl 16) or
              (uint32(90 + y * 50 div h) shl 8) or uint32(140 - y * 60 div h)
      for (cx, cy, rad) in circles:
        if hypot(x.float + 0.5 - cx, y.float + 0.5 - cy) <= rad: c = 0xFFE0A040'u32 + uint32(r.rand(8))
      b.px[y * w + x] = c
  var best = Inf
  var m: EdgeMap
  for _ in 0 .. 1:
    let t0 = epochTime()
    m = newEdgeMap(b)
    best = min(best, epochTime() - t0)
  doAssert m.w == w and m.h == h and m.scale == 2 and m.gw == 2000 and m.gh == 1500
  doAssert m.index.len == 2000 * 1500
  # (the points in the picture's pixels)
  for (cx, cy, rad) in circles:
    let i = m.chainAt(cx + rad, cy, 6)
    doAssert i >= 0 and m.chainClosed(i), "circle " & $(cx, cy, rad)
    let pts = m.chainPoints(i)
    var sum = 0.0
    for p in pts: sum += abs(hypot(p[0] - cx, p[1] - cy) - rad)
    doAssert sum / pts.len.float < 1.0, "off the circle by " & $(sum / pts.len.float)
    pts.ordered(closed = true, gap = 3.2)
    doAssert m.chainAt(cx, cy - rad - 3, 6) == i and m.chainAt(cx, cy, rad / 2) == -1
  echo "  4000 x 3000: traced at half the size, ", m.chains.len, " chains, ",
       int(best * 1000), " ms"
  when defined(release):
    doAssert best < 3.0, "4000 x 3000 took " & $best & " s"

let t0 = epochTime()
circle()
rectangle()
across()
branch()
noise()
transparent()
empty()
big()
echo "edgetrace: passed (", formatFloat(epochTime() - t0, ffDecimal, 1), " s)"
