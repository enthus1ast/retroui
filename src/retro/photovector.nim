## Illustrator's path tools for shape layers and paths: Merge Shape
## Components (the Pathfinder: what Combine, Subtract, Intersect and
## Exclude make, as plain outlines), Offset Path, Outline Stroke, Simplify,
## Reverse Path Direction, Join, and the Star and Spiral shapes.
##
## The outlines are worked out on pixels as big as the image (finer:
## `scale`), then traced and fitted with curves -- smooth, few points.

import std/[math, algorithm]
import photo, photopaint, photoshapes

proc tracedPath*(m: seq[uint8]; w, h: int; tolerance = 0.8; scale = 1.0): Path =
  ## The outlines of a mask (`w` x `h`, 128 and over inside) as a path of
  ## curves (fitted within `tolerance` pixels), divided by `scale`.
  if m.len != w * h or w <= 0 or h <= 0: return
  let tmp = Doc(w: w, h: h)
  tmp.sel = m
  # (outlines and holes: the bigger first, holes taken away from what is
  # before them -- an island in a hole, smaller, comes after it)
  var loops: seq[tuple[area: float; sp: SubPath]]
  for loop in tmp.selectionOutlines():
    if loop.len < 3: continue
    var pts = loop
    if scale != 1.0:
      for p in pts.mitems: p = (p[0] / scale, p[1] / scale)
    var area = 0.0
    for i in 0 ..< pts.len:
      let a = pts[i]
      let b = pts[(i + 1) mod pts.len]
      area += a[0] * b[1] - b[0] * a[1]
    var sp = fitPath(pts, tolerance / scale * max(1.0, scale * 0.6), closed = true, cornerAngle = 55)
    sp.closed = true
    if sp.pts.len >= 3: loops.add (area / 2, sp)
  var outerSign = 0.0
  for l in loops:
    if abs(l.area) > abs(outerSign): outerSign = l.area
  loops.sort(proc (a, b: tuple[area: float; sp: SubPath]): int = cmp(abs(b.area), abs(a.area)))
  for l in loops:
    var sp = l.sp
    sp.op = if (l.area > 0) == (outerSign > 0): poAdd else: poSubtract
    result.subs.add sp

proc maskOf(p: Path; w, h: int; scale: float): seq[uint8] =
  var q = p
  if scale != 1.0:
    for sp in q.subs.mitems:
      for pt in sp.pts.mitems:
        pt.p = (pt.p[0] * scale, pt.p[1] * scale)
        pt.inH = (pt.inH[0] * scale, pt.inH[1] * scale)
        pt.outH = (pt.outH[0] * scale, pt.outH[1] * scale)
  shapeMask(q, int(ceil(w.float * scale)), int(ceil(h.float * scale)))

proc fineScale(w, h: int): float =
  ## (finer pixels for a small image: up to 4 times, 24 million at most)
  clamp(sqrt(24e6 / max(1.0, w.float * h.float)), 1.0, 4.0)

proc mergeComponents*(p: Path; w, h: int): Path =
  ## Merge Shape Components: the subpaths, as their operations put them
  ## together (Combine, Subtract Front, Intersect, Exclude), made one set of
  ## plain outlines (holes as holes).
  let k = fineScale(w, h)
  let m = maskOf(p, w, h, k)
  tracedPath(m, int(ceil(w.float * k)), int(ceil(h.float * k)), 0.8, k)

proc offsetPath*(p: Path; w, h: int; dist: float): Path =
  ## Offset Path: the outline moved `dist` pixels out (negative: in), its
  ## corners rounded.
  let k = fineScale(w, h)
  let sw = int(ceil(w.float * k))
  let sh = int(ceil(h.float * k))
  var m = maskOf(p, w, h, k)
  let r = abs(dist) * k
  if r >= 0.5:
    # (the distance to the edge, from a blur wide enough, thresholded: round corners)
    var f = newSeq[float32](sw * sh)
    for i, v in m: f[i] = v.float32 / 255
    let passes = 3
    let br = max(1, int(round(r / sqrt(passes.float))))
    for _ in 0 ..< passes:
      # a box blur, rows then columns
      var t = f
      for y in 0 ..< sh:
        var acc = 0'f32
        for x in -br .. br: acc += f[y * sw + clamp(x, 0, sw - 1)]
        for x in 0 ..< sw:
          t[y * sw + x] = acc / float32(2 * br + 1)
          acc += f[y * sw + min(x + br + 1, sw - 1)] - f[y * sw + max(x - br, 0)]
      for x in 0 ..< sw:
        var acc = 0'f32
        for y in -br .. br: acc += t[clamp(y, 0, sh - 1) * sw + x]
        for y in 0 ..< sh:
          f[y * sw + x] = acc / float32(2 * br + 1)
          acc += t[min(y + br + 1, sh - 1) * sw + x] - t[max(y - br, 0) * sw + x]
    # (out: anything the blur reached; in: only what stayed whole)
    let cut = if dist > 0: 0.04'f32 else: 0.96'f32
    for i in 0 ..< sw * sh: m[i] = if f[i] > cut: 255'u8 else: 0'u8
  tracedPath(m, sw, sh, 0.8, k)

proc outlineStroke*(s: ShapeData; w, h: int): Path =
  ## Outline Stroke: a shape's stroke made a shape of its own -- its
  ## outline, to fill.
  if s.strokeWidth <= 0: return
  let k = fineScale(w, h)
  var t = s
  t.fill = ShapePaint(kind: spNone)
  t.stroke = ShapePaint(kind: spColor, color: 0xFFFFFFFF'u32)
  t.strokeWidth = s.strokeWidth * k
  for sp in t.path.subs.mitems:
    for pt in sp.pts.mitems:
      pt.p = (pt.p[0] * k, pt.p[1] * k)
      pt.inH = (pt.inH[0] * k, pt.inH[1] * k)
      pt.outH = (pt.outH[0] * k, pt.outH[1] * k)
  t.dashes = s.dashes
  let sw = int(ceil(w.float * k))
  let sh = int(ceil(h.float * k))
  var px = newSeq[uint32](sw * sh)
  discard renderShape(t, px, sw, sh)
  var m = newSeq[uint8](sw * sh)
  for i, c in px: m[i] = uint8(c shr 24)
  tracedPath(m, sw, sh, 0.8, k)

proc simplifyPath*(p: Path; tolerance = 2.0): Path =
  ## Simplify: each subpath with fewer points, fitted again with curves
  ## within `tolerance` pixels of where it was.
  result.name = p.name
  for sp in p.subs:
    var pts: seq[(float, float)]
    for poly in Path(subs: @[sp]).flatten(16): pts.add poly
    if pts.len < 2:
      result.subs.add sp
      continue
    var o = fitPath(pts, tolerance, sp.closed)
    o.op = sp.op
    o.joined = sp.joined
    if o.pts.len >= 2: result.subs.add o else: result.subs.add sp

proc reversed*(sp: SubPath): SubPath =
  ## The subpath the other way round (its handles swapped).
  result = sp
  result.pts.setLen(0)
  for i in countdown(sp.pts.high, 0):
    let q = sp.pts[i]
    result.pts.add PathPoint(p: q.p, inH: q.outH, outH: q.inH)

proc reversePath*(p: Path): Path =
  ## Reverse Path Direction: every subpath the other way round.
  result = p
  for sp in result.subs.mitems: sp = sp.reversed

proc joinPaths*(p: Path; tolerance = 6.0): Path =
  ## Join: open subpaths whose ends meet (within `tolerance` pixels) made
  ## one; an open subpath whose own ends meet closed.
  result = p
  var changed = true
  while changed:
    changed = false
    for i in 0 ..< result.subs.len:
      let a = result.subs[i]
      if a.closed or a.pts.len < 2: continue
      if hypot(a.pts[0].p[0] - a.pts[^1].p[0], a.pts[0].p[1] - a.pts[^1].p[1]) <= tolerance and a.pts.len >= 3:
        result.subs[i].closed = true
        if hypot(a.pts[0].p[0] - a.pts[^1].p[0], a.pts[0].p[1] - a.pts[^1].p[1]) < 0.01:
          result.subs[i].pts[0].inH = a.pts[^1].inH
          result.subs[i].pts.setLen(a.pts.len - 1)
        changed = true
        break
      for j in 0 ..< result.subs.len:
        if j == i: continue
        var b = result.subs[j]
        if b.closed or b.pts.len < 1: continue
        let endA = a.pts[^1].p
        var hit = false
        if hypot(endA[0] - b.pts[0].p[0], endA[1] - b.pts[0].p[1]) <= tolerance: hit = true
        elif hypot(endA[0] - b.pts[^1].p[0], endA[1] - b.pts[^1].p[1]) <= tolerance:
          b = b.reversed
          hit = true
        if hit:
          var merged = a
          var first = 0
          if hypot(endA[0] - b.pts[0].p[0], endA[1] - b.pts[0].p[1]) < 0.01:
            merged.pts[^1].outH = b.pts[0].outH
            first = 1
          for k in first ..< b.pts.len: merged.pts.add b.pts[k]
          result.subs[i] = merged
          result.subs.delete(j)
          changed = true
          break
      if changed: break

proc starPath*(x0, y0, x1, y1: float; points = 5; indent = 50; roundness = 0): Path =
  ## The Star tool: `points` points, its inner corners `indent` % in;
  ## `roundness` % rounds them.
  polygonPath(x0, y0, x1, y1, points, star = true, indent = indent, smooth = roundness > 0)

proc spiralPath*(x0, y0, x1, y1: float; turns = 3.0; decay = 80): Path =
  ## The Spiral tool: an open spiral filling the box, `turns` times round,
  ## each turn `decay` % the size of the one outside it.
  let cx = (x0 + x1) / 2
  let cy = (y0 + y1) / 2
  let rx = abs(x1 - x0) / 2
  let ry = abs(y1 - y0) / 2
  let k = clamp(decay, 5, 99).float / 100
  let steps = max(24, int(turns * 24))
  var pts: seq[(float, float)]
  for i in 0 .. steps:
    let t = i.float / 24                     # (turns so far)
    let r = pow(k, t)
    let a = -PI / 2 + t * 2 * PI
    pts.add (cx + cos(a) * rx * r, cy + sin(a) * ry * r)
  var sp = fitPath(pts, 0.4, false)
  sp.closed = false
  result.subs.add sp
