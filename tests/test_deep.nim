## 16 bits a channel (Image > Mode > 16 Bits/Channel): 16-bit PNG and PSD
## read and written without losing a bit; an edited layer saved as its 8
## bits made 16.

import std/[unittest, os]
import retro/[photo, psd, photofiles, imaging, gfx]

proc ramp16(w, h: int): seq[uint16] =
  ## Values no 8-bit picture has (odd low bytes), and some transparency.
  result = newSeq[uint16](w * h * 4)
  for y in 0 ..< h:
    for x in 0 ..< w:
      let o = (y * w + x) * 4
      result[o] = uint16(x * 997 + 13)
      result[o + 1] = uint16(y * 2003 + 7)
      result[o + 2] = uint16((x * y * 31 + 5) and 0xFFFF)
      result[o + 3] = if x == 0: 30000'u16 else: 65535'u16

suite "16 bits a channel":
  let dir = getTempDir() / "retro-deep"
  createDir(dir)

  test "PNG: 16 bits written and read back as they were":
    let w = 33
    let h = 21
    let src = ramp16(w, h)
    let png = encodePng16(w, h, src)
    var hi: seq[uint16]
    let b = decodePng(png, addr hi)
    check b.w == w and b.h == h
    check hi == src
    # (the 8 bits are the high bytes)
    check ((b.px[5] shr 16) and 255) == uint32(src[5 * 4] shr 8)
    # an 8-bit PNG gives no 16 bits
    var none: seq[uint16]
    discard decodePng(encodePng(b), addr none)
    check none.len == 0

  test "a 16-bit PNG opened, saved, opened: the same bits":
    let w = 40
    let h = 24
    var src = ramp16(w, h)
    for i in 0 ..< w * h: src[i * 4 + 3] = 65535
    writeFile(dir / "a.png", encodePng16(w, h, src, alpha = false))
    let d = openPicture(dir / "a.png")
    check d.depth == 16 and d.hiValid(d.layers[0])
    var o = defaultExport(efPng)
    d.exportPicture(dir / "b.png", o)
    var hi: seq[uint16]
    discard decodePng(readFile(dir / "b.png"), addr hi)
    check hi.len == w * h * 4
    var same = true
    for i in 0 ..< w * h * 4:
      if hi[i] != src[i]: same = false
    check same

  test "PSD: layers and the merged picture at 16 bits":
    let w = 30
    let h = 20
    let d = newDoc(w, h, 0xFFFFFFFF'u32)
    d.setDepth(16)
    let src = ramp16(w, h)
    var px = newSeq[uint32](w * h)
    for i in 0 ..< w * h:
      px[i] = (uint32(src[4 * i + 3] shr 8) shl 24) or (uint32(src[4 * i] shr 8) shl 16) or
              (uint32(src[4 * i + 1] shr 8) shl 8) or uint32(src[4 * i + 2] shr 8)
    d.layers[0].px = px
    d.layers[0].background = false
    d.setHi(d.layers[0], src)
    d.markAll()
    let L2 = d.addLayer("Edited")
    for i in 0 ..< w * h: L2.px[i] = if i mod 7 == 0: 0xFF102030'u32 else: 0'u32
    inc L2.ver
    d.markAll()
    let data = writePsd(psdOf(d))
    let p = readPsd(data)
    check p.depth == 16 and p.layers.len == 2
    let back = docOfPsd(p, "back")
    check back.depth == 16
    check back.hiValid(back.layers[0])
    check back.layers[0].hi == src
    # the edited layer: its 8 bits made 16 (exactly)
    let h2 = back.hiPixels(back.layers[1])
    check h2[0] == 0x10'u16 * 257 and h2[1] == 0x20'u16 * 257 and h2[2] == 0x30'u16 * 257 and h2[3] == 65535'u16
    # back to 8 bits: the 16 let go
    back.setDepth(8)
    check back.layers[0].hi.len == 0 and back.depth == 8

  test "a pixel edited at 8 bits is its 8 bits; the others keep their 16":
    let d = newDoc(8, 8, 0xFF808080'u32)
    d.setDepth(16)
    var hi = newSeq[uint16](8 * 8 * 4)
    for v in hi.mitems: v = 33333
    d.setHi(d.layers[0], hi)
    check d.hiValid(d.layers[0])
    check d.layers[0].px[5] == 0x82828282'u32          # (its 8 bits made from the 16)
    check d.flattened16()[0] == 33333'u16
    d.layers[0].px[0] = 0xFF000000'u32
    inc d.layers[0].ver
    let f = d.flattened16()
    check f[0] == 0 and f[1] == 0 and f[3] == 65535'u16
    check f[4 * 1] == 33333'u16
    # only the channel changed: red edited, green and blue keep theirs
    d.layers[0].px[2] = 0xFF008282'u32
    let g = d.flattened16()
    check g[4 * 2] == 0 and g[4 * 2 + 1] == 33333'u16
