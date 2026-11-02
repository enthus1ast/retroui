## Tests of `retro/morepictures`: each kind of file it teaches `loadPicture`
## made here -- with the kit's own encoders, or by hand (a Photoshop file
## with its thumbnail; raw files shaped as cameras write them: TIFF
## directories, SubIFDs, maker's notes of Nikon, Olympus and Pentax, a CR3's
## boxes, a RAF's header, a JPEG past the first megabytes) -- and read back
## at thumbnail size: its size, shape, orientation and colors checked. Then
## each file is damaged a few hundred ways (cut short, bytes changed) and
## read again: nil is fine, an exception or a crash is not.

include retro/morepictures
import std/[random, times]
import retro/[photohdr, parallel]    # (writeHdr; runAlone)
when desktop:
  import retro/gifanim

const
  rounds {.intdefine.} = 300      ## damaged copies of each file (-d:rounds=2000: a longer run)
  seed {.intdefine.} = 20261101
  red = 0xFFFF0000'u32
  blue = 0xFF0000FF'u32
  green = 0xFF00FF00'u32
  yellow = 0xFFFFFF00'u32

let tmpDir = getTempDir() / ("retro-morepictures-" & $getCurrentProcessId())
removeDir(tmpDir)
createDir(tmpDir)

# ---- helpers ------------------------------------------------------------------------------------

proc halves(w, h: int; a, b: uint32; across = true): Bitmap =
  ## Left half `a`, right half `b` (`across` false: top and bottom).
  result = newBitmap(w, h)
  for y in 0 ..< h:
    for x in 0 ..< w:
      result.px[y * w + x] = if (if across: x < w div 2 else: y < h div 2): a else: b
  result.opaque = (a shr 24) == 255 and (b shr 24) == 255
  result.changed()

proc near(p, c: uint32; tol = 40): bool =
  for s in [24, 16, 8, 0]:
    if abs(int((p shr s) and 255) - int((c shr s) and 255)) > tol: return false
  true

proc at(b: Bitmap; fx, fy: float): uint32 =
  b.px[min(b.h - 1, int(fy * b.h.float)) * b.w + min(b.w - 1, int(fx * b.w.float))]

proc check(name: string; b: Bitmap; w, h: int; probes: openArray[(float, float, uint32)]; tol = 40) =
  doAssert b != nil, name & ": nil"
  doAssert b.w == w and b.h == h, name & ": " & $b.w & " x " & $b.h & ", not " & $w & " x " & $h
  for (fx, fy, c) in probes:
    let p = b.at(fx, fy)
    doAssert near(p, c, tol), name & ": " & toHex(p) & " at " & $fx & ", " & $fy & ", not " & toHex(c)

proc leftRight(a, b: uint32): seq[(float, float, uint32)] = @[(0.2, 0.5, a), (0.8, 0.5, b)]
proc topBottom(a, b: uint32): seq[(float, float, uint32)] = @[(0.5, 0.2, a), (0.5, 0.8, b)]

proc w16(v: int; le: bool): string =
  if le: char(v and 255) & char((v shr 8) and 255) else: char((v shr 8) and 255) & char(v and 255)

proc w32(v: int; le: bool): string =
  if le: w16(v and 0xFFFF, true) & w16((v shr 16) and 0xFFFF, true)
  else: w16((v shr 16) and 0xFFFF, false) & w16(v and 0xFFFF, false)

proc be32(v: int): string = w32(v, false)

type Ent = tuple[tag, kind: int; vals: seq[int]; data: string]
  ## A TIFF entry: numbers, or (`data`) bytes.

proc num(tag, kind: int; vals: varargs[int]): Ent = (tag, kind, @vals, "")
proc bytesOf(tag: int; data: string; kind = 7): Ent = (tag, kind, @[], data)

proc dirBytes(le: bool; at: int; ents: openArray[Ent]; next = 0): string =
  ## A TIFF directory to be placed at `at` (from its TIFF's start), the
  ## values that do not fit in it right after it.
  let extraAt = at + 2 + 12 * ents.len + 4
  var extra = ""
  result = w16(ents.len, le)
  for e in ents:
    var bytes = e.data
    if e.data.len == 0:
      for v in e.vals: bytes.add(if e.kind == 3: w16(v, le) else: w32(v, le))
    let count = if e.data.len > 0: e.data.len else: e.vals.len
    result.add w16(e.tag, le) & w16(e.kind, le) & w32(count, le)
    if bytes.len <= 4: result.add bytes & repeat('\0', 4 - bytes.len)
    else:
      if extra.len mod 2 == 1: extra.add '\0'
      result.add w32(extraAt + extra.len, le)
      extra.add bytes
  result.add w32(next, le) & extra

proc put(s: var string; data: string): int =
  if s.len mod 2 == 1: s.add '\0'
  result = s.len
  s.add data

proc putDir(s: var string; le: bool; ents: openArray[Ent]; base = 0): int =
  if s.len mod 2 == 1: s.add '\0'
  result = s.len
  s.add dirBytes(le, result - base, ents)

proc tiffHead(le: bool; magic = 42): string = (if le: "II" else: "MM") & w16(magic, le) & w32(0, le)

proc setFirst(s: var string; le: bool; at: int) = s[4 ..< 8] = w32(at, le)

proc withTurn(j: string; o: int): string =
  ## A JPEG with an EXIF segment saying orientation `o`.
  let tiff = "MM\0*" & w32(8, false) & w16(1, false) & w16(0x112, false) & w16(3, false) &
             w32(1, false) & w16(o, false) & "\0\0" & w32(0, false)
  let body = "Exif\0\0" & tiff
  j[0 .. 1] & "\xFF\xE1" & w16(body.len + 2, false) & body & j[2 .. ^1]

proc rgbBytes(b: Bitmap): string =
  for p in b.px: result.add char((p shr 16) and 255) & char((p shr 8) and 255) & char(p and 255)

proc found(path: string): tuple[cands: seq[Cand]; turn: int] =
  ## What the file's structure tells of (no looking through its bytes).
  var f = open(path)
  defer: f.close()
  var s = Src(f: f, size: int(getFileSize(f)))
  s.head = newString(min(s.size, HeadBytes))
  doAssert f.readBuffer(addr s.head[0], s.head.len) == s.head.len
  result.turn = 1
  s.structured(result.cands, result.turn)

let pic = halves(240, 160, red, blue)           # (the picture most files hold)
let jpic = encodeJpeg(pic, 92)
var samples: seq[string]                        # (the files damaged at the end)

proc sample(name, data: string): string =
  result = tmpDir / name
  writeFile(result, data)
  samples.add result

# ---- the kinds ----------------------------------------------------------------------------------

block kinds:
  doAssert ".jxl" in morePictureKinds and ".nef" in morePictureKinds and ".cr3" in morePictureKinds
  when desktop: doAssert ".gif" in morePictureKinds and ".heic" in morePictureKinds
  else: doAssert ".gif" notin morePictureKinds
  # (a reader a program gave first is kept; adding twice adds nothing)
  addPictureReader([".rgbe"], proc (path: string; maxW, maxH: int): Bitmap {.nimcall, gcsafe.} =
    newBitmap(3, 3, 0xFF123456'u32))
  addMorePictures()
  addMorePictures()
  let own = loadPicture(tmpDir / "x.rgbe", 128, 128)
  doAssert own != nil and own.w == 3 and own.px[0] == 0xFF123456'u32
  doAssert pictureReaderFor("a.NEF") != nil and pictureReaderFor("a.svg") != nil
  doAssert readMorePicture(tmpDir / "none.png") == nil and readMorePicture(tmpDir / "missing.jxl") == nil

# ---- pictures of the kit's own encoders --------------------------------------------------------

block jxlFile:
  let p = sample("pic.jxl", encodeJxlLossless(pic))
  check("jxl", loadPicture(p, 128, 128), 128, 85, leftRight(red, blue), 2)

block svgFiles:
  let p = sample("pic.svg", """<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">
    <rect width="100" height="100" fill="#ff0000"/><rect x="100" width="100" height="100" fill="#0000ff"/></svg>""")
  check("svg", loadPicture(p, 128, 128), 128, 64, leftRight(red, blue), 2)
  # (drawn at the size asked for, not made smaller from another)
  check("svg big", loadPicture(p, 1000, 1000), 1000, 500, leftRight(red, blue), 2)
  let q = sample("tall.svg", """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 50 100">
    <circle cx="25" cy="50" r="25" fill="#00ff00"/></svg>""")
  check("svg viewBox", loadPicture(q, 128, 128), 64, 128, @[(0.5, 0.5, green), (0.02, 0.02, 0'u32)], 2)
  doAssert loadPicture(sample("empty.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\"/>"), 64, 64) == nil

block tiffFiles:
  check("tiff", loadPicture(sample("pic.tif", encodeTiff(pic, tcLzw, alpha = false)), 128, 128),
        128, 85, leftRight(red, blue), 2)
  let half = halves(240, 160, red, 0x800000FF'u32)
  check("tiff alpha", loadPicture(sample("alpha.tiff", encodeTiff(half, tcDeflate)), 128, 128),
        128, 85, leftRight(red, 0x800000FF'u32), 2)

block tgaFiles:
  check("tga", loadPicture(sample("pic.tga", encodeTga(pic)), 128, 128), 128, 85, leftRight(red, blue), 2)
  check("tga flat", loadPicture(sample("flat.tga", encodeTga(pic, alpha = false, rle = false)), 128, 128),
        128, 85, leftRight(red, blue), 2)

proc light(w, h: int; a, b: array[4, float32]; across = true): seq[float32] =
  for y in 0 ..< h:
    for x in 0 ..< w:
      result.add(if (if across: x < w div 2 else: y < h div 2): @a else: @b)

block exrFiles:
  # (2 times brighter than white: cut to white; 0.214 of light: 128 on the screen)
  let l = light(240, 160, [2'f32, 0, 0, 1], [0'f32, 0, 0.214, 1])
  check("exr", loadPicture(sample("pic.exr", writeExr(240, 160, l)), 128, 128),
        128, 85, leftRight(red, 0xFF000080'u32), 3)
  let la = light(64, 32, [0.5'f32, 0, 0, 0.5], [0'f32, 0.214, 0, 1])
  check("exr alpha", loadPicture(sample("alpha.exr", writeExr(64, 32, la, half = false, compression = "piz")), 128, 128),
        64, 32, leftRight(0x80FF0000'u32, 0xFF008000'u32), 3)
  doAssert bitmapOfLight(2, 1, [0.5'f32, 0, 0, 0.5, 0, 0, 1, 0], alpha = false).px == @[0xFFBC0000'u32, 0xFF0000FF'u32]

block hdrFiles:
  let l = light(240, 160, [1'f32, 0, 0, 1], [0'f32, 0, 0.214, 1], across = false)
  let data = writeHdr(240, 160, l)
  check("hdr", loadPicture(sample("pic.hdr", data), 128, 128), 128, 85, topBottom(red, 0xFF000080'u32), 3)
  # (rows bottom first)
  check("hdr +Y", loadPicture(sample("up.hdr", data.replace("-Y 160", "+Y 160")), 128, 128),
        128, 85, topBottom(0xFF000080'u32, red), 3)
  # (narrower than 8: flat)
  check("hdr flat", loadPicture(sample("flat.hdr", writeHdr(6, 4, light(6, 4, [1'f32, 0, 0, 1], [0'f32, 1, 0, 1]))), 128, 128),
        6, 4, leftRight(red, green), 2)

when desktop:
  block gifFiles:
    let animated = encodeGifFrames(240, 160, [(pic.px, 100), (halves(240, 160, green, green).px, 100)])
    check("gif", loadPicture(sample("anim.gif", animated), 128, 128), 128, 85, leftRight(red, blue), 2)
    check("gif still", loadPicture(sample("still.gif", encodeGif(240, 160, quantize(pic.px))), 128, 128),
          128, 85, leftRight(red, blue), 2)
    doAssert gifFirstEnd(animated) > 0 and gifFirstEnd(animated) < animated.len - 10

  block webpFiles:
    check("webp", loadPicture(sample("pic.webp", encodeWebpLossless(pic)), 128, 128), 128, 85, leftRight(red, blue), 2)
    check("webp lossy", loadPicture(sample("lossy.webp", encodeWebp(pic, 90)), 128, 128), 128, 85, leftRight(red, blue))

  block systemFiles:
    # (decoded by the system's libraries when there are some: libheif and libavif here)
    for name in ["photo.heic", "photo.avif"]:
      let p = currentSourcePath.parentDir / "data" / "systemimage" / name
      let whole = decodeWithSystem(p)
      if whole == nil:
        echo "  (", name, ": this system cannot decode it -- not checked)"
        continue
      let b = loadPicture(p, 48, 48)
      doAssert b != nil and max(b.w, b.h) == 48, name
      doAssert abs(b.w / b.h - whole.w / whole.h) < 0.05, name

# ---- documents ---------------------------------------------------------------------------------

proc psd(version: int; id: int; thumb: string): string =
  ## A Photoshop file with a thumbnail resource (and nothing else of use).
  result = "8BPS" & w16(version, false) & repeat('\0', 6) & w16(3, false) & be32(160) & be32(240) &
           w16(8, false) & w16(3, false)
  result.add be32(0)                                 # (no color mode data)
  var res = "8BIM" & w16(1005, false) & "\0\0" & be32(4) & "abcd"     # (another resource first)
  let body = be32(1) & be32(240) & be32(160) & be32(720) & be32(720 * 160) & be32(thumb.len) &
             w16(24, false) & w16(1, false) & thumb
  res.add "8BIM" & w16(id, false) & "\x03abc" & be32(body.len) & body
  if body.len mod 2 == 1: res.add '\0'
  result.add be32(res.len) & res & be32(0) & w16(0, false)

block psdFiles:
  check("psd", loadPicture(sample("pic.psd", psd(1, 1036, jpic)), 128, 128), 128, 85, leftRight(red, blue))
  # (Photoshop 4's: blue and red swapped in it)
  let swapped = encodeJpeg(halves(240, 160, blue, red), 92)
  check("psb 1033", loadPicture(sample("pic.psb", psd(2, 1033, swapped)), 128, 128), 128, 85, leftRight(red, blue))
  doAssert loadPicture(sample("none.psd", psd(1, 1005, jpic)), 128, 128) == nil

block rpdFiles:
  var z = newZipWriter()
  z.addFile("document.json", "{\"width\": 240, \"height\": 160}")
  z.addFile("layer0.png", encodePng(halves(240, 160, green, green)))
  z.addFile("preview.png", encodePng(pic))
  check("rpd", loadPicture(sample("pic.rpd", z.finish()), 128, 128), 128, 85, leftRight(red, blue), 2)
  var old = newZipWriter()
  old.addFile("document.json", "{}")
  old.addFile("layer0.png", encodePng(pic))
  check("rp3 layer", loadPicture(sample("old.rp3", old.finish()), 128, 128), 128, 85, leftRight(red, blue), 2)

# ---- camera raw files ----------------------------------------------------------------------------

block nef:
  # (Nikon: a small preview in IFD0, a bigger one in a SubIFD, the camera held a quarter clockwise)
  var s = tiffHead(true)
  let small = encodeJpeg(halves(120, 80, red, blue), 92)
  let sm = s.put(small)
  let bg = s.put(jpic)
  let sub = s.putDir(true, [num(0xFE, 4, 0), num(0x201, 4, bg), num(0x202, 4, jpic.len)])
  let ifd0 = s.putDir(true, [num(0xFE, 4, 1), num(0x112, 3, 6), num(0x14A, 4, sub),
                             num(0x201, 4, sm), num(0x202, 4, small.len)])
  s.setFirst(true, ifd0)
  let p = sample("shot.nef", s)
  let (cands, turn) = found(p)
  doAssert cands.len == 2 and turn == 6
  check("nef", loadPicture(p, 128, 128), 85, 128, topBottom(red, blue))
  check("nef biggest", rawPreview(p, 1000, 1000), 160, 240, topBottom(red, blue))
  check("nef smaller", rawPreview(p, 60, 60), 40, 60, topBottom(red, blue))
  check("nef eighth", rawPreview(p, 10, 10), 6, 10, topBottom(red, blue), 60)

block makerNotes:
  # (Nikon: the preview's directory in the maker's notes, their own TIFF)
  var note = tiffHead(true)
  let jp = note.put(jpic)
  let pv = note.putDir(true, [num(0x201, 4, jp), num(0x202, 4, jpic.len)])
  let nd = note.putDir(true, [bytesOf(0x1, "0210"), num(0x11, 13, pv)])
  note.setFirst(true, nd)
  var s = tiffHead(true)
  let exif = s.putDir(true, [bytesOf(0x927C, "Nikon\0\x02\x10\0\0" & note)])
  s.setFirst(true, s.putDir(true, [num(0x112, 3, 1), num(0x8769, 4, exif)]))
  let p = sample("note.nef", s)
  doAssert found(p).cands.len == 1
  check("nikon notes", loadPicture(p, 128, 128), 128, 85, leftRight(red, blue))
  # (Olympus: CameraSettings, offsets from the notes' start)
  var oly = "OLYMPUS\0II\x03\0"
  oly.add dirBytes(true, 12, [num(0x2020, 13, 30)])
  oly.add dirBytes(true, 30, [num(0x100, 4, 1), num(0x101, 4, 72), num(0x102, 4, jpic.len)])
  oly.add jpic
  var o = tiffHead(true, 0x4F52)                 # ("IIRO")
  let oexif = o.putDir(true, [bytesOf(0x927C, oly)])
  o.setFirst(true, o.putDir(true, [num(0x112, 3, 3), num(0x8769, 4, oexif)]))
  let op = sample("shot.orf", o)
  let (oc, ot) = found(op)
  doAssert oc.len == 1 and ot == 3
  check("olympus notes", loadPicture(op, 128, 128), 128, 85, leftRight(blue, red))
  # (Pentax: its preview's place from the file's TIFF)
  var x = tiffHead(false)
  let xj = x.put(jpic)
  let pexif = x.putDir(false, [bytesOf(0x927C, "AOC\0MM" & dirBytes(false, 0, [num(0x4, 4, jpic.len), num(0x5, 4, xj)]))])
  x.setFirst(false, x.putDir(false, [num(0x112, 3, 1), num(0x8769, 4, pexif)]))
  let xp = sample("shot.pef", x)
  doAssert found(xp).cands.len == 1
  check("pentax notes", loadPicture(xp, 128, 128), 128, 85, leftRight(red, blue))

block dng:
  # (big-endian; an RGB thumbnail in IFD0; the raw -- lossless JPEG -- and a
  # preview in SubIFDs; held a quarter counter-clockwise)
  let pic2 = halves(300, 200, green, yellow)
  let jp2 = encodeJpeg(pic2, 92)
  let lossless = "\xFF\xD8\xFF\xC3\x00\x0B\x10\x01\x90\x02\x58\x01\x01\x11\x00" &
                 "\xFF\xDA\x00\x08\x01\x01\x00\x00\x00\x00" & repeat("\x12\x34", 500) & "\xFF\xD9"
  var s = tiffHead(false)
  let th = s.put(rgbBytes(halves(60, 40, green, yellow)))
  let raw = s.put(lossless)
  let pv = s.put(jp2)
  let rawDir = s.putDir(false, [num(0xFE, 4, 0), num(0x100, 4, 600), num(0x101, 4, 400), num(0x103, 3, 7),
                                num(0x111, 4, raw), num(0x117, 4, lossless.len)])
  let pvDir = s.putDir(false, [num(0xFE, 4, 1), num(0x100, 4, 300), num(0x101, 4, 200), num(0x103, 3, 7),
                               num(0x111, 4, pv), num(0x117, 4, jp2.len)])
  s.setFirst(false, s.putDir(false, [num(0xFE, 4, 1), num(0x100, 4, 60), num(0x101, 4, 40),
      num(0x102, 3, 8, 8, 8), num(0x103, 3, 1), num(0x106, 3, 2), num(0x111, 4, th), num(0x112, 3, 8),
      num(0x115, 3, 3), num(0x117, 4, 7200), num(0x11C, 3, 1), num(0x14A, 4, rawDir, pvDir),
      bytesOf(0xC612, "\x01\x04\x00\x00", 1)]))
  let p = sample("shot.dng", s)
  let (cands, turn) = found(p)
  doAssert cands.len == 2 and turn == 8         # (the thumbnail and the preview; not the raw)
  check("dng", loadPicture(p, 128, 128), 85, 128, topBottom(yellow, green))
  check("dng thumbnail", rawPreview(p, 40, 40), 26, 40, topBottom(yellow, green), 2)

block arw:
  # (the JPEG says how it is turned itself: turned once, not twice)
  let own = withTurn(jpic, 6)
  doAssert decodeJpeg(own).w == 160
  var s = tiffHead(true)
  let jp = s.put(own)
  s.setFirst(true, s.putDir(true, [num(0x112, 3, 6), num(0x201, 4, jp), num(0x202, 4, own.len)]))
  check("arw", loadPicture(sample("shot.arw", s), 128, 128), 85, 128, topBottom(red, blue))

proc box(kind, body: string): string = be32(8 + body.len) & kind & body

block cr3:
  # (Canon: ISO boxes; a 4:3 thumbnail with black bars is passed over for the preview)
  var cmt1 = tiffHead(true)
  cmt1.setFirst(true, cmt1.putDir(true, [bytesOf(0x10F, "Canon\0", 2), num(0x112, 3, 3)]))
  let thumb = encodeJpeg(halves(160, 120, green, green), 90)
  let uuid = "\x85\xc0\xb6\x87\x82\x0f\x11\xe0\x81\x11\xf4\xce\x46\x2b\x6a\x48"
  let data = box("ftyp", "crx \0\0\0\x01crx isom") &
    box("moov", box("uuid", uuid & box("CNCV", "CanonCR3_001/01.09.00/00.00.00") & box("CMT1", cmt1) &
                    box("THMB", "\0\0\0\0\0\xa0\0\x78" & be32(thumb.len) & "\0\x01\0\0" & thumb))) &
    box("uuid", "\xea\xf4\x2b\x5e\x1c\x98\x4b\x88\xb9\xfb\xb7\xdc\x40\x6e\x4d\x16" &
        box("PRVW", "\0\0\0\0\0\x01\0\xf0\0\xa0" & be32(jpic.len) & jpic)) &
    box("mdat", repeat("\x55\xAA", 3000))
  let p = sample("shot.cr3", data)
  doAssert found(p).turn == 3
  check("cr3", loadPicture(p, 128, 128), 128, 85, leftRight(blue, red))
  check("cr3 small", loadPicture(p, 100, 100), 100, 66, leftRight(blue, red))

block raf:
  # (Fujifilm: the JPEG's place in the header; it is turned by its own EXIF)
  let j = withTurn(jpic, 3)
  var data = "FUJIFILMCCD-RAW 0201FF383501"
  data.add repeat('\0', 84 - data.len)
  data.add be32(160) & be32(j.len)
  data.add repeat('\0', 160 - data.len)
  data.add j & repeat("\x01\x02", 2000)
  let p = sample("shot.raf", data)
  let (cands, _) = found(p)
  doAssert cands.len == 1 and cands[0].at == 160 and cands[0].own == 3
  check("raf", loadPicture(p, 128, 128), 128, 85, leftRight(blue, red))

block rw2:
  # (Panasonic: "IIU", the JPEG the value of tag 0x2E)
  var s = tiffHead(true, 0x55)
  s.setFirst(true, s.putDir(true, [bytesOf(0x2E, jpic), num(0x112, 3, 1)]))
  let p = sample("shot.rw2", s)
  doAssert found(p).cands.len == 1
  check("rw2", loadPicture(p, 128, 128), 128, 85, leftRight(red, blue))

block farAway:
  # (a preview past the first megabytes: read where the directory says ...)
  var s = tiffHead(true)
  let ifd0 = s.putDir(true, [num(0x112, 3, 1), num(0x201, 4, 5_000_000), num(0x202, 4, jpic.len)])
  s.setFirst(true, ifd0)
  s.add repeat('\0', 5_000_000 - s.len)
  s.add jpic
  let far = tmpDir / "far.pef"
  writeFile(far, s)
  check("far pef", loadPicture(far, 128, 128), 128, 85, leftRight(red, blue))
  # (... or found by looking through the rest of the file, where nothing tells)
  var x = "FOVb\x02\0\0\0"
  var r = 12345'u32
  while x.len < 5_000_000:
    r = r * 1103515245'u32 + 12345'u32
    x.add char((r shr 16) and 0x7F)
  x.add jpic & repeat("\0", 1000)
  let big = tmpDir / "big.x3f"
  writeFile(big, x)
  let t0 = cpuTime()
  check("x3f", loadPicture(big, 128, 128), 128, 85, leftRight(red, blue))
  echo "  a 5 MB file looked through in ", formatFloat((cpuTime() - t0) * 1000, ffDecimal, 1), " ms"

# ---- on worker threads, several at once (as the file lists ask for them) ------------------------

block threads:
  proc work(paths: seq[string]) {.thread.} =
    # (a thread of its own does its parallel work alone: the cores' pool is
    # the drawing thread's -- decoders sharing it from several threads at
    # once break)
    runAlone()
    {.cast(gcsafe).}:
      for p in paths:
        let b = loadPicture(p, 96, 96)
        doAssert b != nil and b.w <= 96 and b.h <= 96, p
  var paths: seq[string]
  for p in samples:
    if not (p.endsWith("empty.svg") or p.endsWith("none.psd")): paths.add p
  when desktop:
    let avif = currentSourcePath.parentDir / "data" / "systemimage" / "photo.avif"
    if decodeWithSystem(avif) != nil: paths.add avif
  var ths: array[3, Thread[seq[string]]]
  for i in 0 ..< ths.len: createThread(ths[i], work, paths)
  joinThreads(ths)

# ---- damaged files: nothing may raise or crash -------------------------------------------------

block damaged:
  var rng = initRand(seed)
  let t0 = epochTime()
  var loads = 0
  for path in samples:
    let data = readFile(path)
    let bad = tmpDir / ("bad" & path.splitFile.ext)
    for k in 0 ..< rounds:
      var d = data
      if k mod 3 == 0:
        d.setLen(rng.rand(data.len - 1))          # (cut short)
      else:
        # (bytes changed: most often where the headers and directories are)
        for _ in 0 .. rng.rand(1 .. 8):
          let i = if rng.rand(1) == 0: rng.rand(min(d.len, 600) - 1) else: rng.rand(d.len - 1)
          d[i] = char(rng.rand(255))
      writeFile(bad, d)
      try:
        let b = loadPicture(bad, (if k mod 5 == 0: 1024 else: 128), 128)
        if b != nil: doAssert b.w > 0 and b.h > 0 and b.px.len == b.w * b.h
      except CatchableError, Defect:
        doAssert false, path.extractFilename & ": " & getCurrentExceptionMsg()
      inc loads
  echo "  ", loads, " damaged files read in ", formatFloat(epochTime() - t0, ffDecimal, 1), " s"

removeDir(tmpDir)
echo "morepictures: ok"
