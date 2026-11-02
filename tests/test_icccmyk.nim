## Tests of printing color management: CMYK and table profiles read
## (retro/iccprofile), converted with every intent and black point
## compensation (retro/icclut) and checked against littlecms, the press
## profile hook of retro/photoinks, and the built-in ink model written as a
## profile.
##
## The data (tests/data/icc):
## - GenericCMYK.icm: "Fogra27L CMYK Coated Press", copyright "Public
##   Domain"; from Scribus (github.com/scribusproject/scribus,
##   resources/profiles/GenericCMYK.icm). Version 2.2 printer profile, lut16
##   tables (a B2A for each intent), bkpt.
## - lcms_test3.icc, lcms_test4.icc: littlecms' test profiles (MIT, from
##   github.com/mm2/Little-CMS, testbed/test3.icc and test4.icc): lut8
##   tables; version 4 lutAtoB/lutBtoA with curves, matrix and grid.
## - retro_srgb.icc: our `srgbProfile().data`; retro_ink_model.icc: our
##   `inkModelProfile(defaultInks)` (both made by this code, no copyright).
## - *.lcmsref: what littlecms 2.19 (Pillow 12.3 ImageCms) makes of the
##   colors in them, 8 bits a channel, made with the flags NOOPTIMIZE (its
##   full steps for each color) and BLACKPOINTCOMPENSATION as marked: for
##   each profile P, sRGB (retro_srgb.icc) -> P ("F") and P -> sRGB ("B")
##   for each intent. Layout: "RLCM", n, P's channels, blocks (u32 big
##   endian each); n RGB colors; n colors of P; then each block: direction
##   'F'/'B', intent, bpc, 0, and the n colors made.

import std/[unittest, os, monotimes, times, strformat, strutils]
import retro/[iccprofile, icclut, photoinks]

const dir = currentSourcePath().parentDir / "data" / "icc"

proc be32(s: string; at: int): int =
  (ord(s[at]) shl 24) or (ord(s[at + 1]) shl 16) or (ord(s[at + 2]) shl 8) or ord(s[at + 3])

type
  RefBlock = object
    forward: bool
    intent: RenderingIntent
    bpc: bool
    output: string
  Ref = object
    n, ch: int
    rgb, dev: string
    blocks: seq[RefBlock]

proc readRef(name: string): Ref =
  let s = readFile(dir / name)
  doAssert s[0 ..< 4] == "RLCM"
  result.n = be32(s, 4)
  result.ch = be32(s, 8)
  let nb = be32(s, 12)
  var p = 16
  result.rgb = s[p ..< p + result.n * 3]
  p += result.n * 3
  result.dev = s[p ..< p + result.n * result.ch]
  p += result.n * result.ch
  for b in 0 ..< nb:
    let fwd = s[p] == 'F'
    let size = result.n * (if fwd: result.ch else: 3)
    result.blocks.add RefBlock(forward: fwd, intent: RenderingIntent(ord(s[p + 1])), bpc: ord(s[p + 2]) == 1,
                               output: s[p + 4 ..< p + 4 + size])
    p += 4 + size

proc px3(r, g, b: int): uint32 = 0xFF000000'u32 or (uint32(r) shl 16) or (uint32(g) shl 8) or uint32(b)
proc ch(p: uint32; s: int): int = int((p shr s) and 255)

let srgbRef = parseIcc(readFile(dir / "retro_srgb.icc"))
let generic = parseIcc(readFile(dir / "GenericCMYK.icm"))

suite "profiles with tables, read":
  test "a press profile (lut16, version 2)":
    check generic.colorSpace == "CMYK" and generic.pcs == "Lab " and generic.deviceClass == "prtr"
    check generic.description == "Fogra27L CMYK Coated Press" and generic.name == generic.description
    check generic.version == 0x02200000 and not generic.usable
    for i in 0 .. 2:
      check generic.a2b[i].kind == "mft2" and generic.a2b[i].inputs == 4 and generic.a2b[i].outputs == 3
      check generic.b2a[i].kind == "mft2" and generic.b2a[i].inputs == 3 and generic.b2a[i].outputs == 4
      check generic.a2b[i].stages.len == 3 and generic.a2b[i].stages[1].grid == @[9, 9, 9, 9]
      check generic.b2a[i].stages[1].grid == @[17, 17, 17] and generic.b2a[i].stages[1].table.len == 17 * 17 * 17 * 4
    check generic.a2b[0].stages[0].curves[0].table.len == 1024
    check generic.mediaWhite[1] > 0.8 and generic.mediaWhite[1] <= 1.0
    check generic.mediaBlack[1] > 0.0 and generic.mediaBlack[1] < 0.1
    check canConvert(generic) and canConvert(generic, asInput = false)

  test "lut8, lutAtoB and lutBtoA":
    let t3 = parseIcc(readFile(dir / "lcms_test3.icc"))
    check t3.colorSpace == "RGB " and t3.pcs == "Lab " and t3.deviceClass == "spac"
    check t3.a2b[0].kind == "mft1" and t3.b2a[0].kind == "mft1" and t3.a2b[1].kind == ""
    check t3.a2b[0].stages[1].grid == @[16, 16, 16]
    let t4 = parseIcc(readFile(dir / "lcms_test4.icc"))
    check t4.version >= 0x04000000 and t4.colorSpace == "RGB " and t4.pcs == "Lab "
    check t4.a2b[0].kind == "mAB " and t4.a2b[1].kind == "mAB " and t4.b2a[0].kind == "mBA "
    var kinds: seq[IccStageKind]
    for st in t4.a2b[0].stages: kinds.add st.kind
    check kinds == @[iccCurves, iccGrid, iccCurves, iccMatrix, iccCurves]   # A, CLUT, M, matrix, B
    check t4.a2b[0].stages[3].matrix.len == 12
    check t4.a2b[2].kind == "" and t4.b2a[2].kind == ""

  test "the built-in and matrix profiles: as before, and more said":
    let s = srgbProfile()
    check s.usable and s.pcs == "XYZ " and s.deviceClass == "mntr" and s.description == "sRGB IEC61966-2.1"
    check s.version == 0x02100000 and abs(s.mediaWhite[0] - 0.9642) < 1e-9
    let q = parseIcc(s.data)
    check q.usable and q.pcs == "XYZ " and q.deviceClass == "mntr" and q.a2b[0].kind == ""
    check q == srgbRef
    # damaged tables: not read (no crash)
    var bad = readFile(dir / "GenericCMYK.icm")
    bad.setLen 60_000
    let b = parseIcc(bad)
    check b.colorSpace == "CMYK" and b.a2b[0].kind == "mft2" and b.b2a[0].kind == ""
    check not canConvert(b, asInput = false) and not newTransform(srgbRef, b).ok
    check parseLut("mft2\0\0\0\0", 0, 8).kind == ""

suite "conversions, against littlecms":
  test "each profile, intent and black point compensation":
    echo "  littlecms 2.19 (NOOPTIMIZE) and ours, 8-bit results: mean and largest difference"
    echo "  (to CMYK in % of ink, to RGB in levels of 255)"
    for (file, refName) in [("GenericCMYK.icm", "GenericCMYK.lcmsref"), ("lcms_test3.icc", "lcms_test3.lcmsref"),
                            ("lcms_test4.icc", "lcms_test4.lcmsref"), ("retro_ink_model.icc", "retro_ink_model.lcmsref")]:
      let p = parseIcc(readFile(dir / file))
      let r = readRef(refName)
      for b in r.blocks:
        let t = if b.forward: newTransform(srgbRef, p, b.intent, b.bpc) else: newTransform(p, srgbRef, b.intent, b.bpc)
        check t.ok
        let nin = if b.forward: 3 else: r.ch
        let nout = if b.forward: r.ch else: 3
        var src = newSeq[int](nin)
        var dst = newSeq[int](nout)
        var sum = 0.0
        var most = 0
        for i in 0 ..< r.n:
          for k in 0 ..< nin: src[k] = ord((if b.forward: r.rgb else: r.dev)[i * nin + k])
          t.transform8(src, dst)
          for k in 0 ..< nout:
            let d = abs(dst[k] - ord(b.output[i * nout + k]))
            sum += d.float
            most = max(most, d)
        let mean = sum / float(r.n * nout)
        let unit = if nout == 4: 100 / 255 else: 1.0
        let what = (if b.forward: "sRGB -> " & p.colorSpace.strip else: p.colorSpace.strip & " -> sRGB")
        echo &"  {file:<20} {what:<13} {$b.intent:<22} bpc {b.bpc:<5}  mean {mean * unit:.3f} max {most.float * unit:.2f}"
        check most <= 1 and mean < 0.05

  test "black points":
    # the press profile's: below L* 20, gray
    let (ok, bp) = detectDestinationBlackPoint(generic, riRelative)
    check ok and bp[1] > 0.005 and bp[1] < 0.03
    let lab = xyzToLabD50(bp)
    check abs(lab[1]) < 0.01 and abs(lab[2]) < 0.01
    check detectBlackPoint(srgbRef, riRelative) == (true, [0.0, 0.0, 0.0])
    check not detectBlackPoint(generic, riAbsolute)[0]
    # with compensation, sRGB's black is the press's darkest: more ink
    let plain = newTransform(srgbRef, generic, riRelative).rgbToCmyk(px3(40, 40, 40))
    let comp = newTransform(srgbRef, generic, riRelative, bpc = true).rgbToCmyk(px3(40, 40, 40))
    check int(comp[3]) < int(plain[3])

  test "grids, as photoinks packs them":
    let t = newTransform(srgbProfile(), generic, riRelative, true)
    let g = rgbToCmykGrid(srgbProfile(), generic, riRelative, true, 33)
    check g.len == 33 * 33 * 33
    for (ri, gi, bi) in [(0, 0, 0), (32, 32, 32), (5, 17, 30), (32, 0, 9)]:
      let ink = t.rgbToCmyk(px3((ri * 255 + 16) div 32, (gi * 255 + 16) div 32, (bi * 255 + 16) div 32))
      let v = g[(ri * 33 + gi) * 33 + bi]
      check v == ((uint32(ink[0]) shl 24) or (uint32(ink[1]) shl 16) or (uint32(ink[2]) shl 8) or uint32(ink[3]))
    let back = newTransform(generic, srgbProfile(), riRelative)
    let g4 = cmykToRgbGrid(generic, srgbProfile(), riRelative, false, 17)
    check g4.len == 17 * 17 * 17 * 17
    check g4[((16 * 17 + 0) * 17 + 0) * 17 + 0] == back.cmykToRgb(255, 0, 0, 0)
    check g4[0] == back.cmykToRgb(0, 0, 0, 0) and ch(g4[0], 16) >= 254   # the paper: white
    # a gray profile, and profiles that cannot be used so
    let gray = newTransform(grayProfile(), srgbProfile(), riRelative)
    var o: array[3, int]
    gray.transform8([128], o)
    check gray.ok and o[0] == o[1] and o[1] == o[2] and o[0] > 100 and o[0] < 160
    check not newTransform(srgbProfile(), IccProfile()).ok
    check rgbToCmykGrid(srgbProfile(), srgbProfile()).len == 0

suite "the ink model as a profile":
  test "written, read, as littlecms reads it":
    let m = inkModelProfile(defaultInks)
    let p = parseIcc(m)
    check m.len > 100_000 and m.len < 400_000
    check p.colorSpace == "CMYK" and p.pcs == "Lab " and p.deviceClass == "prtr" and p.version == 0x02100000
    check p.description == "Retro Photo Ink Model" and abs(p.mediaWhite[2] - 0.8249) < 1e-4
    for i in 0 .. 2:
      check p.a2b[i].kind == "mft2" and p.b2a[i].kind == "mft2"
    check m[36 ..< 40] == "acsp" and be32(m, 0) == m.len
    check parseIcc(inkModelProfile(defaultInks, "Press")).description == "Press"
    # the one the references were made from: the same conversions
    let stored = parseIcc(readFile(dir / "retro_ink_model.icc"))
    let a = newTransform(srgbProfile(), p, riRelative)
    let b = newTransform(srgbProfile(), stored, riRelative)
    for c in [0xFF3366CC'u32, 0xFF808080'u32, 0xFFE0B090'u32, 0xFF102030'u32]:
      for k in 0 .. 3: check abs(int(a.rgbToCmyk(c)[k]) - int(b.rgbToCmyk(c)[k])) <= 1

  test "littlecms with it agrees with the model":
    let r = readRef("retro_ink_model.lcmsref")
    var inkSum, inkMost, rgbSum, rgbMost = 0.0
    for b in r.blocks:
      if b.intent != riRelative or b.bpc: continue
      for i in 0 ..< r.n:
        if b.forward:
          let ink = inkOf(px3(ord(r.rgb[i * 3]), ord(r.rgb[i * 3 + 1]), ord(r.rgb[i * 3 + 2])))
          for k in 0 .. 3:
            let d = abs(int(ink[k]) - ord(b.output[i * 4 + k])).float / 2.55
            inkSum += d
            inkMost = max(inkMost, d)
        else:
          let q = printed(ord(r.dev[i * 4]), ord(r.dev[i * 4 + 1]), ord(r.dev[i * 4 + 2]), ord(r.dev[i * 4 + 3]))
          for k in 0 .. 2:
            let d = abs(ch(q, 16 - 8 * k) - ord(b.output[i * 3 + k])).float
            rgbSum += d
            rgbMost = max(rgbMost, d)
    let inkMean = inkSum / float(r.n * 4)
    let rgbMean = rgbSum / float(r.n * 3)
    echo &"  sRGB -> CMYK, littlecms with the profile vs inkOf: mean {inkMean:.2f}% max {inkMost:.1f}%"
    echo &"  CMYK -> sRGB, littlecms with the profile vs printed: mean {rgbMean:.2f} max {rgbMost:.0f} levels"
    check inkMean < 1.0 and inkMost < 20
    check rgbMean < 0.6 and rgbMost <= 8

suite "photoinks with a press profile":
  test "set, used, the tables made again, and back":
    let colors = [0xFF3366CC'u32, 0xFF808080'u32, 0xFFE0B090'u32, 0xFF000000'u32, 0xFFFFFFFF'u32, 0xFF0000FF'u32]
    var before: seq[(Ink, uint32, int)]
    for c in colors: before.add (inkOf(c), proofOf(c), gamutDistance(c))
    let beforePrinted = printed(100, 50, 20, 10)
    check inkProfile() == "" and inkProfileName() == ""
    # not a CMYK profile: refused, nothing changed
    check not setInkProfile(srgbProfile().data) and inkProfile() == ""
    let icc = readFile(dir / "GenericCMYK.icm")
    check setInkProfile(icc, riRelative, bpc = true)
    check inkProfile() == icc and inkProfileName() == "Fogra27L CMYK Coated Press"
    let t0 = getMonoTime()
    discard inkOf(0xFF808080'u32)                   # (the tables, from the profile)
    let ms = (getMonoTime() - t0).inMicroseconds.float / 1000
    echo &"  the ink and proof tables (33^3) from the press profile: {ms:.1f} ms"
    when defined(release): check ms < 200
    let toInk = newTransform(srgbProfile(), generic, riRelative, bpc = true)
    let shown = newTransform(generic, srgbProfile(), riRelative)
    for (ri, gi, bi) in [(0, 0, 0), (32, 32, 32), (8, 20, 31), (31, 4, 12)]:
      # on the grid: the conversion's (but for reading between: 1)
      let c = px3((ri * 255 + 16) div 32, (gi * 255 + 16) div 32, (bi * 255 + 16) div 32)
      let k = inkOf(c)
      for j in 0 .. 3: check abs(int(k[j]) - int(toInk.rgbToCmyk(c)[j])) <= 1
      let q = shown.cmykToRgb(k[0].int, k[1].int, k[2].int, k[3].int)
      for sh in [0, 8, 16]: check abs(ch(proofOf(c), sh) - ch(q, sh)) <= 1
    check inkOf(0xFFFFFFFF'u32) == toInk.rgbToCmyk(0xFFFFFFFF'u32) and inkOf(0xFF000000'u32) == toInk.rgbToCmyk(0xFF000000'u32)
    # between: near it
    for c in colors:
      for k in 0 .. 3: check abs(int(inkOf(c)[k]) - int(toInk.rgbToCmyk(c)[k])) <= 6
    check printed(100, 50, 20, 10) == shown.cmykToRgb(100, 50, 20, 10) and printed(100, 50, 20, 10) != beforePrinted
    check fromInk([0'u8, 0, 0, 0]) == shown.cmykToRgb(0, 0, 0, 0)
    for (c, m, y, k) in [(100, 50, 20, 10), (0, 255, 255, 0), (30, 30, 30, 200)]:
      let a = printedFast(c, m, y, k)
      let b = printed(c, m, y, k)
      for s in [0, 8, 16]: check abs(ch(a, s) - ch(b, s)) <= 3
    # gamut: gray prints, sRGB's blue does not
    check inGamut(0xFF808080'u32) and not inGamut(0xFF0000FF'u32)
    check gamutDistance(0xFF808080'u32) <= 4
    # another profile: the tables follow
    let inkA = inkOf(0xFF3366CC'u32)
    check setInkProfile(readFile(dir / "retro_ink_model.icc"), riRelative, bpc = false)
    check inkProfileName() == "Retro Photo Ink Model" and inkOf(0xFF3366CC'u32) != inkA
    # (the model as a profile, without compensation: near the model itself)
    for i, c in colors:
      for k in 0 .. 3: check abs(int(inkOf(c)[k]) - int(before[i][0][k])) <= 26
    check setInkProfile(icc, riPerceptual, bpc = false, simulatePaper = true)
    let paper = proofOf(0xFFFFFFFF'u32)
    check ch(paper, 16) < 250 and ch(paper, 8) < 252  # the paper's own white (Fogra27's: a little blue)
    # back to the model: as before, exactly
    check setInkProfile("")
    check inkProfile() == "" and inkProfileName() == ""
    for i, c in colors:
      check inkOf(c) == before[i][0] and proofOf(c) == before[i][1] and gamutDistance(c) == before[i][2]
    check printed(100, 50, 20, 10) == beforePrinted
