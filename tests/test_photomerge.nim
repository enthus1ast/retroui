## Tests of retroui/photomerge: matching and aligning pictures, panoramas,
## focus stacks, exposure fusion, Surface Blur, skin and skies.

import std/[unittest, math, random]
import retroui/[photo, photofx, photomerge]

proc scene(w, h: int; seed = 3): Img =
  ## Something with corners: boxes and discs of many colors on a gradient.
  var r = initRand(seed)
  result = newImg(w, h)
  for y in 0 ..< h:
    for x in 0 ..< w:
      result.px[y * w + x] = argb(255, 60 + x * 120 div w, 80, 60 + y * 120 div h)
  for _ in 0 ..< (w * h) div 900:
    let c = argb(255, r.rand(255), r.rand(255), r.rand(255))
    let cx = r.rand(w - 1)
    let cy = r.rand(h - 1)
    let s = 4 + r.rand(18)
    if r.rand(1) == 0:
      for y in max(0, cy - s) .. min(h - 1, cy + s):
        for x in max(0, cx - s div 2) .. min(w - 1, cx + s):
          result.px[y * w + x] = c
    else:
      for y in max(0, cy - s) .. min(h - 1, cy + s):
        for x in max(0, cx - s) .. min(w - 1, cx + s):
          if (x - cx) ^ 2 + (y - cy) ^ 2 <= s * s: result.px[y * w + x] = c

proc crop(im: Img; x, y, w, h: int): Img =
  result = newImg(w, h)
  for yy in 0 ..< h:
    for xx in 0 ..< w: result.px[yy * w + xx] = im.px[(y + yy) * im.w + x + xx]

proc lum(p: uint32): float = (float(rOf(p)) + float(gOf(p)) + float(bOf(p))) / 3

suite "aligning":
  test "two crops of one scene: how far apart":
    let big = scene(900, 500)
    let a = crop(big, 0, 20, 560, 420)
    let b = crop(big, 330, 50, 560, 420)
    let fa = featuresOf(a)
    let fb = featuresOf(b)
    check fa.len > 80 and fb.len > 80
    for model in AlignModel:
      let m = matchPair(fa, fb, model)
      check m.ok
      # b's (0, 0) is a's (330, 30)
      let (x, y) = m.h.apply(0, 0)
      check abs(x - 330) < 1.5 and abs(y - 30) < 1.5
      let (x2, y2) = m.h.apply(500, 400)
      check abs(x2 - 830) < 2 and abs(y2 - 430) < 2

  test "a turned and scaled copy":
    let a = scene(640, 480, 5)
    let t = 8.0 * PI / 180
    let s = 0.9
    let h: Homography = [s * cos(t), -s * sin(t), 40, s * sin(t), s * cos(t), 10, 0, 0, 1]
    let b = Img(w: 640, h: 480, px: warp(a, inverse(h), 640, 480))
    let m = matchPair(featuresOf(a), featuresOf(b), amSimilarity)
    check m.ok
    for (x, y) in [(200.0, 150.0), (400.0, 300.0)]:
      let (u, v) = m.h.apply(x, y)
      let (eu, ev) = h.apply(x, y)
      check abs(u - eu) < 2 and abs(v - ev) < 2

  test "pictures that share nothing":
    let a = scene(400, 300, 11)
    let b = scene(400, 300, 12)
    check not matchPair(featuresOf(a), featuresOf(b), amPerspective).ok

suite "panoramas":
  test "three pictures, in the wrong order, put together":
    let big = scene(1200, 500, 7)
    let left = crop(big, 0, 0, 500, 500)
    let mid = crop(big, 350, 0, 500, 500)
    let right = crop(big, 700, 0, 500, 500)
    let p = photomerge(@[right, left, mid], amTranslation)
    check p.left.len == 0 and p.used.len == 3
    check abs(p.w - 1200) <= 2 and abs(p.h - 500) <= 2
    check p.masks.len == 3
    # the layers mixed by their masks: the scene again
    var bad = 0
    for y in countup(5, p.h - 6, 7):
      for x in countup(5, p.w - 6, 7):
        var c = 0'u32
        for k in 0 ..< 3:
          let L = p.layers[k][y * p.w + x]
          let a = int(L shr 24) * int(p.masks[k][y * p.w + x]) div 255
          if a > 0: c = mix(c, L or 0xFF000000'u32, a / 255)
        let ox = x + (if p.w > 1200: 0 else: 0)
        if abs(lum(c) - lum(big.px[min(499, y) * 1200 + min(1199, ox)])) > 40: inc bad
    check bad < 40
    let r = p.fullRect()
    check r.w >= 1190 and r.h >= 490

suite "stacks":
  test "focus: each part from the picture where it is sharp":
    let sharp = scene(300, 200, 9)
    let soft = Img(w: 300, h: 200, px: gaussianBlur(4)(sharp, rect(0, 0, 300, 200)).px)
    var a = newImg(300, 200)
    var b = newImg(300, 200)
    for y in 0 ..< 200:
      for x in 0 ..< 300:
        let i = y * 300 + x
        a.px[i] = if x < 150: sharp.px[i] else: soft.px[i]
        b.px[i] = if x < 150: soft.px[i] else: sharp.px[i]
    let m = focusStackMasks(@[a, b])
    check m.len == 2
    var leftB, rightB = 0
    for y in 20 ..< 180:
      for x in 20 ..< 120: leftB += int(m[1][y * 300 + x])
      for x in 180 ..< 280: rightB += int(m[1][y * 300 + x])
    check rightB > leftB * 4

  test "exposures fused":
    let s = scene(256, 192, 4)
    var dark = newImg(256, 192)
    var bright = newImg(256, 192)
    for i, p in s.px:
      dark.px[i] = argb(255, rOf(p) div 4, gOf(p) div 4, bOf(p) div 4)
      bright.px[i] = argb(255, min(255, rOf(p) * 3), min(255, gOf(p) * 3), min(255, bOf(p) * 3))
    let f = exposureFusion(@[dark, bright])
    check f.w == 256 and f.h == 192
    var md, mb, mf = 0.0
    for i in 0 ..< f.px.len:
      md += lum(dark.px[i]); mb += lum(bright.px[i]); mf += lum(f.px[i])
    check mf > md and mf < mb
    check (f.px[0] shr 24) == 255

suite "retouching":
  test "Surface Blur: smooth flat parts, keep the edges":
    var r = initRand(2)
    var im = newImg(80, 40)
    for y in 0 ..< 40:
      for x in 0 ..< 80:
        let base = if x < 40: 60 else: 200
        let v = clamp(base + r.rand(20) - 10, 0, 255)
        im.px[y * 80 + x] = argb(255, v, v, v)
    let o = surfaceBlurImg(im, 5, 30)
    proc spread(m: Img; x0, x1: int): float =
      var s, s2 = 0.0
      var n = 0
      for y in 5 ..< 35:
        for x in x0 ..< x1:
          let v = rOf(m.px[y * 80 + x]).float
          s += v; s2 += v * v; inc n
      sqrt(s2 / n.float - (s / n.float) ^ 2)
    check spread(o, 5, 30) < spread(im, 5, 30) / 2
    # the edge: still a step
    check rOf(o.px[20 * 80 + 37]) < 100 and rOf(o.px[20 * 80 + 42]) > 160

  test "skin":
    var im = newImg(3, 1)
    im.px[0] = argb(255, 224, 172, 140)     # skin
    im.px[1] = argb(255, 40, 90, 200)       # sky
    im.px[2] = argb(255, 120, 72, 50)       # darker skin
    let p = skinProbability(im)
    check p[0] > 200 and p[1] == 0 and p[2] > 120
    var face = newImg(60, 20)
    for y in 0 ..< 20:
      for x in 0 ..< 60:
        face.px[y * 60 + x] = if x < 30: argb(255, 224 + (x * 7 + y * 3) mod 9, 172, 140) else: im.px[1]
    let s = skinSmoothingImg(face, 3, 80)
    check s.w == 60 and s.px[10 * 60 + 58] == face.px[10 * 60 + 58]
    var changed = 0
    for x in 0 ..< 25:
      if s.px[10 * 60 + x] != face.px[10 * 60 + x]: inc changed
    check changed > 10

suite "skies":
  test "skies painted and placed":
    for k in SkyKind:
      let s = makeSky(k, 120, 80)
      check s.w == 120 and s.h == 80
      check (s.px[0] shr 24) == 255
    let blue = makeSky(skBlue, 50, 100)
    check lum(blue.px[0]) < lum(blue.px[99 * 50])
    var mask = newSeq[uint8](40 * 30)
    for y in 0 ..< 12:
      for x in 0 ..< 40: mask[y * 40 + x] = 255
    check skyHorizon(mask, 40, 30) == 12
    let placed = placeSky(blue, 40, 30, 12)
    check placed.w == 40 and placed.h == 30
    var m2 = mask
    shiftEdge(m2, 40, 30, 3)
    var more = 0
    for i in 0 ..< m2.len:
      if m2[i] > mask[i]: inc more
    check more > 0
