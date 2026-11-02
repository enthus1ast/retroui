## Tests of retro/iccprofile: profiles read, made, converted and carried in
## files.

import std/[unittest, math]
import retro/[iccprofile, imaging, jpeg, gfx, imageformats]

proc px3(r, g, b: int): uint32 = 0xFF000000'u32 or (uint32(r) shl 16) or (uint32(g) shl 8) or uint32(b)
proc ch(p: uint32; s: int): int = int((p shr s) and 255)

suite "profiles":
  test "built in, written and read back":
    for name in builtInProfileNames:
      let p = builtInProfile(name)
      check p.usable and p.data.len > 200
      let q = parseIcc(p.data)
      check q.usable and q.name == name and q.colorSpace == "RGB "
      for k in 0 .. 8: check abs(q.toXyz[k] - p.toXyz[k]) < 1e-3
      for x in [0.05, 0.3, 0.7, 1.0]:
        check abs(q.trc[0].eval(x) - p.trc[0].eval(x)) < 2e-3
    check srgbProfile().isSrgbLike and parseIcc(srgbProfile().data).isSrgbLike
    check not adobeRgbProfile().isSrgbLike and not displayP3Profile().isSrgbLike
    let g = parseIcc(grayProfile().data)
    check g.usable and g.colorSpace == "GRAY"
    # sRGB's white is D50 in the profile, its columns add up to it
    let s = srgbProfile()
    check abs(s.toXyz[3] + s.toXyz[4] + s.toXyz[5] - 1.0) < 1e-4
    check abs(s.toXyz[0] + s.toXyz[1] + s.toXyz[2] - 0.9642) < 2e-3

  test "converting":
    var px = @[px3(0, 0, 0), px3(255, 255, 255), px3(128, 64, 200), px3(0, 255, 0)]
    let before = px
    convertPixels(px, srgbProfile(), srgbProfile())
    for i in 0 ..< 3:
      for sft in [0, 8, 16]: check abs(ch(px[i], sft) - ch(before[i], sft)) <= 1
    # P3's green is greener than sRGB can show: clipped to sRGB's
    var p3 = @[px3(0, 255, 0), px3(255, 255, 255), px3(118, 118, 118)]
    convertPixels(p3, displayP3Profile(), srgbProfile())
    check ch(p3[0], 8) == 255 and ch(p3[0], 16) == 0
    check ch(p3[1], 16) >= 254 and ch(p3[1], 0) >= 254
    check abs(ch(p3[2], 16) - 118) <= 1 and abs(ch(p3[2], 0) - 118) <= 1
    # and there and back: near
    var a = @[px3(200, 120, 60), px3(30, 90, 160)]
    let a0 = a
    convertPixels(a, srgbProfile(), adobeRgbProfile())
    check a != a0
    convertPixels(a, adobeRgbProfile(), srgbProfile())
    for i in 0 ..< 2:
      for sft in [0, 8, 16]: check abs(ch(a[i], sft) - ch(a0[i], sft)) <= 2

  test "in JPEG, PNG and TIFF files":
    let b = newBitmap(8, 8)
    for p in b.px.mitems: p = px3(10, 200, 30)
    let icc = displayP3Profile().data
    let j = embedInJpeg(encodeJpeg(b, 90), icc)
    check iccFromJpeg(j) == icc
    check decodeJpeg(j).w == 8
    # (a long profile: in several segments)
    var big = icc
    while big.len < 150_000: big.add icc
    check iccFromJpeg(embedInJpeg(encodeJpeg(b, 90), big)) == big
    let png = embedInPng(encodePng(b), icc)
    check iccFromPng(png) == icc and decodePng(png).w == 8
    let tif = encodeTiff(b, icc = icc)
    check iccFromTiff(tif) == icc and decodeTiff(tif).w == 8
    check iccFromJpeg(encodeJpeg(b, 90)) == "" and iccFromPng(encodePng(b)) == ""

import std/os
import retro/[photo, photofiles]

suite "documents and profiles":
  test "opened: converted to sRGB, or kept":
    let b = newBitmap(4, 4)
    for p in b.px.mitems: p = px3(0, 255, 0)
    let path = getTempDir() / "p3.jpg"
    writeFile(path, embedInJpeg(encodeJpeg(b, 95), displayP3Profile().data))
    profilePolicy = ppConvert
    let d = openPicture(path)
    check d.icc == "" and ch(d.layers[0].px[0], 16) < 20 and ch(d.layers[0].px[0], 8) > 240
    profilePolicy = ppKeep
    let e = openPicture(path)
    check e.icc == displayP3Profile().data and e.profileName == "Display P3"
    check ch(e.layers[0].px[0], 8) > 240
    profilePolicy = ppIgnore
    check openPicture(path).icc == ""
    profilePolicy = ppConvert
    # kept in our documents and Photoshop's
    let r = getTempDir() / "p3.rpd"
    e.saveRpd(r)
    check loadRpd(r).icc == e.icc
    let s = getTempDir() / "p3.psd"
    e.savePsd(s)
    profilePolicy = ppKeep
    check openPicture(s).icc == e.icc
    profilePolicy = ppConvert
    # exported with it (or sRGB)
    let x = getTempDir() / "out.png"
    e.exportPicture(x, defaultExport(efPng))
    check iccFromPng(readFile(x)) == e.icc
    d.exportPicture(x, defaultExport(efPng))
    check parseIcc(iccFromPng(readFile(x))).isSrgbLike
    var o = defaultExport(efJpeg)
    o.embedProfile = false
    d.exportPicture(getTempDir() / "out.jpg", o)
    check iccFromJpeg(readFile(getTempDir() / "out.jpg")) == ""
    # Convert to Profile: the colors kept, the numbers changed
    let c = openPicture(path)
    let before = c.layers[0].px[0]
    c.convertProfile(adobeRgbProfile())
    check c.profileName == "Adobe RGB (1998)" and c.layers[0].px[0] != before
    c.convertProfile(srgbProfile())
    check c.icc == "" and abs(ch(c.layers[0].px[0], 8) - ch(before, 8)) <= 3
    for f in [path, r, s, x, getTempDir() / "out.jpg"]: removeFile(f)
