## Makes the Retro Photo Library: brushes, patterns, gradients, swatches,
## layer styles (and the designs, which are Retro Photo's templates) with
## a catalog and thumbnails, written to library/ -- the folder that is put
## on GitHub for the app's Assets window to read (and that the app carries
## inside it, so it works offline too). All of it is made here, in code:
## CC0, free for anything.
##
##   nim c -r -d:release tools/genlibrary.nim          # writes library/

import std/[os, math, json, random, strutils]
import retro/[gfx, photo, photoshapes, photobrushes, photopaint, photostyles, adobefiles, imaging, phototemplates]

const Out = "library"

var catalog = newJArray()

proc add(id, title, kind, category, file, ext: string; thumb: Bitmap; tags: seq[string] = @[]) =
  let tp = "thumbs" / kind & "-" & id & ".png"
  createDir(Out / "thumbs")
  writeFile(Out / tp, encodePng(thumb))
  catalog.add %*{"id": id, "title": title, "kind": kind, "category": category, "thumb": tp, "file": file,
                 "ext": ext, "author": "Sultan Al Isaiee (@foxoman)", "license": "CC0", "tags": tags}

proc bitmapOf(px: seq[uint32]; w, h: int; bg = 0xFFFFFFFF'u32): Bitmap =
  result = newBitmap(w, h)
  for i in 0 ..< w * h: result.px[i] = blendPx(bg, px[i], 255, bmNormal)
  result.changed()

# ---- brushes ----------------------------------------------------------------------------------------------

const T = 128

proc mask(f: proc (x, y: float): float): seq[uint8] =
  ## A tip from a coverage function over -1..1 (4 samples a pixel).
  result = newSeq[uint8](T * T)
  for y in 0 ..< T:
    for x in 0 ..< T:
      var s = 0.0
      for (ox, oy) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]:
        s += clamp(f((x.float + ox) / T * 2 - 1, (y.float + oy) / T * 2 - 1), 0.0, 1.0)
      result[y * T + x] = uint8(clamp(int(s / 4 * 255 + 0.5), 0, 255))

proc smooth(e0, e1, v: float): float =
  let t = clamp((v - e0) / (e1 - e0), 0.0, 1.0)
  t * t * (3 - 2 * t)

proc starF(points: int; inner: float; x, y: float; r = 0.95): float =
  ## (inside a star of `points` points)
  let a = arctan2(y, x) + PI / 2
  let d = hypot(x, y)
  let seg = 2 * PI / points.float
  let t = abs(((a mod seg) + seg) mod seg - seg / 2) / (seg / 2)     # 0 at a point, 1 between
  let edge = r * (inner + (1 - inner) * (1 - t))
  1 - smooth(edge - 0.03, edge + 0.03, d)

proc noise2(x, y: float; seed: int): float =
  let ix = floor(x)
  let iy = floor(y)
  proc h(a, b: float): float =
    let n = cast[uint32](int32(a)) * 374761393'u32 + cast[uint32](int32(b)) * 668265263'u32 +
            uint32(seed) * 2654435761'u32
    var v = (n xor (n shr 13)) * 1274126177'u32
    v = v xor (v shr 16)
    float(v and 0xFFFF) / 65535
  let fx = x - ix
  let fy = y - iy
  let sx = fx * fx * (3 - 2 * fx)
  let sy = fy * fy * (3 - 2 * fy)
  let a = h(ix, iy) * (1 - sx) + h(ix + 1, iy) * sx
  let b = h(ix, iy + 1) * (1 - sx) + h(ix + 1, iy + 1) * sx
  a * (1 - sy) + b * sy

proc fbm(x, y: float; seed: int): float =
  var amp = 0.5
  var f = 1.0
  for o in 0 .. 3:
    result += amp * noise2(x * f, y * f, seed + o)
    amp *= 0.5
    f *= 2

proc custom(name: string; m: seq[uint8]; d: int; spacing: int): BrushTip =
  BrushTip(name: name, diameter: d, hardness: 100, spacing: spacing, roundness: 100, custom: m, cw: T, ch: T)

proc strokeThumb(p: BrushPreset): Bitmap

proc fBokeh(x, y: float): float =
  let d = hypot(x, y)
  (1 - smooth(0.86, 0.95, d)) * (0.55 + 0.45 * smooth(0.6, 0.9, d))

proc fSparkle(x, y: float): float =
  let core = 1 - smooth(0.0, 0.25, hypot(x, y))
  let rays = max(exp(-abs(x) * 28) * (1 - smooth(0.4, 1.0, abs(y))),
                 exp(-abs(y) * 28) * (1 - smooth(0.4, 1.0, abs(x))))
  max(core, rays)

proc fSnow(x, y: float): float =
  var best = 0.0
  for k in 0 .. 5:
    let a = k.float * PI / 3
    let u = x * cos(a) + y * sin(a)
    let v = -x * sin(a) + y * cos(a)
    if u > 0 and u < 0.95: best = max(best, 1 - smooth(0.03, 0.07, abs(v)))
    for bp in [0.45, 0.7]:
      let du = u - bp
      if du > -0.02 and du < 0.22: best = max(best, 1 - smooth(0.03, 0.06, abs(abs(v) - du)))
  max(best, 1 - smooth(0.08, 0.13, hypot(x, y)))

proc fHeart(x, y: float): float =
  let xx = x * 1.15
  let yy = -(y * 1.15) + 0.25
  let v = pow(xx * xx + yy * yy - 0.5, 3) - xx * xx * yy * yy * yy * 0.95
  1 - smooth(-0.004, 0.004, v)

proc fRain(x, y: float): float =
  (1 - smooth(0.02, 0.06, abs(x + y * 0.12))) * (1 - smooth(0.6, 0.95, abs(y))) * 0.8

proc fCloud(x, y: float): float =
  let n = fbm(x * 2.5 + 3, y * 2.5 + 7, 11)
  (1 - smooth(0.45, 1.0, hypot(x, y) + (0.5 - n) * 0.5)) * 0.85

proc fHatch(x, y: float): float =
  let u = (x + y) * 0.7071
  let line = 1 - smooth(0.12, 0.3, abs(((u * 7) mod 1.0 + 1.0) mod 1.0 - 0.5) * 2)
  line * (1 - smooth(0.7, 0.95, hypot(x, y)))

proc fGrunge(x, y: float): float =
  let n = fbm(x * 4 + 1, y * 4 + 2, 23)
  smooth(0.48, 0.58, n) * (1 - smooth(0.6, 1.0, hypot(x, y)))

proc fPaper(x, y: float): float =
  let n = noise2(x * 40, y * 40, 3) * 0.6 + noise2(x * 13, y * 13, 4) * 0.4
  smooth(0.35, 0.75, n) * (1 - smooth(0.5, 1.0, hypot(x, y)))

proc fKhatam(x, y: float): float =
  # the eight-pointed star of two squares, as on Islamic tiles
  let a = max(abs(x), abs(y))
  let r = PI / 4
  let u = x * cos(r) - y * sin(r)
  let v = x * sin(r) + y * cos(r)
  let b = max(abs(u), abs(v))
  let outer = 1 - smooth(0.66, 0.7, min(a, b))
  let hole = smooth(0.3, 0.34, hypot(x, y))
  outer * (0.35 + 0.65 * hole)

proc fCrescent(x, y: float): float =
  let a = 1 - smooth(0.86, 0.9, hypot(x, y))
  let b = 1 - smooth(0.7, 0.74, hypot(x - 0.36, y + 0.14))
  a * (1 - b)

proc stippleMask(): seq[uint8] =
  var r = initRand(5)
  result = newSeq[uint8](T * T)
  for k in 0 .. 70:
    let cx = r.rand(T.float)
    let cy = r.rand(T.float)
    if hypot(cx - T / 2, cy - T / 2) > T / 2 - 4: continue
    let rr = 1.2 + r.rand(2.2)
    for y in 0 ..< T:
      for x in 0 ..< T:
        let v = 1 - smooth(rr - 0.7, rr + 0.7, hypot(x.float + 0.5 - cx, y.float + 0.5 - cy))
        result[y * T + x] = max(result[y * T + x], uint8(v * 255))

proc brushes() =
  createDir(Out / "brushes")
  var list: seq[(string, string, string, BrushPreset, seq[string])]
  proc b(id, title, cat: string; tip: BrushTip; dy: BrushDynamics; tags: seq[string]) =
    list.add (id, title, cat, BrushPreset(name: title, folder: "Library", tip: tip, dyn: dy), tags)
  b("bokeh", "Bokeh", "Light & Sparkle", custom("Bokeh", mask(fBokeh), 90, 120),
    BrushDynamics(sizeJitter: 80, minDiameter: 20, scatter: 300, scatterBoth: true, count: 2, opacityJitter: 60),
    @["bokeh", "lights", "blur", "circles"])
  b("sparkle", "Sparkle", "Light & Sparkle", custom("Sparkle", mask(fSparkle), 70, 160),
    BrushDynamics(sizeJitter: 70, minDiameter: 15, angleJitter: 20, scatter: 260, scatterBoth: true),
    @["sparkle", "glitter", "star", "shine"])
  b("snowflake", "Snowflake", "Nature", custom("Snowflake", mask(fSnow), 60, 150),
    BrushDynamics(sizeJitter: 60, minDiameter: 25, angleJitter: 100, scatter: 300, scatterBoth: true,
                  opacityJitter: 40), @["snow", "winter", "flake"])
  b("heart", "Heart", "Shapes", custom("Heart", mask(fHeart), 60, 140),
    BrushDynamics(sizeJitter: 50, minDiameter: 30, angleJitter: 12, scatter: 220, scatterBoth: true),
    @["heart", "love", "valentine"])
  b("rain", "Rain", "Nature", custom("Rain", mask(fRain), 80, 70),
    BrushDynamics(sizeJitter: 40, scatter: 400, scatterBoth: true, count: 3, opacityJitter: 50),
    @["rain", "drops", "weather"])
  b("cloud", "Cloud Puff", "Nature", custom("Cloud Puff", mask(fCloud), 160, 30),
    BrushDynamics(sizeJitter: 40, angleJitter: 100, scatter: 60, opacityJitter: 40, flow: 35),
    @["cloud", "sky", "fog", "smoke"])
  b("stipple", "Stipple", "Texture", custom("Stipple", stippleMask(), 40, 50),
    BrushDynamics(angleJitter: 100, sizeJitter: 20), @["dots", "stipple", "pointillism", "ink"])
  b("hatching", "Hatching", "Texture", custom("Hatching", mask(fHatch), 50, 25),
    BrushDynamics(opacityJitter: 20), @["hatching", "lines", "sketch", "pencil"])
  b("grunge", "Grunge", "Texture", custom("Grunge", mask(fGrunge), 120, 60),
    BrushDynamics(sizeJitter: 50, angleJitter: 100, scatter: 50, opacityJitter: 30),
    @["grunge", "dirty", "distress", "texture"])
  b("paper", "Paper Grain", "Texture", custom("Paper Grain", mask(fPaper), 100, 20),
    BrushDynamics(angleJitter: 100, flow: 50), @["paper", "grain", "noise", "texture"])
  b("khatam", "Khatam Star", "Arabic & Islamic", custom("Khatam Star", mask(fKhatam), 80, 120),
    BrushDynamics(), @["islamic", "arabic", "star", "geometric", "khatam"])
  b("crescent", "Crescent", "Arabic & Islamic", custom("Crescent", mask(fCrescent), 70, 150),
    BrushDynamics(sizeJitter: 40, minDiameter: 40, angleJitter: 8, scatter: 200, scatterBoth: true),
    @["crescent", "moon", "ramadan", "eid"])
  b("nib", "Calligraphy Nib", "Ink & Pen",
    BrushTip(name: "Calligraphy Nib", diameter: 30, hardness: 100, spacing: 2, roundness: 12, angle: 40),
    BrushDynamics(sizeControl: dcPressure, minDiameter: 40), @["calligraphy", "arabic", "nib", "ink"])
  b("inkpen", "Ink Pen", "Ink & Pen",
    BrushTip(name: "Ink Pen", diameter: 8, hardness: 100, spacing: 3, roundness: 100),
    BrushDynamics(sizeControl: dcPressure, minDiameter: 10), @["ink", "pen", "line art"])
  for (id, title, cat, p, tags) in list:
    var p = p
    if id == "inkpen": p.smoothing = 40
    writeFile(Out / "brushes" / id & ".json", presetsToJson([p]))
    add(id, title, "brush", cat, "brushes/" & id & ".json", "json", strokeThumb(p), tags)

# ---- patterns ---------------------------------------------------------------------------------------------

proc tile(w, h: int; bg: uint32; shapes: seq[(Path, uint32)]): seq[uint32] =
  ## A tile `w` x `h`: the shapes drawn on `bg` -- and again a tile over on
  ## each side, so what crosses an edge comes back on the other.
  result = newSeq[uint32](w * h)
  for p in result.mitems: p = bg
  for (path, c) in shapes:
    for dy in -1 .. 1:
      for dx in -1 .. 1:
        var moved = path
        for s in moved.subs.mitems:
          for q in s.pts.mitems:
            let (ox, oy) = (dx.float * w.float, dy.float * h.float)
            q.p = (q.p[0] + ox, q.p[1] + oy)
            q.inH = (q.inH[0] + ox, q.inH[1] + oy)
            q.outH = (q.outH[0] + ox, q.outH[1] + oy)
        var lay = newSeq[uint32](w * h)
        discard renderShape(ShapeData(path: moved, fill: solidPaint(c)), lay, w, h)
        for i in 0 ..< w * h: result[i] = blendPx(result[i], lay[i], 255, bmNormal)

proc tile(n: int; bg: uint32; shapes: seq[(Path, uint32)]): seq[uint32] = tile(n, n, bg, shapes)

proc poly(pts: openArray[(float, float)]): Path =
  var sp = SubPath(closed: true)
  for p in pts: sp.pts.add PathPoint(p: p, inH: p, outH: p)
  result.subs.add sp

proc ring(cx, cy, r, w: float): Path =
  result = ellipsePath(cx - r, cy - r, cx + r, cy + r)
  result.combine(ellipsePath(cx - r + w, cy - r + w, cx + r - w, cy + r - w), poSubtract)

proc patterns() =
  createDir(Out / "patterns")
  var list: seq[(string, string, string, int, int, seq[uint32], seq[string])]
  template p(id, title, cat: string; n: int; px: seq[uint32]; tags: seq[string]) =
    list.add (id, title, cat, n, n, px, tags)
  let n = 120
  p("dots", "Polka Dots", "Classic", n, tile(n, 0xFF2A9D8F'u32,
    @[(ellipsePath(18, 18, 42, 42), 0xFFFFFFFF'u32), (ellipsePath(78, 78, 102, 102), 0xFFFFFFFF'u32)]),
    @["dots", "polka", "retro"])
  block:
    var st: seq[(Path, uint32)]
    for x0 in [0.0, 60.0, 120.0, 180.0]:
      st.add (poly([(x0, 0.0), (x0 + 30, 0.0), (x0 + 30 - 120, 120.0), (x0 - 120, 120.0)]), 0xFFF2A541'u32)
    p("stripes", "Diagonal Stripes", "Classic", n, tile(n, 0xFFFFF3D6'u32, st), @["stripes", "diagonal", "lines"])
  p("chevron", "Chevron", "Classic", n, tile(n, 0xFF1D3557'u32,
    @[(poly([(0.0, 20.0), (60.0, 60.0), (120.0, 20.0), (120.0, 45.0), (60.0, 85.0), (0.0, 45.0)]), 0xFFF1FAEE'u32),
      (poly([(0.0, 80.0), (60.0, 120.0), (120.0, 80.0), (120.0, 105.0), (60.0, 145.0), (0.0, 105.0)]),
       0xFFF1FAEE'u32)]),
    @["chevron", "zigzag"])
  block:
    var hs: seq[(Path, uint32)]
    let r = 30.0
    for (cx, cy) in [(0.0, 0.0), (52.0, 0.0), (26.0, 45.0), (78.0, 45.0)]:
      var pts: seq[(float, float)]
      for k in 0 .. 5:
        let a = PI / 6 + k.float * PI / 3
        pts.add (cx + cos(a) * (r - 3), cy + sin(a) * (r - 3))
      hs.add (poly(pts), 0xFFF4D35E'u32)
    list.add ("hexagons", "Honeycomb", "Geometric", 104, 90, tile(104, 90, 0xFF8B5E34'u32, hs),
              @["hexagon", "honeycomb", "geometric"])
  p("grid", "Graph Paper", "Classic", 100, block:
    var t = newSeq[uint32](100 * 100)
    for y in 0 ..< 100:
      for x in 0 ..< 100:
        t[y * 100 + x] = if x mod 20 == 0 or y mod 20 == 0: 0xFF9FC5E8'u32
                         else: 0xFFFFFFFF'u32
        if x == 0 or y == 0: t[y * 100 + x] = 0xFF4A90D9'u32
    t, @["grid", "graph", "paper"])
  block:
    var w: seq[(Path, uint32)]
    for k in 0 .. 1:
      var sp = SubPath(closed: true)
      let y0 = 30.0 + k.float * 60
      for i in 0 .. 24:
        let x = i.float * 5
        let pt = (x, y0 + sin(x / 120 * 2 * PI) * 12)
        sp.pts.add PathPoint(p: pt, inH: pt, outH: pt)
      for i in countdown(24, 0):
        let x = i.float * 5
        let pt = (x, y0 + 14 + sin(x / 120 * 2 * PI) * 12)
        sp.pts.add PathPoint(p: pt, inH: pt, outH: pt)
      w.add (Path(subs: @[sp]), 0xFF48CAE4'u32)
    p("waves", "Waves", "Classic", n, tile(n, 0xFF023E8A'u32, w), @["waves", "sea", "water"])
  block:
    # the eight-pointed star (khatam) and the cross between: Islamic tiles
    var s: seq[(Path, uint32)]
    proc star8(cx, cy, r: float): Path =
      var pts: seq[(float, float)]
      for k in 0 .. 15:
        let a = k.float * PI / 8 - PI / 2
        let rr = if k mod 2 == 0: r else: r * 0.76
        pts.add (cx + cos(a) * rr, cy + sin(a) * rr)
      poly(pts)
    s.add (star8(60, 60, 50), 0xFF0F5C63'u32)
    s.add (star8(60, 60, 30), 0xFFF4D35E'u32)
    for (cx, cy) in [(0.0, 0.0)]:
      s.add (star8(cx, cy, 22), 0xFFB5838D'u32)
    p("khatam", "Khatam Stars", "Arabic & Islamic", n, tile(n, 0xFFF5EBDD'u32, s),
      @["islamic", "arabic", "star", "tile", "geometric"])
  block:
    var s: seq[(Path, uint32)]
    for (cx, cy) in [(0.0, 0.0), (60.0, 0.0), (0.0, 60.0), (60.0, 60.0), (30.0, 30.0), (90.0, 30.0),
                     (30.0, 90.0), (90.0, 90.0)]:
      s.add (ring(cx, cy, 30, 2.5), 0xFFC9A227'u32)
    p("arabesque", "Arabesque Circles", "Arabic & Islamic", n, tile(n, 0xFF14213D'u32, s),
      @["arabesque", "circles", "islamic", "lattice"])
  block:
    var s: seq[(Path, uint32)]
    for k in 0 .. 3:
      let x = k.float * 30
      s.add (poly([(x, 0.0), (x + 30, 30.0), (x + 30, 50.0), (x, 20.0)]), 0xFF9C6644'u32)
      s.add (poly([(x + 30, 60.0), (x, 90.0), (x, 110.0), (x + 30, 80.0)]), 0xFF7F5539'u32)
    p("herringbone", "Herringbone", "Classic", n, tile(n, 0xFFE6CCB2'u32, s), @["herringbone", "wood", "floor"])
  block:
    var s: seq[(Path, uint32)]
    for j in 0 .. 3:
      for i in 0 .. 3:
        let x = i.float * 30
        let y = j.float * 30
        s.add (poly([(x, y + 30), (x + 15, y), (x + 30, y + 30)]),
               [0xFFE63946'u32, 0xFFF1FAEE'u32, 0xFFA8DADC'u32, 0xFF457B9D'u32][(i + j * 2) mod 4])
    p("triangles", "Triangles", "Geometric", n, tile(n, 0xFF1D3557'u32, s), @["triangles", "geometric"])
  block:
    var s: seq[(Path, uint32)]
    s.add (poly([(60.0, 0.0), (120.0, 60.0), (60.0, 120.0), (0.0, 60.0)]), 0xFF6A994E'u32)
    s.add (poly([(60.0, 20.0), (100.0, 60.0), (60.0, 100.0), (20.0, 60.0)]), 0xFFA7C957'u32)
    p("argyle", "Argyle", "Classic", n, tile(n, 0xFF386641'u32, s), @["argyle", "diamonds"])
  block:
    var s: seq[(Path, uint32)]
    var r = initRand(9)
    for k in 0 .. 6:
      let cx = r.rand(120.0)
      let cy = r.rand(120.0)
      let rr = 6 + r.rand(8.0)
      s.add (polygonPath(cx - rr, cy - rr, cx + rr, cy + rr, 5, star = true, indent = 55), 0xFFFFD166'u32)
    p("stars", "Starry Night", "Geometric", n, tile(n, 0xFF0B132B'u32, s), @["stars", "night", "sky"])
  block:
    var s: seq[(Path, uint32)]
    for (cx, cy) in [(0.0, 0.0), (60.0, 60.0), (120.0, 0.0), (0.0, 120.0), (120.0, 120.0)]:
      var q = ellipsePath(cx - 38, cy - 22, cx + 38, cy + 22)
      q.combine(ellipsePath(cx - 22, cy - 38, cx + 22, cy + 38), poAdd)
      s.add (q, 0xFFFFFFFF'u32)
    for (cx, cy) in [(0.0, 0.0), (60.0, 60.0), (120.0, 0.0), (0.0, 120.0), (120.0, 120.0)]:
      var q = ellipsePath(cx - 33, cy - 17, cx + 33, cy + 17)
      q.combine(ellipsePath(cx - 17, cy - 33, cx + 17, cy + 33), poAdd)
      s.add (q, 0xFF2A9D8F'u32)
    p("trellis", "Moroccan Trellis", "Arabic & Islamic", n, tile(n, 0xFFFFFFFF'u32, s),
      @["moroccan", "trellis", "quatrefoil"])
  block:
    var s: seq[(Path, uint32)]
    for j in 0 .. 3:
      let off = if j mod 2 == 0: 0.0 else: 30.0
      for i in -1 .. 2:
        let x = i.float * 60 + off
        let y = j.float * 30
        s.add (rectPath(x + 2, y + 2, x + 58, y + 28, 2), 0xFFB5523B'u32)
    p("bricks", "Bricks", "Classic", n, tile(n, 0xFFD8D3CD'u32, s), @["bricks", "wall"])
  for (id, title, cat, tw, tht, px, tags) in list:
    var b = newBitmap(tw, tht)
    b.px = px
    b.changed()
    writeFile(Out / "patterns" / id & ".png", encodePng(b))
    var th = newBitmap(160, 160)
    for y in 0 ..< 160:
      for x in 0 ..< 160: th.px[y * 160 + x] = px[(y mod tht) * tw + (x mod tw)]
    th.changed()
    add(id, title, "pattern", cat, "patterns/" & id & ".png", "png", th, tags)

# ---- gradients ----------------------------------------------------------------------------------------------

proc gradients() =
  createDir(Out / "gradients")
  let list = [
    ("sunset", "Sunset", "Warm", @[0xFF2B1055'u32, 0xFFD53A9D'u32, 0xFFFF7E5F'u32, 0xFFFEB47B'u32]),
    ("desert", "Desert Sand", "Warm", @[0xFF8B5E34'u32, 0xFFD4A373'u32, 0xFFFAEDCD'u32]),
    ("peach", "Peach", "Warm", @[0xFFFFDAB9'u32, 0xFFFFB4A2'u32, 0xFFE5989B'u32]),
    ("ocean", "Ocean", "Cool", @[0xFF03045E'u32, 0xFF0077B6'u32, 0xFF00B4D8'u32, 0xFF90E0EF'u32]),
    ("mint", "Mint", "Cool", @[0xFFD8F3DC'u32, 0xFF74C69D'u32, 0xFF2D6A4F'u32]),
    ("royal", "Royal Night", "Cool", @[0xFF0B132B'u32, 0xFF3A0CA3'u32, 0xFF7209B7'u32]),
    ("gold", "Gold Foil", "Metal", @[0xFF8A5A10'u32, 0xFFF6E27A'u32, 0xFFB8860B'u32, 0xFFFFF1B5'u32, 0xFF8A5A10'u32]),
    ("silver", "Silver", "Metal", @[0xFF5A5F66'u32, 0xFFE6E9ED'u32, 0xFF8E949C'u32, 0xFFF7F8FA'u32, 0xFF5A5F66'u32]),
    ("rosegold", "Rose Gold", "Metal", @[0xFFB76E79'u32, 0xFFF4C2C2'u32, 0xFFB76E79'u32, 0xFFFAD6D6'u32]),
    ("neon", "Neon Night", "Colors", @[0xFFFF006E'u32, 0xFF8338EC'u32, 0xFF3A86FF'u32]),
    ("oman", "Oman Flag", "Colors", @[0xFFDB161B'u32, 0xFFFFFFFF'u32, 0xFF008000'u32]),
    ("rainbow", "Soft Rainbow", "Colors", @[0xFFFFADAD'u32, 0xFFFFD6A5'u32, 0xFFFDFFB6'u32, 0xFFCAFFBF'u32,
                                            0xFF9BF6FF'u32, 0xFFA0C4FF'u32, 0xFFBDB2FF'u32])]
  for (id, title, cat, cols) in list:
    var stops = newJArray()
    var gs: seq[GradientStop]
    for k, c in cols:
      let at = k / max(1, cols.high)
      gs.add GradientStop(at: at, color: c, mid: 0.5)
      stops.add %*{"at": at, "color": "#" & toHex(c and 0xFFFFFF'u32, 6), "alpha": int(c shr 24), "mid": 0.5}
    writeFile(Out / "gradients" / id & ".json", $(%*{"retroGradient": 1, "name": title, "stops": stops}))
    var th = newBitmap(160, 80)
    for x in 0 ..< 160:
      let t = x / 159
      var c = cols[^1]
      for k in 0 ..< gs.high:
        if t >= gs[k].at and t <= gs[k + 1].at:
          let f = (t - gs[k].at) / max(1e-6, gs[k + 1].at - gs[k].at)
          let a = gs[k].color
          let b = gs[k + 1].color
          template mixc(s: int): int = int(float((a shr s) and 255) * (1 - f) + float((b shr s) and 255) * f + 0.5)
          c = argb(255, mixc(16), mixc(8), mixc(0))
          break
      for y in 0 ..< 80: th.px[y * 160 + x] = c
    th.changed()
    add(id, title, "gradient", cat, "gradients/" & id & ".json", "json", th, @[title.toLowerAscii])

# ---- swatches ----------------------------------------------------------------------------------------------

proc swatchSets() =
  createDir(Out / "swatches")
  let list = [
    ("oman", "Oman Flag", "Flags & Brands", @[("Red", 0xFFDB161B'u32), ("White", 0xFFFFFFFF'u32),
                                               ("Green", 0xFF008000'u32)]),
    ("desert", "Desert Earth", "Nature", @[("Dune", 0xFFE9C46A'u32), ("Clay", 0xFFE76F51'u32),
                                          ("Rock", 0xFF8D6346'u32), ("Palm", 0xFF2A9D8F'u32), ("Night", 0xFF264653'u32)]),
    ("hotel", "Luxury Hotel", "Business", @[("Gold", 0xFFC9A227'u32), ("Black", 0xFF111111'u32),
                                           ("Cream", 0xFFF5EBDD'u32), ("Bronze", 0xFF8C6239'u32),
                                           ("Charcoal", 0xFF3D3D3D'u32)]),
    ("corporate", "Corporate Blues", "Business", @[("Navy", 0xFF14213D'u32), ("Blue", 0xFF1D4E89'u32),
                                                  ("Sky", 0xFF4A90D9'u32), ("Ice", 0xFFDCEAF7'u32),
                                                  ("Accent", 0xFFF2A541'u32)]),
    ("pastel", "Pastel Spring", "Nature", @[("Pink", 0xFFFFC8DD'u32), ("Lilac", 0xFFCDB4DB'u32),
                                           ("Baby Blue", 0xFFBDE0FE'u32), ("Mint", 0xFFCAFFBF'u32),
                                           ("Butter", 0xFFFDFFB6'u32)]),
    ("sea", "Sea and Sand", "Nature", @[("Deep", 0xFF03045E'u32), ("Sea", 0xFF0077B6'u32),
                                       ("Lagoon", 0xFF48CAE4'u32), ("Foam", 0xFFCAF0F8'u32), ("Sand", 0xFFF4E1C1'u32)])]
  for (id, title, cat, cols) in list:
    var sw: seq[Swatch]
    for (n, c) in cols: sw.add (n, c)
    writeFile(Out / "swatches" / id & ".ase", writeAse(sw))
    var th = newBitmap(160, 80)
    let w = 160 div cols.len
    for x in 0 ..< 160:
      let c = cols[min(cols.high, x div w)][1]
      for y in 0 ..< 80: th.px[y * 160 + x] = c
    th.changed()
    add(id, title, "swatches", cat, "swatches/" & id & ".ase", "ase", th, @[title.toLowerAscii])

# ---- styles ------------------------------------------------------------------------------------------------

proc styleThumb(fx: LayerFx): Bitmap =
  let n = 160
  let d = newDoc(n, n, 0'u32)
  discard d.addShapeLayer(ShapeData(path: rectPath(30, 30, 130, 130, 22), fill: solidPaint(0xFF7A8AA0'u32)), "S")
  d.layers[^1].fx = fx
  d.markAll()
  d.updateComposite()
  bitmapOf(d.compCopy, n, n, 0xFFDADDE2'u32)

proc styles() =
  createDir(Out / "styles")
  var list: seq[(string, string, string, LayerFx)]
  template st(id, title, cat: string; body: untyped) =
    block:
      var fx {.inject.}: LayerFx
      template eff(k: FxKind; b2: untyped) =
        block:
          var e {.inject.} = defaultEffect(k)
          e.on = true
          b2
          fx.fx[k] = e
      body
      list.add (id, title, cat, fx)
  st("goldfoil", "Gold Foil", "Metal"):
    eff fxGradientOverlay:
      e.color = 0xFF8A5A10'u32; e.color2 = 0xFFF6E27A'u32; e.angle = 90
    eff fxBevel:
      e.size = 5; e.depth = 160; e.soften = 1
    eff fxStroke:
      e.color = 0xFF6B4A12'u32; e.size = 1
  st("rosegold", "Rose Gold", "Metal"):
    eff fxGradientOverlay:
      e.color = 0xFFB76E79'u32; e.color2 = 0xFFFAD6D6'u32; e.angle = 90
    eff fxBevel:
      e.size = 4; e.depth = 120
  st("silver", "Brushed Silver", "Metal"):
    eff fxGradientOverlay:
      e.color = 0xFF6B717A'u32; e.color2 = 0xFFF2F4F7'u32; e.angle = 90
    eff fxBevel:
      e.size = 4; e.depth = 200
    eff fxDropShadow:
      e.opacity = 40; e.distance = 3; e.size = 5
  st("neonpink", "Neon Pink", "Glow"):
    eff fxColorOverlay: e.color = 0xFFFFE6F2'u32
    eff fxOuterGlow:
      e.color = 0xFFFF2E93'u32; e.size = 18; e.opacity = 95
    eff fxInnerGlow:
      e.color = 0xFFFF2E93'u32; e.size = 5
  st("iceglow", "Ice Glow", "Glow"):
    eff fxColorOverlay: e.color = 0xFFEFFFFF'u32
    eff fxOuterGlow:
      e.color = 0xFF7FDBFF'u32; e.size = 14; e.opacity = 85
  st("softglow", "Soft White Glow", "Glow"):
    eff fxOuterGlow:
      e.color = 0xFFFFFFFF'u32; e.size = 22; e.opacity = 75
  st("letterpress", "Letterpress", "Classic"):
    eff fxInnerShadow:
      e.distance = 2; e.size = 3; e.opacity = 60
    eff fxDropShadow:
      e.color = 0xFFFFFFFF'u32; e.mode = bmNormal; e.distance = 1; e.size = 0; e.opacity = 70
  st("retro3d", "Retro 3D", "Classic"):
    eff fxStroke:
      e.color = 0xFF14213D'u32; e.size = 3
    eff fxDropShadow:
      e.color = 0xFFF2A541'u32; e.mode = bmNormal; e.distance = 8; e.size = 0; e.spread = 100; e.opacity = 100
  st("sticker", "Die-Cut Sticker", "Classic"):
    eff fxStroke:
      e.color = 0xFFFFFFFF'u32; e.size = 10
    eff fxDropShadow:
      e.distance = 5; e.size = 10; e.opacity = 45
  st("embossed", "Embossed Paper", "Classic"):
    eff fxColorOverlay: e.color = 0xFFF5EBDD'u32
    eff fxBevel:
      e.style = 2; e.size = 4; e.soften = 2; e.depth = 80
  for (id, title, cat, fx) in list:
    writeFile(Out / "styles" / id & ".json", $(%*{"retroStyle": 1, "name": title, "fx": toJson(fx)}))
    add(id, title, "style", cat, "styles/" & id & ".json", "json", styleThumb(fx), @[title.toLowerAscii])

# ---- designs (the templates) -----------------------------------------------------------------------------------

proc designs() =
  var seen: seq[string]
  for t in docTemplates():
    if t.name in seen: continue
    seen.add t.name
    let id = t.name.toLowerAscii.multiReplace((" ", "-"), ("'", ""))
    add(id, t.name, "design", $t.category, "template:" & t.name, "template", templateThumb(t, 200),
        @[t.name.toLowerAscii, ($t.category).toLowerAscii])

proc strokeThumb(p: BrushPreset): Bitmap =
  if p.tip.custom.len > 0:
    # (a sampled tip: the tip itself, big, beside a short stroke)
    result = newBitmap(160, 80)
    for v in result.px.mitems: v = 0xFFFFFFFF'u32
    let side = 72
    let m = tipPreview(p.tip, side)
    for y in 0 ..< side:
      for x in 0 ..< side:
        let a = int(m[y * side + x])
        result.px[(y + 4) * 160 + x + 4] = blendPx(0xFFFFFFFF'u32, 0xFF000000'u32, a, bmNormal)
    var q = p
    q.dyn.scatter = min(q.dyn.scatter, 80)
    let st = strokePreview(q, 80, 80)
    for y in 0 ..< 80:
      for x in 0 ..< 80: result.px[y * 160 + 80 + x] = st[y * 80 + x]
    result.changed()
    return
  let px = strokePreview(p, 160, 80)
  result = newBitmap(160, 80)
  for i in 0 ..< min(px.len, result.px.len): result.px[i] = px[i]
  result.changed()

createDir(Out)
brushes()
patterns()
gradients()
swatchSets()
styles()
designs()
writeFile(Out / "catalog.json", pretty(%*{"version": 1, "name": "Retro Photo Library", "license": "CC0",
                                        "items": catalog}))
# (the same files inside the app: it works offline, the online catalog adds to them)
var nimSrc = "# Retro Photo -- included by photo.nim. Made by tools/genlibrary.nim: do not edit.\n" &
             "# The Retro Photo Library carried in the app (library/: the same files that go online).\n\n" &
             "const bundledLibrary = [\n"
for f in walkDirRec(Out, relative = true):
  if f.endsWith(".part"): continue
  nimSrc.add "  (\"" & f.replace("\\", "/") & "\", staticRead(\"../../library/" & f.replace("\\", "/") & "\")),\n"
nimSrc.add "]\n"
writeFile("examples/photo/librarydata.nim", nimSrc)
echo catalog.len, " items in ", Out
