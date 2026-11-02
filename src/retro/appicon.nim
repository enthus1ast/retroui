## The default app icon (a Windows 3.1 window in pixel art) as PNG files,
## for the APK and iOS build tools, and the PNG writer.

import codec
export codec

proc be32(b: var Bytes; v: SomeInteger) =
  let x = uint32(v)
  for i in countdown(3, 0): b.add byte((x shr (8 * i)) and 0xFF)

proc chunk(b: var Bytes; kind: string; data: Bytes) =
  var t = kind.toBytes
  t.add data
  b.be32(data.len)
  b.add t
  b.be32(crc32(t))

proc png*(w, h: int; argb: openArray[uint32]): Bytes =
  ## A PNG of `w` x `h` pixels given as 0xAARRGGBB.
  var raw: Bytes
  for y in 0 ..< h:
    raw.add 0                                   # filter: none
    for x in 0 ..< w:
      let p = argb[y * w + x]
      raw.add byte((p shr 16) and 0xFF); raw.add byte((p shr 8) and 0xFF)
      raw.add byte(p and 0xFF); raw.add byte(p shr 24)
  var z: Bytes = @[0x78'u8, 0x9C]               # zlib header
  z.add deflate(raw)
  var s1 = 1'u32
  var s2 = 0'u32
  for x in raw:
    s1 = (s1 + x) mod 65521
    s2 = (s2 + s1) mod 65521
  z.be32((s2 shl 16) or s1)
  result = @[0x89'u8, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
  var ihdr: Bytes
  ihdr.be32(w)
  ihdr.be32(h)
  ihdr.add [8'u8, 6, 0, 0, 0]                   # 8 bits, RGBA
  result.chunk("IHDR", ihdr)
  result.chunk("IDAT", z)
  result.chunk("IEND", @[])

proc iconPixels*(): array[48 * 48, uint32] =
  ## The icon at its own size, 48 x 48: a 3.1 window on the desktop teal.
  ## (Drawn by tools/genicons.py.)
  const art = [
    "................................................",
    ".tttttttttttttttttttttttttttttttttttttttttttttt.",
    ".tttttttttttttttttttttttttttttttttttttttttttttt.",
    ".tttttttttttttttttttttttttttttttttttttttttttttt.",
    ".tttttttttttttttttttttttttttttttttttttttttttttt.",
    ".tttttttttttttttttttttttttttttttttttttttttttttt.",
    ".ttttkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkktttt.",
    ".ttttknnnnnnnnnnnnnnnnnnnnnnnkssssskssssssktttt.",
    ".ttttknkkkkknnnnnnnnnnnnnnnnnkssssskssssssktttt.",
    ".ttttknkwwwknnnnwwwwwwwwwwwwnksskkkkssksssktttt.",
    ".ttttknkwssknnnnwwwwwwwwwwwwnkssskskskkkssktttt.",
    ".ttttknkkkkknnnnnnnnnnnnnnnnnkssssskssssssktttt.",
    ".ttttknnnnnnnnnnnnnnnnnnnnnnnkssssskssssssktttt.",
    ".ttttkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwkkkkwwkkkkkwwkkkkwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwkkkkkkkkkkkwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwkwwwwwwwwwkwwwnnnnnnnnnnnnnnnnwwwktttt.",
    ".ttttkwwwkwkwwwwwkwkwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwkwwkwwwkwwkwwwgggggggggggwwwwwwwwktttt.",
    ".ttttkwwwkwwwkwkwwwkwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwkwwwwkwwwwkwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwkwwwkwkwwwkwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwkwwkwwwkwwkwwwkkkkkkkkkkkkkkkkwwwktttt.",
    ".ttttkwwwkwkwwwwwkwkwwwkwwwwwwwwwwwwwgkwwwktttt.",
    ".ttttkwwwkwwwwwwwwwkwwwkwssssssssssssgkwwwktttt.",
    ".ttttkwwwkkkkkkkkkkkwwwkwsskkkkkkkkssgkwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwkwssssssssssssgkwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwkggggggggggggggkwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwkkkkkkkkkkkkkkkkwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwktttt.",
    ".ttttkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkktttt.",
    ".tttttttttttttttttttttttttttttttttttttttttttttt.",
    ".tttttttttttttttttttttttttttttttttttttttttttttt.",
    ".tttttttttttttttttttttttttttttttttttttttttttttt.",
    ".tttttttttttttttttttttttttttttttttttttttttttttt.",
    ".tttttttttttttttttttttttttttttttttttttttttttttt.",
    "................................................",
  ]
  for y in 0 ..< 48:
    for x in 0 ..< 48:
      result[y * 48 + x] = case art[y][x]
        of 'k': 0xFF000000'u32
        of 'w': 0xFFFFFFFF'u32
        of 's': 0xFFC0C0C0'u32
        of 'g': 0xFF808080'u32
        of 'n': 0xFF000080'u32
        of 't': 0xFF008080'u32
        of 'y': 0xFFFFFF00'u32
        of 'r': 0xFFFF0000'u32
        of 'G': 0xFF008000'u32
        of 'l': 0xFF00FF00'u32
        of 'b': 0xFF0000FF'u32
        of 'c': 0xFF00FFFF'u32
        of 'm': 0xFF800000'u32
        of 'o': 0xFF808000'u32
        of 'p': 0xFFFF00FF'u32
        of 'P': 0xFF800080'u32
        else: 0'u32

proc iconPng*(size: int; opaque = false): Bytes =
  ## The icon as a `size` x `size` PNG (nearest-neighbor, so it stays crisp).
  ## `opaque` fills the corners (iOS icons may not be transparent).
  let art = iconPixels()
  var px = newSeq[uint32](size * size)
  for y in 0 ..< size:
    for x in 0 ..< size:
      var c = art[(y * 48 div size) * 48 + x * 48 div size]
      if opaque and (c shr 24) == 0: c = 0xFF008080'u32
      px[y * size + x] = c
  png(size, size, px)
