## Anti-aliased filling of outlines made of lines and quadratic curves:
## each pixel gets the exact area of its square that lies inside (signed
## area accumulation, the method of font-rs). Used for glyphs and shapes.

import std/math

type Raster* = object
  w*, h*: int
  acc: seq[float32]

proc newRaster*(w, h: int): Raster =
  ## A canvas of `w` x `h` pixels; draw closed outlines into it with `line`
  ## and `quad` (any direction; overlaps add up), then take `coverage`.
  Raster(w: w, h: h, acc: newSeq[float32](w * h + w + 3))


{.push boundChecks: off, overflowChecks: off.}

const Huge = 1e30'f32

proc line*(r: var Raster; x0, y0, x1, y1: float32) =
  ## Adds the signed area left of the line (font-rs' accumulation).
  # (not a number, or infinite -- a chart of NaN, a path scaled by 0: no
  # area; such a number made into an index would write anywhere)
  if not (abs(x0) < Huge and abs(x1) < Huge and abs(y0) < Huge and abs(y1) < Huge): return
  if abs(y0 - y1) <= 1e-6: return
  var (dir, ax, ay, bx, by) =
    if y0 < y1: (1'f32, x0, y0, x1, y1) else: (-1'f32, x1, y1, x0, y0)
  if ay >= float32(r.h) or by <= 0: return
  let dxdy = (bx - ax) / (by - ay)
  var x = ax
  if ay < 0: x -= ay * dxdy
  let ys = if ay <= 0: 0 else: int(ay)
  let ye = if by >= float32(r.h): r.h else: int(ceil(by))
  for y in ys ..< ye:
    let ls = y * r.w
    let dy = min(float32(y + 1), by) - max(float32(y), ay)
    let xn = x + dxdy * dy
    let d = dy * dir
    # (past the sides: on them -- the row's area is all there still, so
    # what is right of it is filled as it should be; a line that ends on the
    # left side a hair past it, by rounding, is not lost)
    # (written so that a NaN, from a line as steep as can be, lands on 0)
    let cx0 = if x > 0: min(x, float32(r.w)) else: 0'f32
    let cx1 = if xn > 0: min(xn, float32(r.w)) else: 0'f32
    let (xa, xb) = if cx0 < cx1: (cx0, cx1) else: (cx1, cx0)
    let xaf = floor(xa)
    let xai = int(xaf)
    let xbc = ceil(xb)
    let xbi = int(xbc)
    if xbi <= xai + 1:
      let xm = 0.5'f32 * (cx0 + cx1) - xaf
      r.acc[ls + xai] += d - d * xm
      r.acc[ls + xai + 1] += d * xm
    else:
      let s = 1'f32 / (xb - xa)
      let x0f = xa - xaf
      let a0 = 0.5'f32 * s * (1 - x0f) * (1 - x0f)
      let x1f = xb - xbc + 1
      let am = 0.5'f32 * s * x1f * x1f
      r.acc[ls + xai] += d * a0
      if xbi == xai + 2:
        r.acc[ls + xai + 1] += d * (1 - a0 - am)
      else:
        let a1 = s * (1.5'f32 - x0f)
        r.acc[ls + xai + 1] += d * (a1 - a0)
        for xi in xai + 2 ..< xbi - 1:
          r.acc[ls + xi] += d * s
        let a2 = a1 + float32(xbi - xai - 3) * s
        r.acc[ls + xbi - 1] += d * (1 - a2 - am)
      r.acc[ls + xbi] += d * am
    x = xn

proc quad*(r: var Raster; x0, y0, cx, cy, x1, y1: float32) =
  ## Adds a quadratic curve from `x0`, `y0` to `x1`, `y1` bent toward
  ## `cx`, `cy` (as short lines).
  let dx = x0 - 2 * cx + x1
  let dy = y0 - 2 * cy + y1
  let dd = dx * dx + dy * dy
  if dd < 0.333'f32:
    r.line(x0, y0, x1, y1)
    return
  let n = 1 + int(floor(sqrt(sqrt(3'f32 * dd))))
  var px = x0
  var py = y0
  for i in 1 .. n:
    let t = float32(i) / float32(n)
    let u = 1 - t
    let qx = u * u * x0 + 2 * u * t * cx + t * t * x1
    let qy = u * u * y0 + 2 * u * t * cy + t * t * y1
    r.line(px, py, qx, qy)
    px = qx
    py = qy

{.pop.}


proc coverage*(r: Raster): seq[uint8] =
  ## How much of each pixel the outlines cover, 0..255, row by row.
  result = newSeq[uint8](r.w * r.h)
  var acc = 0'f32
  for i in 0 ..< r.w * r.h:
    acc += r.acc[i]
    result[i] = uint8(min(1'f32, abs(acc)) * 255 + 0.5)


proc clear*(r: var Raster) =
  ## Empty again (to draw other outlines in it).
  if r.acc.len > 0: zeroMem(addr r.acc[0], r.acc.len * sizeof(float32))

proc edge*(r: var Raster; x0, y0, x1, y1: float32) =
  ## `line`, for outlines that go past the left or right side: what lies
  ## past them is drawn on them (so the inside still counts) -- cut where
  ## they cross the sides, so what is inside is exactly as it would be.
  let w = r.w.float32
  if not (abs(x0) < Huge and abs(x1) < Huge and abs(y0) < Huge and abs(y1) < Huge): return
  if x0 >= 0 and x1 >= 0 and x0 <= w and x1 <= w:
    r.line(x0, y0, x1, y1)
    return
  if abs(y1 - y0) <= 1e-6: return             # (flat: no area to add)
  var ts: array[4, float32]
  var n = 1                                   # (ts[0] = 0)
  let dx = x1 - x0
  if abs(dx) > 1e-9:
    for side in [0'f32, w]:
      let t = (side - x0) / dx
      if t > 0 and t < 1:
        ts[n] = t
        inc n
  if n == 3 and ts[1] > ts[2]: swap(ts[1], ts[2])
  ts[n] = 1
  inc n
  for k in 0 ..< n - 1:
    let ta = ts[k]
    let tb = ts[k + 1]
    if tb - ta <= 1e-9: continue
    let ax = clamp(x0 + dx * ta, 0'f32, w)
    let bx = clamp(x0 + dx * tb, 0'f32, w)
    r.line(ax, y0 + (y1 - y0) * ta, bx, y0 + (y1 - y0) * tb)

proc accumulate*(r: var Raster) =
  ## The areas drawn turned into how much of each pixel is covered, 0..1
  ## (read with `[]`; overlapping outlines turning the same way add up to
  ## one: their union).
  var acc = 0'f32
  for i in 0 ..< r.w * r.h:
    acc += r.acc[i]
    r.acc[i] = min(1'f32, abs(acc))

proc `[]`*(r: Raster; i: int): float32 {.inline.} = r.acc[i]
  ## How much of pixel `i` (row by row) is covered, 0..1, after `accumulate`.
