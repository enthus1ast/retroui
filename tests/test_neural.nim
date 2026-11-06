## Tests of the Neural Filters made without a network (retroui/photoneural):
## each does what it says on pictures made for it.

import std/[math]
import retroui/[gfx, jpeg, photo, photofx, photoneural]

proc scene(w, h: int): Img =
  ## A sky going lighter, green ground, a red "subject" in the middle.
  result = newImg(w, h)
  for y in 0 ..< h:
    for x in 0 ..< w:
      var c = if y < h * 6 div 10: argb(255, 90 + y * 100 div h, 140 + y * 80 div h, 230)
              else: argb(255, 40, 120 + (x * 7 + y * 3) mod 40, 50)
      # (a few sharp details in the sky and on the ground)
      if (x mod 23 == 0 and y < h div 2) or (y mod 17 == 0 and y > h * 7 div 10): c = argb(255, 255, 255, 255)
      let dx = (x - w div 2).float / (w.float * 0.12)
      let dy = (y - h * 55 div 100).float / (h.float * 0.3)
      if dx * dx + dy * dy <= 1: c = argb(255, 210, 40, 40)
      result.px[y * w + x] = c

proc blockiness(im: Img): float =
  ## How much bigger the steps at 8-pixel edges are than elsewhere.
  var atEdge, inside = 0.0
  var ne, ni = 0
  for y in 0 ..< im.h:
    for x in 1 ..< im.w:
      let a = im.px[y * im.w + x - 1]
      let b = im.px[y * im.w + x]
      let d = abs(int((a shr 8) and 255) - int((b shr 8) and 255)).float
      if x mod 8 == 0:
        atEdge += d; inc ne
      else:
        inside += d; inc ni
  (atEdge / ne.float) / max(0.01, inside / ni.float)

block jpegArtifacts:
  # a smooth gradient saved at a low quality: blocky; cleaned: much less so
  let w = 128
  let h = 96
  let b = newBitmap(w, h)
  for y in 0 ..< h:
    for x in 0 ..< w: b.px[y * w + x] = argb(255, x * 2, 80 + y, 200 - x)
  let jp = decodeJpeg(encodeJpeg(b, quality = 12))
  let src = Img(w: w, h: h, px: jp.px)
  let before = blockiness(src)
  let after = blockiness(jpegCleanImg(src, 2))
  doAssert before > 1.3, "the JPEG is blocky: " & $before
  doAssert after < before * 0.75, "less blocky: " & $before & " -> " & $after

block restoration:
  # a white scratch across a gray picture: gone
  var im = newImg(80, 60)
  for p in im.px.mitems: p = 0xFF707070'u32
  for x in 0 ..< 80: im.px[30 * 80 + x] = 0xFFFFFFFF'u32
  let o = restoreImg(im, enhance = 0, scratches = 60, noise = 0, colorNoise = 0)
  doAssert ((o.px[30 * 80 + 40] shr 8) and 255) < 0x90, "the scratch is gone"

block depthBlur:
  # the subject stays sharp; the sky's details (far) go soft
  let im = scene(240, 160)
  var subj = newSeq[uint8](240 * 160)
  for y in 0 ..< 160:
    for x in 0 ..< 240:
      let dx = (x - 120).float / (240 * 0.12)
      let dy = (y - 88).float / (160 * 0.3)
      if dx * dx + dy * dy <= 1: subj[y * 240 + x] = 255
  let depth = depthMapOf(im, subj)
  doAssert depth[88 * 240 + 120] < 40, "the subject is near: " & $depth[88 * 240 + 120]
  doAssert depth[10 * 240 + 20] > depth[150 * 240 + 20], "the top is farther than the bottom"
  let o = depthBlurImg(im, depth, strength = 80)
  # (a white line of the sky: spread out now)
  let sky0 = im.px[20 * 240 + 23]
  let sky1 = o.px[20 * 240 + 23]
  doAssert (sky1 and 0xFF) < (sky0 and 0xFF) or ((sky1 shr 16) and 255) < ((sky0 shr 16) and 255),
    "the far detail is blurred"
  doAssert o.px[88 * 240 + 120] == im.px[88 * 240 + 120] or
           abs(int((o.px[88 * 240 + 120] shr 16) and 255) - 210) < 6, "the subject is sharp"

block colorTransfer:
  # gray-blue picture given a warm look: its mean color moves that way
  let im = scene(120, 80)
  let warm = ColorStats(mean: [62.0, 14, 34], sd: [22.0, 10, 18])
  let o = colorTransferImg(im, warm)
  let a = colorStatsOf(im.px)
  let b = colorStatsOf(o.px)
  doAssert b.mean[2] > a.mean[2] + 15, "warmer (more yellow): " & $a.mean[2] & " -> " & $b.mean[2]
  doAssert abs(b.mean[2] - 34) < 8
  let faded = colorTransferImg(im, warm, fade = 100)
  doAssert faded.px == im.px, "faded all the way: as it was"

block superZoom:
  # twice the size; a hard edge stays hard (no wide soft band)
  var im = newImg(40, 30)
  for y in 0 ..< 30:
    for x in 0 ..< 40: im.px[y * 40 + x] = if x < 20: 0xFF000000'u32 else: 0xFFFFFFFF'u32
  let o = superZoomImg(im, 2, details = 60)
  doAssert (o.w, o.h) == (80, 60)
  var soft = 0
  for x in 0 ..< 80:
    let v = int(o.px[30 * 80 + x] and 255)
    if v > 40 and v < 215: inc soft
  doAssert soft <= 3, "the edge is sharp: " & $soft & " soft pixels"

echo "neural filter tests passed"
