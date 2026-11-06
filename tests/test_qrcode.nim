## QR codes (retroui/qrcode): the modules equal those of reference encoders
## (the fixtures below were made by segno and python-qrcode, which agree on
## them), the capacities the standard gives, and the picture and the
## outlines show the same modules.

import std/strutils
import retroui/[gfx, qrcode]

proc rowsOf(q: QrCode): seq[string] =
  ## Each row as hex, its last module the lowest bit (as the fixtures).
  for y in 0 ..< q.size:
    var bits: seq[bool]
    for i in 0 ..< (4 - q.size mod 4) mod 4: bits.add false
    for x in 0 ..< q.size: bits.add q[x, y]
    var s = ""
    for i in countup(0, bits.high, 4):
      s.add "0123456789abcdef"[ord(bits[i]) * 8 + ord(bits[i + 1]) * 4 + ord(bits[i + 2]) * 2 +
                               ord(bits[i + 3])]
    result.add s

const fixtures: seq[tuple[text: string; ec: QrEcc; minVersion, mask, version, maskWas: int;
                          rows: seq[string]]] = @[
  # "HELLO WORLD" M, from version 1, mask auto
  ("HELLO WORLD", qrM, 1, -1, 1, 0, @[
    "1fc57f", "105c41", "17455d",
    "17455d", "17575d", "104e41",
    "1fd57f", "000000", "154912",
    "0f1211", "03fa58", "1eb3ae",
    "09ea75", "001445", "1fc12c",
    "104c68", "17597f", "1746a2",
    "175ee9", "10438b", "1fdae1"]),
  # "WIFI:T:WPA;S:Hotel;P:secret;;" Q, from version 1, mask auto
  ("WIFI:T:WPA;S:Hotel;P:secret;;", qrQ, 1, -1, 3, 6, @[
    "1fcfb17f", "105f7f41", "1748435d",
    "1754d05d", "1751935d", "10473541",
    "1fd5557f", "001d9300", "0bdcffda",
    "1e240239", "0ffae404", "082d7972",
    "035bc7d1", "1793aaf9", "07c73e41",
    "178851cf", "10f76d04", "150e0717",
    "1b6ad7a1", "1c123546", "1b5c43f0",
    "00146f1c", "1fc83150", "105ea719",
    "175bcbfd", "175eccae", "1740645b",
    "10599675", "1fc6e368"]),
  # "مرحبا بكم في صحار" H, from version 1, mask 5
  ("مرحبا بكم في صحار", qrH, 1, 5, 4, 5, @[
    "1fdd63a7f", "1042ada41", "1751eb45d",
    "174a1335d", "175c6645d", "1041bd341",
    "1fd55557f", "001b20a00", "00cd47255",
    "019d82084", "0668b2b65", "1fa986518",
    "037ab6f96", "1392f7d7a", "11dff2a5f",
    "0daf81dfa", "0d403b34f", "1a1a1cb31",
    "097eead96", "10a32ad00", "0f76e2b45",
    "17aa4f5ac", "12e9b2c28", "103e5fd86",
    "184f4dbf9", "00142cd12", "1fca3575f",
    "105d75d11", "174fc7df5", "1748860e2",
    "174d9be4f", "1042c9360", "1fce3fa02"]),
  # "01234567890123456789" L, from version 1, mask auto
  ("01234567890123456789", qrL, 1, -1, 1, 0, @[
    "1fcb7f", "104e41", "175b5d",
    "174a5d", "17455d", "104141",
    "1fd57f", "001b00", "1dfec4",
    "0b2442", "02f52e", "079862",
    "0e7141", "0012f2", "1fde41",
    "1057bc", "175263", "174c62",
    "175d31", "105c44", "1fd951"]),
  # "https://example.com/booking?room=214" M, from version 7, mask 3
  ("https://example.com/booking?room=214", qrM, 7, 3, 7, 3, @[
    "1fd8674fc17f", "105c4847e241", "174419bbca5d",
    "1752b78a035d", "174b53f6775d", "104ecf112041",
    "1fd55555557f", "00170f199900", "16e6fdf59e4b",
    "16ae77b8511b", "1ed40ba32c83", "0cb2c665c412",
    "1f639e150119", "12951de97155", "19fd723a2da5",
    "09b4af40d6c9", "01fc481c370a", "148ae92b2a70",
    "1cd16a1a0a2c", "11227d88917b", "01f4ddfe9ffa",
    "091fc51f591d", "195db9572b5b", "1316eb18c119",
    "07f8a7f40bfb", "0b21f36f7ac4", "0d7abb5e20b8",
    "09236b3044a4", "0f789d1c2437", "1c1f0bfb3bf0",
    "1769e25afa2c", "1c039e58620b", "13cf659e4d7a",
    "0b8e00afe968", "0171e807eaae", "0f1602cbca9f",
    "134fb1fa0df7", "0017a5167d10", "1fd0f7512750",
    "1059af1f4b1f", "174e8ffa29f6", "1751e7623c93",
    "175ff316fe90", "104e40e87359", "1fdb603e6f2c"])
  ]

block reference:
  for f in fixtures:
    let q = qrEncode(f.text, f.ec, f.minVersion, f.mask)
    doAssert q.version == f.version and q.mask == f.maskWas,
      f.text & ": v" & $q.version & " mask " & $q.mask
    doAssert q.size == 17 + 4 * f.version
    doAssert rowsOf(q) == f.rows, f.text

block modes:
  doAssert qrEncode("0123456789").mode == qmNumeric
  doAssert qrEncode("HTTPS://A.B/C D$%*+-").mode == qmAlphanumeric
  doAssert qrEncode("hello").mode == qmByte
  doAssert qrEncode("").mode == qmByte and qrEncode("").version == 1
  doAssert qrEncode("مرحبا").mode == qmByte

block capacity:
  # the most version 40 holds (ISO 18004 table 7), and one more
  for (text, ec, fits) in [("a".repeat(2953), qrL, true), ("a".repeat(2954), qrL, false),
                           ("7".repeat(7089), qrL, true), ("7".repeat(7090), qrL, false),
                           ("A".repeat(4296), qrL, true), ("A".repeat(4297), qrL, false),
                           ("a".repeat(1273), qrH, true), ("a".repeat(1274), qrH, false),
                           ("a".repeat(2331), qrM, true), ("a".repeat(1663), qrQ, true)]:
    var ok = true
    try:
      doAssert qrEncode(text, ec).version == 40
    except ValueError: ok = false
    doAssert ok == fits, $text.len & " " & $ec
  # version 1: 17 bytes at L, 7 at H
  doAssert qrEncode("a".repeat(17), qrL).version == 1 and qrEncode("a".repeat(18), qrL).version == 2
  doAssert qrEncode("a".repeat(7), qrH).version == 1 and qrEncode("a".repeat(8), qrH).version == 2
  doAssert qrFits("a".repeat(17), qrL, 1) and not qrFits("a".repeat(18), qrL, 1)
  doAssert qrEncode("x", qrM, minVersion = 12).version == 12

block masks:
  for m in 0 .. 7:
    doAssert qrEncode("mask test", qrQ, mask = m).mask == m
  try:
    discard qrEncode("x", mask = 8)
    doAssert false
  except ValueError: discard
  let q = qrEncode("HELLO WORLD")
  doAssert not q[-1, 0] and not q[q.size, 0] and q[0, 0] and q[q.size - 1, 0]

block picture:
  let q = qrEncode("WIFI:T:WPA;S:Hotel;P:secret;;", qrQ)
  let b = qrBitmap(q, scale = 3, border = 4, dark = color(10, 20, 30), light = color(250, 240, 230))
  doAssert b.w == (q.size + 8) * 3 and b.h == b.w and b.opaque
  for y in -4 ..< q.size + 4:
    for x in -4 ..< q.size + 4:
      let p = b.px[((y + 4) * 3 + 1) * b.w + (x + 4) * 3 + 1]
      doAssert p == (if q[x, y]: 0xFF0A141E'u32 else: 0xFFFAF0E6'u32)

proc winding(polys: seq[seq[(float, float)]]; px, py: float): int =
  ## The non-zero winding number at the point (a ray to the right; y down).
  for poly in polys:
    for i in 0 ..< poly.len:
      let (x0, y0) = poly[i]
      let (x1, y1) = poly[(i + 1) mod poly.len]
      if (y0 <= py) != (y1 <= py) and x0 + (py - y0) / (y1 - y0) * (x1 - x0) > px:
        result += (if y1 > y0: 1 else: -1)

proc crossings(polys: seq[seq[(float, float)]]; px, py: float): int =
  for poly in polys:
    for i in 0 ..< poly.len:
      let (x0, y0) = poly[i]
      let (x1, y1) = poly[(i + 1) mod poly.len]
      if (y0 <= py) != (y1 <= py) and x0 + (py - y0) / (y1 - y0) * (x1 - x0) > px: inc result

block outlines:
  for text in ["HELLO WORLD", "WIFI:T:WPA;S:Hotel;P:secret;;", "مرحبا بكم في صحار",
               "https://example.com/".repeat(20)]:
    let q = qrEncode(text, qrM)
    let polys = qrPath(q)
    var dark = 0
    for y in 0 ..< q.size:
      for x in 0 ..< q.size:
        if q[x, y]: inc dark
        let w = winding(polys, x.float + 0.5, y.float + 0.5)
        doAssert (w != 0) == q[x, y], "non-zero rule at " & $x & "," & $y
        doAssert (crossings(polys, x.float + 0.5, y.float + 0.5) mod 2 == 1) == q[x, y], "even-odd"
        doAssert w in -1 .. 1
    var area = 0.0
    var corners = 0
    for poly in polys:
      doAssert poly.len >= 4 and poly.len mod 2 == 0
      for i in 0 ..< poly.len:
        let (x0, y0) = poly[i]
        let (x1, y1) = poly[(i + 1) mod poly.len]
        doAssert (x0 == x1) != (y0 == y1), "sides along the grid, a point only where they turn"
        area += x0 * y1 - x1 * y0
      corners += poly.len
    doAssert area / 2 == dark.float, "clockwise outsides less anticlockwise holes: the dark area"
    doAssert corners < dark * 2, "regions joined, not a square a module"
  # moved and scaled
  let q = qrEncode("1")
  let p1 = qrPath(q)
  let p2 = qrPath(q, scale = 2.5, x = 10, y = 20)
  doAssert p1.len == p2.len and p2[0][0] == (10 + p1[0][0][0] * 2.5, 20 + p1[0][0][1] * 2.5)

echo "qrcode tests passed"
