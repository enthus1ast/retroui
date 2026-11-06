## Tests of `retroui/photohdr`: 32 bits a channel -- made from 8 bits and
## shown as it was, an exposure, Radiance and PFM files read and written,
## kept in a .rpd, HDR Toning down to 16 and 8 bits by each method; and
## the 24- and 32-bit BMP, PNG-24.

import std/[os, math]
import retroui/[gfx, imaging, photo, photohdr, photofiles]

proc sample(w, h: int): Doc =
  result = newDoc(w, h, 0xFF808080'u32)
  for i in 0 ..< w * h:
    result.layer.px[i] = argb(255, i mod 256, (i div w) * 5 mod 256, 128)
  inc result.layer.ver

block toAndShown:
  let d = sample(64, 48)
  let before = d.layer.px
  d.toHdr()
  doAssert d.depth == 32 and d.hdrValid(d.layer)
  d.setExposure(0)
  doAssert d.layer.px == before, "shown as it was"
  d.setExposure(1)
  doAssert lumaOf(d.layer.px[100]) > lumaOf(before[100]), "a stop brighter"
  d.setExposure(0)
  doAssert d.hdrValid(d.layer), "the light kept while shown otherwise"
  # edited at 8 bits: its light made again from what is shown
  d.layer.px[0] = 0xFFFFFFFF'u32
  inc d.layer.ver
  let l = d.hdrPixels(d.layer)
  doAssert abs(l[0] - 1.0) < 1e-3
  doAssert l[4 .. 7] == d.layer.hdr[4 .. 7], "the pixels not edited keep their light"

block filesHdrPfm:
  var light = newSeq[float32](32 * 16 * 4)
  for i in 0 ..< 32 * 16:
    for c in 0 .. 2: light[4 * i + c] = float32(i) / 50 + float32(c) * 0.1   # up to 10: past white
    light[4 * i + 3] = 1
  let h = readHdr(writeHdr(32, 16, light))
  doAssert h.w == 32 and h.h == 16
  for i in 0 ..< 32 * 16:
    let m = max(light[4 * i], max(light[4 * i + 1], light[4 * i + 2]))
    for c in 0 .. 2: doAssert abs(h.light[4 * i + c] - light[4 * i + c]) <= m * 0.01 + 1e-3, $i
  let p = readPfm(writePfm(32, 16, light))
  for i in 0 ..< light.len:
    if i mod 4 < 3: doAssert p.light[i] == light[i]
  var refused = false
  try: discard readHdr("#?NOT")
  except ValueError: refused = true
  doAssert refused
  # opened as a 32-bit image; saved again; the light as it was
  let dir = getTempDir() / "retro-hdr-test"
  createDir(dir)
  writeFile(dir / "sky.hdr", writeHdr(32, 16, light))
  let d = openPicture(dir / "sky.hdr")
  doAssert d.depth == 32 and d.w == 32 and d.hdrValid(d.layer)
  d.exportPicture(dir / "again.pfm", defaultExport(efPfm))
  let back = readPfm(readFile(dir / "again.pfm"))
  for i in 0 ..< light.len:
    if i mod 4 < 3: doAssert abs(back.light[i] - d.layer.hdr[i]) < 1e-6
  # kept in a .rpd
  d.setExposure(-1.5, 1.2)
  d.saveRpd(dir / "sky.rpd")
  let e = loadRpd(dir / "sky.rpd")
  doAssert e.depth == 32 and e.hdrValid(e.layer) and e.layer.hdr == d.layer.hdr
  doAssert abs(e.exposure + 1.5) < 1e-9 and abs(e.viewGamma - 1.2) < 1e-9
  removeDir(dir)

block toning:
  for m in ToneMethod:
    let e = newDoc(64, 48, 0xFF808080'u32)
    e.layer.hdr = newSeq[float32](64 * 48 * 4)
    for i in 0 ..< 64 * 48:
      for c in 0 .. 2: e.layer.hdr[4 * i + c] = float32(i) / 300
      e.layer.hdr[4 * i + 3] = 1
    e.depth = 32
    e.layer.hdrVer = e.layer.ver
    e.toneMap(16, m)
    doAssert e.depth == 16 and e.hiValid(e.layer), $m
    doAssert e.layer.hdr.len == 0
    # brighter light, brighter pixels (each method keeps the order, broadly)
    doAssert lumaOf(e.layer.px[^1]) >= lumaOf(e.layer.px[10]), $m
  let f = newDoc(8, 8, 0xFF808080'u32)
  f.toHdr()
  f.toneMap(8, tmExposure)
  doAssert f.depth == 8 and not f.hiValid(f.layer)

block bmpAndPng:
  var px = newSeq[uint32](4 * 3)
  for i in 0 ..< px.len: px[i] = argb(i * 20, 200, 100, 50)
  let b32 = encodeBmp32(px, 4, 3)
  let back = decodeBmp(b32)
  doAssert back != nil and back.w == 4 and back.h == 3
  doAssert aOf(back.px[5]) == aOf(px[5]) and rOf(back.px[5]) == 200, $back.px[5]
  doAssert $efPng == "PNG-24"

echo "test_photohdr: ok"
