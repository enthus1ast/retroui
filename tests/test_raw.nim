## Tests of retro/rawphoto: DNG raw photos read (uncompressed and lossless
## JPEG), the mosaic filled in, developed as light.

import std/[unittest, math, random]
import retro/[rawphoto, photo, photofx, photodevelop]

proc w16(o: var string; v: int) = (o.add char(v and 255); o.add char((v shr 8) and 255))
proc w32(o: var string; v: int) =
  o.add char(v and 255); o.add char((v shr 8) and 255); o.add char((v shr 16) and 255); o.add char((v shr 24) and 255)

proc scene(w, h: int): seq[array[3, float]] =
  ## Light: smooth colors, a few edges.
  result = newSeq[array[3, float]](w * h)
  for y in 0 ..< h:
    for x in 0 ..< w:
      let fx = x.float / w.float
      let fy = y.float / h.float
      var c = [0.15 + 0.6 * fx, 0.2 + 0.5 * fy, 0.5 - 0.3 * fx]
      if (x div 16 + y div 16) mod 3 == 0: c = [c[0] * 0.5, c[1] * 0.5, c[2] * 0.5]
      result[y * w + x] = c

proc dng(w, h: int; lj92: bool; orient = 1): string =
  ## A small DNG: an RGGB mosaic, 12 bits over a black of 64.
  let sc = scene(w, h)
  var samples = newSeq[uint16](w * h)
  let pat = [0, 1, 1, 2]
  for y in 0 ..< h:
    for x in 0 ..< w:
      let c = pat[(y and 1) * 2 + (x and 1)]
      samples[y * w + x] = uint16(64 + int(round(sc[y * w + x][c] * (4095 - 64))))
  var data = ""
  if lj92: data = encodeLj92(samples, w, h)
  else:
    for v in samples: data.w16(int(v))
  # the matrix that makes the camera's colors sRGB's as they are
  let xyzRgb = [0.412453, 0.357580, 0.180423, 0.212671, 0.715160, 0.072169, 0.019334, 0.119193, 0.950227]
  # (its inverse, worked out here)
  let (a, b, c, d, e, f, g, hh, i) = (xyzRgb[0], xyzRgb[1], xyzRgb[2], xyzRgb[3], xyzRgb[4], xyzRgb[5],
                                      xyzRgb[6], xyzRgb[7], xyzRgb[8])
  let A = e * i - f * hh
  let B = -(d * i - f * g)
  let C = d * hh - e * g
  let det = a * A + b * B + c * C
  let inv = [A / det, -(b * i - c * hh) / det, (b * f - c * e) / det, B / det, (a * i - c * g) / det,
             -(a * f - c * d) / det, C / det, -(a * hh - b * g) / det, (a * e - b * d) / det]
  var o = "II*\0"
  o.w32(0)
  let dataAt = o.len
  o.add data
  if (o.len and 1) == 1: o.add '\0'
  # values that do not fit
  let cmAt = o.len
  for v in inv:
    o.w32(int(round(v * 1_000_000)))
    o.w32(1_000_000)
  let neutralAt = o.len
  for v in [1, 1, 1]:
    o.w32(v); o.w32(1)
  let ifd = o.len
  o[4] = char(ifd and 255); o[5] = char((ifd shr 8) and 255); o[6] = char((ifd shr 16) and 255); o[7] = char(ifd shr 24)
  var tags: seq[(int, int, int, int)]
  tags.add (254, 4, 1, 0)
  tags.add (256, 4, 1, w)
  tags.add (257, 4, 1, h)
  tags.add (258, 3, 1, 16)
  tags.add (259, 3, 1, if lj92: 7 else: 1)
  tags.add (262, 3, 1, 32803)
  tags.add (273, 4, 1, dataAt)
  tags.add (274, 3, 1, orient)
  tags.add (277, 3, 1, 1)
  tags.add (278, 4, 1, h)
  tags.add (279, 4, 1, data.len)
  tags.add (33421, 3, 2, 2 or (2 shl 16))
  tags.add (33422, 1, 4, 0 or (1 shl 8) or (1 shl 16) or (2 shl 24))
  tags.add (50706, 1, 4, 1 or (4 shl 8))
  tags.add (50714, 3, 1, 64)
  tags.add (50717, 3, 1, 4095)
  tags.add (50721, 10, 9, cmAt)
  tags.add (50728, 5, 3, neutralAt)
  tags.add (50778, 3, 1, 21)
  o.w16(tags.len)
  for (tag, kind, cnt, v) in tags:
    o.w16(tag); o.w16(kind); o.w32(cnt); o.w32(v)
  o.w32(0)
  o

suite "raw photos":
  test "lossless JPEG, there and back":
    var r = initRand(5)
    var px = newSeq[uint16](37 * 23)
    for v in px.mitems: v = uint16(r.rand(65535))
    let j = decodeLj92(encodeLj92(px, 37, 23), 0, high(int) shr 1)
    check j.w == 37 and j.h == 23 and j.comps == 1 and j.px == px
    var smooth = newSeq[uint16](64 * 64)
    for i, v in smooth.mpairs: v = uint16(1000 + (i mod 64) * 3)
    let enc = encodeLj92(smooth, 64, 64, 12)
    check enc.len < 64 * 64
    check decodeLj92(enc, 0, enc.len).px == smooth

  test "a DNG: the light as it was":
    for lj in [false, true]:
      let data = dng(96, 64, lj)
      check isDng(data)
      let raw = readDng(data)
      check raw.w == 96 and raw.h == 64
      let sc = scene(96, 64)
      var err = 0.0
      var n = 0
      for y in 4 ..< 60:
        for x in 4 ..< 92:
          if x mod 16 in 0 .. 1 or x mod 16 in 14 .. 15 or y mod 16 in 0 .. 1 or y mod 16 in 14 .. 15: continue
          for c in 0 .. 2:
            err += abs(raw.px[(y * 96 + x) * 3 + c] - sc[y * 96 + x][c])
            inc n
      check err / n.float < 0.01
    check not isDng("II*\0\x08\0\0\0\0\0")
    expect RawError: discard readDng("not a raw file at all, no")

  test "turned as the camera was held":
    let raw = readDng(dng(48, 32, false, orient = 6))
    check raw.w == 32 and raw.h == 48

  test "developed: exposure and white balance in the light":
    let raw = readDng(dng(96, 64, true))
    let a = developRaw(raw, Develop())
    let b = developRaw(raw, Develop(exposure: 100))
    let c = developRaw(raw, Develop(temperature: 60))
    check a.w == 96 and (a.px[0] shr 24) == 255
    var la, lb = 0
    for i in 0 ..< a.px.len:
      la += lumaOf(a.px[i]); lb += lumaOf(b.px[i])
    check lb > la
    check rOf(c.px[40 * 96 + 50]) > rOf(a.px[40 * 96 + 50]) and bOf(c.px[40 * 96 + 50]) < bOf(a.px[40 * 96 + 50])
    # very bright light rolls off rather than cut flat
    var hot = RawImage(w: 2, h: 1, px: @[2.0'f32, 2.0, 2.0, 0.9, 0.9, 0.9])
    let hp = developRaw(hot, Develop())
    check rOf(hp.px[0]) == 255 and rOf(hp.px[1]) < 255 and rOf(hp.px[1]) > 200
    let d = docOfRaw(raw, "raw", Develop(exposure: 50, contrast: 20))
    check d.w == 96 and d.layers[0].px.len == 96 * 64
    let s = raw.smaller(40)
    check s.w == 40 and s.h == 26
