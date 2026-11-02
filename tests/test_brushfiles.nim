## Tests of retro/abr: Photoshop (.abr) and GIMP (.gbr) brushes read.

import std/unittest
import retro/[abr, photopaint]

proc w16(o: var string; v: int) = (o.add char((v shr 8) and 255); o.add char(v and 255))
proc w32(o: var string; v: int) =
  o.add char((v shr 24) and 255); o.add char((v shr 16) and 255); o.add char((v shr 8) and 255); o.add char(v and 255)

proc disc(n: int): seq[uint8] =
  result = newSeq[uint8](n * n)
  for y in 0 ..< n:
    for x in 0 ..< n:
      if (x - n div 2) * (x - n div 2) + (y - n div 2) * (y - n div 2) <= (n div 2) * (n div 2): result[y * n + x] = 255

suite "brush files":
  test "version 2, written and read back":
    let t = BrushTip(name: "Dot", custom: disc(9), cw: 9, ch: 9, spacing: 30)
    let got = readAbr(writeAbr([t, t]))
    check got.len == 2
    check got[0].name == "Dot" and got[0].cw == 9 and got[0].ch == 9 and got[0].custom == t.custom
    check got[0].spacing == 30

  test "version 6, packed rows":
    var s = ""
    s.w16(6); s.w16(2)
    var brush = newString(301)                 # (its key and what we skip)
    brush.w32(0); brush.w32(0); brush.w32(2); brush.w32(4)    # top, left, bottom, right
    brush.w16(8)
    brush.add '\1'                             # PackBits
    # two rows of four: "AAAA" as a run, "ABCD" as literals
    brush.w16(2); brush.w16(5)
    brush.add char(0xFD); brush.add char(200)
    brush.add char(3); brush.add "\x01\x02\x03\x04"
    var body = ""
    body.w32(brush.len)
    body.add brush
    while body.len mod 4 != 0: body.add '\0'
    s.add "8BIM" & "samp"
    s.w32(body.len)
    s.add body
    let got = readAbr(s)
    check got.len == 1
    check got[0].cw == 4 and got[0].ch == 2
    check got[0].custom == @[200'u8, 200, 200, 200, 1, 2, 3, 4]

  test "GIMP brushes; big ones made smaller":
    var g = ""
    let name = "Star"
    g.w32(28 + name.len + 1); g.w32(2); g.w32(3); g.w32(2); g.w32(1)
    g.add "GIMP"
    g.w32(40)
    g.add name & "\0"
    g.add "\x00\x80\xff\x10\x20\x30"
    let t = readBrushes("star.gbr", g)
    check t.len == 1 and t[0].name == "Star" and t[0].spacing == 40
    check t[0].custom == @[0'u8, 128, 255, 16, 32, 48]
    let big = BrushTip(name: "Big", custom: newSeq[uint8](2000 * 1000), cw: 2000, ch: 1000, spacing: 25)
    let b = readAbr(writeAbr([big]))
    # (its picture kept at most 1024 across, painted at its own 2000)
    check b[0].cw == 1024 and b[0].ch == 512 and b[0].diameter == 2000
    let m = tipMask(b[0])
    check m.fullW == 2000 and m.fullH == 1000 and m.w <= MaxMaskSide

  test "not a brush file":
    expect ValueError: discard readAbr("hello, world")
    expect ValueError: discard readAbr("\x00\x09\x00\x01")
