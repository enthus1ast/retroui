## Freehand ink: the outline of a stroke drawn with a pen, a finger or the
## mouse -- thinner where it was drawn fast or pressed lightly, tapered at
## its ends if asked, with round caps -- as one polygon to fill (nonzero).
## In the manner of the "perfect freehand" strokes of today's whiteboards.
## Use it for ink in a drawing or note-taking app; `retroui/board` draws its
## ink with it.
##
## ```nim
## let outline = strokeOutline(points, size = 8)
## fillContours(@[outline], ink)            # (or any polygon filler)
## ```
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/math

type
  InkPoint* = tuple[x, y, p: float32]
    ## A point of a stroke: where, and how hard it was pressed (0..1; 0.5
    ## when the device says nothing).

  InkOptions* = object
    ## How a stroke's outline is made (`inkOptions` gives the usual ones).
    size*: float            ## the width at full pressure
    thinning*: float        ## how much pressure narrows it (0: not at all .. 1)
    smoothing*: float       ## how much the outline's corners are softened (0..1)
    streamline*: float      ## how much the points follow behind the pen (0..1)
    simulatePressure*: bool ## no real pressure: from the speed (slow: thick)
    taperStart*, taperEnd*: float  ## lengths over which the ends narrow to nothing
    capStart*, capEnd*: bool       ## round ends
    last*: bool             ## the stroke is finished (its end is where the pen lifted)

proc inkOptions*(size: float; thinning = 0.5; smoothing = 0.5; streamline = 0.5;
                 simulatePressure = true): InkOptions =
  ## Options for strokes `size` wide.
  InkOptions(size: size, thinning: thinning, smoothing: smoothing, streamline: streamline,
             simulatePressure: simulatePressure, capStart: true, capEnd: true, last: true)

type V = tuple[x, y: float]

proc `+`(a, b: V): V {.inline.} = (a.x + b.x, a.y + b.y)
proc `-`(a, b: V): V {.inline.} = (a.x - b.x, a.y - b.y)
proc `*`(a: V; k: float): V {.inline.} = (a.x * k, a.y * k)
proc len(a: V): float {.inline.} = sqrt(a.x * a.x + a.y * a.y)
proc unit(a: V): V {.inline.} =
  let l = a.len
  if l < 1e-9: (0.0, 0.0) else: (a.x / l, a.y / l)
proc perp(a: V): V {.inline.} = (a.y, -a.x)
proc lerp(a, b: V; t: float): V {.inline.} = (a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
proc rotAround(p, c: V; r: float): V {.inline.} =
  let s = sin(r)
  let co = cos(r)
  let px = p.x - c.x
  let py = p.y - c.y
  (px * co - py * s + c.x, px * s + py * co + c.y)

proc radiusAt(size, thinning, pressure: float): float {.inline.} =
  ## (half the width at a pressure)
  if thinning == 0: return size / 2
  size / 2 * clamp(0.5 - thinning * (0.5 - pressure), 0.05, 1.0) * 2

type Sample = object
  p: V             ## where (after streamlining)
  pressure: float
  vec: V           ## its direction from the one before (unit)
  dist: float      ## from the one before
  run: float       ## along the stroke so far

proc samples(pts: openArray[InkPoint]; o: InkOptions): seq[Sample] =
  ## The points, made to follow behind the pen (streamline) and measured.
  if pts.len == 0: return
  let t = 0.15 + (1 - clamp(o.streamline, 0.0, 1.0)) * 0.85
  var prev: V = (pts[0].x.float, pts[0].y.float)
  result.add Sample(p: prev, pressure: (if pts[0].p > 0: pts[0].p.float else: 0.5))
  # (very close points first drop out: the start is not a blot)
  for i in 1 ..< pts.len:
    let raw: V = (pts[i].x.float, pts[i].y.float)
    let isLast = o.last and i == pts.high
    let p = if isLast: raw else: lerp(prev, raw, t)
    let d = (p - prev).len
    if d < 0.01 and not isLast: continue
    let run = result[^1].run + d
    result.add Sample(p: p, pressure: (if pts[i].p > 0: pts[i].p.float else: 0.5),
                      vec: unit(prev - p), dist: d, run: run)
    prev = p
  if result.len > 1: result[0].vec = result[1].vec

proc strokeOutline*(pts: openArray[InkPoint]; o: InkOptions): seq[(float, float)] =
  ## The outline of the stroke through `pts` with options `o`: one closed
  ## polygon (empty for no points; a dot for one).
  let ps = samples(pts, o)
  if ps.len == 0: return
  let size = max(0.1, o.size)
  let total = ps[^1].run
  let minDist = (size * clamp(o.smoothing, 0.0, 1.0)) ^ 2 * 0.25
  # a dot: a circle
  if ps.len == 1 or total < size * 0.05:
    let r = radiusAt(size, o.thinning, if o.simulatePressure: 0.5 else: ps[0].pressure)
    let c = ps[0].p
    let n = 16
    for i in 0 ..< n:
      let a = 2 * PI * i.float / n.float
      result.add (c.x + cos(a) * r, c.y + sin(a) * r)
    return
  var left, right: seq[V]
  var prevPressure = ps[0].pressure
  var radius = size / 2
  var firstRadius = -1.0
  let taperS = if o.taperStart > 0: o.taperStart else: 0.0
  let taperE = if o.taperEnd > 0: o.taperEnd else: 0.0
  var prevVec = ps[0].vec
  for i in 0 ..< ps.len:
    let s = ps[i]
    var pressure = s.pressure
    if o.simulatePressure:
      # (fast: thinner; the pressure moves gently toward what the speed says)
      let sp = min(1.0, s.dist / size)
      let rp = min(1.0, 1 - sp)
      pressure = min(1.0, prevPressure + (rp - prevPressure) * (sp * 0.275))
    radius = radiusAt(size, o.thinning, pressure)
    if firstRadius < 0: firstRadius = radius
    # the tapers
    let ts = if taperS > 0 and s.run < taperS: sin(s.run / taperS * PI / 2) else: 1.0
    let te = if taperE > 0 and total - s.run < taperE: sin((total - s.run) / taperE * PI / 2) else: 1.0
    radius = max(0.01, radius * min(ts, te))
    prevPressure = pressure
    let nextVec = if i < ps.high: ps[i + 1].vec else: s.vec
    let dpr = if i < ps.high: nextVec.x * s.vec.x + nextVec.y * s.vec.y else: 1.0
    let offset = perp(lerp(nextVec, s.vec, dpr).unit) * radius
    # a sharp turn: round it (points round the corner)
    if i > 0 and i < ps.high and dpr < 0:
      let off = perp(s.vec) * radius
      for k in 0 .. 12:
        let t = k.float / 12
        left.add rotAround(s.p - off, s.p, PI * t)
        right.add rotAround(s.p + off, s.p, -PI * t)
      prevVec = s.vec
      continue
    let l = s.p - offset
    let r = s.p + offset
    let keep = i <= 1 or i == ps.high
    if keep or left.len == 0 or (l - left[^1]).len * (l - left[^1]).len > minDist: left.add l
    if keep or right.len == 0 or (r - right[^1]).len * (r - right[^1]).len > minDist: right.add r
    prevVec = s.vec
  # the ends: round caps (or tapered points)
  proc arc(a, c, toward: V): seq[V] =
    ## (from `a` round `c` to the point across, by the side of `toward`)
    let plus = rotAround(a, c, PI / 2)
    let minus = rotAround(a, c, -PI / 2)
    let sign = if (plus - toward).len <= (minus - toward).len: 1.0 else: -1.0
    for k in 1 .. 11: result.add rotAround(a, c, sign * PI * k.float / 12)
  let first = ps[0].p
  let lastP = ps[^1].p
  var startCap, endCap: seq[V]
  if left.len >= 1 and right.len >= 1:
    if o.capEnd and taperE == 0:
      endCap = arc(left[^1], lastP, lastP - ps[^1].vec * radius)
    if o.capStart and taperS == 0:
      startCap = arc(right[0], first, first + ps[0].vec * firstRadius)
  # left side, the end, the right side back, the start
  for v in left: result.add (v.x, v.y)
  for v in endCap: result.add (v.x, v.y)
  for i in countdown(right.high, 0): result.add (right[i].x, right[i].y)
  for v in startCap: result.add (v.x, v.y)

proc strokeOutline*(pts: openArray[InkPoint]; size: float; thinning = 0.5;
                    simulatePressure = true): seq[(float, float)] =
  ## `strokeOutline` with the usual options for strokes `size` wide.
  strokeOutline(pts, inkOptions(size, thinning, simulatePressure = simulatePressure))
