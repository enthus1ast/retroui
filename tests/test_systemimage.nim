## HEIC / HEIF and AVIF read and written by the system's own libraries
## (systemimage): libheif and libavif opened at run time on Linux. Each
## decode is compared with a reference decode (pillow-heif, Pillow) and with
## the picture it was made from; a library, or a codec plugin of libheif,
## that is not installed is skipped and said so. The pictures:
## tests/data/systemimage (make_images.py makes them).

include retroui/systemimage
import std/[os, strutils]

const dir = currentSourcePath.parentDir / "data" / "systemimage"

proc meanError(a, b: Bitmap; alpha = false): float =
  ## Mean absolute difference per channel, in 8-bit levels.
  doAssert a.w == b.w and a.h == b.h, $a.w & "x" & $a.h & " vs " & $b.w & "x" & $b.h
  var sum = 0
  let shifts = if alpha: @[24, 16, 8, 0] else: @[16, 8, 0]
  for i in 0 ..< a.px.len:
    for s in shifts:
      sum += abs(int((a.px[i] shr s) and 255) - int((b.px[i] shr s) and 255))
  sum / (a.px.len * shifts.len)

proc meanError16(a, b: openArray[uint16]; channels = 3): float =
  ## The same for R G B A 16-bit pixels, in 8-bit levels.
  doAssert a.len == b.len
  var sum = 0.0
  var n = 0
  for i in 0 ..< a.len div 4:
    for k in 0 ..< channels:
      sum += abs(float(a[4 * i + k]) - float(b[4 * i + k])) / 257
      inc n
  sum / float(n)

proc picture(name: string): Bitmap =
  result = loadPicture(dir / name, 4096, 4096)
  doAssert result != nil, name

proc png16(name: string): seq[uint16] =
  discard decodePng(readFile(dir / name), addr result)

let reference = picture("ref.png")
let reference16 = png16("ref16.png")
doAssert reference16.len == reference.w * reference.h * 4

# ---- the helpers --------------------------------------------------------------

block:
  doAssert isAvif(readFile(dir / "photo.avif")) and isAvif(readFile(dir / "deep.avif"))
  doAssert not isAvif(readFile(dir / "photo.heic")) and not isAvif(readFile(dir / "ref.png"))
  doAssert encodeKind("HEIC") == "heic" and encodeKind(".heif") == "heic" and
           encodeKind("avif") == "avif" and encodeKind("png") == ""
  # HEIF's turn (counter-clockwise quarters) and mirror as EXIF orientations
  doAssert orientationOf(0, -1) == 1 and orientationOf(1, -1) == 8 and
           orientationOf(2, -1) == 3 and orientationOf(3, -1) == 6
  doAssert orientationOf(0, 1) == 2 and orientationOf(0, 0) == 4
  doAssert orientationOf(3, 1) == 5 and orientationOf(3, 0) == 7
  doAssert orientationOf(1, 1) == 7 and orientationOf(1, 0) == 5
  doAssert orientationOf(2, 1) == 4 and orientationOf(2, 0) == 2
  # a 3 x 2 picture turned a quarter clockwise (6): 2 x 3, its left column on top
  let px = @[1'u32, 2, 3,
             4, 5, 6]
  doAssert oriented(px, 3, 2, 1, 6) == @[4'u32, 1, 5, 2, 6, 3]
  doAssert oriented(px, 3, 2, 1, 8) == @[3'u32, 6, 2, 5, 1, 4]
  doAssert oriented(px, 3, 2, 1, 3) == @[6'u32, 5, 4, 3, 2, 1]
  doAssert oriented(px, 3, 2, 1, 2) == @[3'u32, 2, 1, 6, 5, 4]
  # four values a pixel move together
  let deep = @[1'u16, 1, 1, 1, 2, 2, 2, 2]
  doAssert oriented(deep, 2, 1, 4, 6) == deep
  doAssert oriented(deep, 2, 1, 4, 2) == @[2'u16, 2, 2, 2, 1, 1, 1, 1]

# ---- libavif ------------------------------------------------------------------

if not loadAvif():
  echo "SKIP libavif: libavif.so.16 is not installed"
else:
  block:
    let b = avifDecode(readFile(dir / "photo.avif"), nil)
    doAssert b != nil
    let e = meanError(b, picture("photo.avif.png"))
    let o = meanError(b, reference)
    echo "libavif  photo.avif  vs Pillow's decode ", e.formatFloat(ffDecimal, 3),
         ", vs the original ", o.formatFloat(ffDecimal, 3)
    doAssert e < 1.0 and o < 4.0 and b.opaque
  block:
    let b = avifDecode(readFile(dir / "alpha.avif"), nil)
    doAssert b != nil and not b.opaque
    let e = meanError(b, picture("alpha.avif.png"), alpha = true)
    echo "libavif  alpha.avif  vs Pillow's decode (with alpha) ", e.formatFloat(ffDecimal, 3)
    doAssert e < 1.0
    doAssert (b.px[0] shr 24) < 8 and (b.px[b.w - 1] shr 24) > 247
  block:
    # 10 bits: the 16-bit pixels too
    var hi: seq[uint16]
    let b = avifDecode(readFile(dir / "deep.avif"), addr hi)
    doAssert b != nil and hi.len == b.w * b.h * 4
    let e = meanError16(hi, reference16)
    echo "libavif  deep.avif   10 bits, vs the 16-bit original ", e.formatFloat(ffDecimal, 3)
    doAssert e < 2.0
    doAssert hi[3] == 65535                              # opaque: alpha all the way
    doAssert meanError(b, bitmapOf16(b.w, b.h, reference16)) < 2.0
    # without asking for them, 8 bits only
    let b8 = avifDecode(readFile(dir / "deep.avif"), nil)
    doAssert b8 != nil and meanError(b8, b) < 1.0
  block:
    # stored turned a quarter counter-clockwise, then top and bottom exchanged
    # ('irot' 1, 'imir' 0): shown, the original transposed
    let b = avifDecode(readFile(dir / "turned.avif"), nil)
    doAssert b != nil and b.w == reference.h and b.h == reference.w, $b.w & "x" & $b.h
    var t = newBitmap(reference.h, reference.w)
    t.px = oriented(reference.px, reference.w, reference.h, 1, 5)
    let e = meanError(b, t)
    echo "libavif  turned.avif irot + imir applied, vs the original transposed ", e.formatFloat(ffDecimal, 3)
    doAssert e < 4.0
    if loadHeif():
      # libheif turns it by itself: the same picture
      let h = heifDecode(readFile(dir / "turned.avif"), nil)
      if h != nil:
        doAssert h.w == b.w and h.h == b.h and meanError(h, b) < 1.0
        echo "libheif  turned.avif the same as libavif's, after the turn: ",
             meanError(h, b).formatFloat(ffDecimal, 3)

# ---- libheif ------------------------------------------------------------------

proc heifCan(format: cint): bool =
  loadHeif() and (let f = cast[proc (fmt: cint): cint {.cdecl.}](
                    loadLib("libheif.so.1").symAddr("heif_have_decoder_for_format"));
                  f != nil and f(format) != 0)

if not loadHeif():
  echo "SKIP libheif: libheif.so.1 is not installed"
else:
  if not heifCan(HeifCompressionHevc):
    echo "SKIP libheif HEIC: no HEVC decoder plugin (libheif-plugin-libde265)"
  else:
    block:
      let b = heifDecode(readFile(dir / "photo.heic"), nil)
      doAssert b != nil
      let e = meanError(b, picture("photo.heic.png"))
      let o = meanError(b, reference)
      echo "libheif  photo.heic  vs pillow-heif's decode ", e.formatFloat(ffDecimal, 3),
           ", vs the original ", o.formatFloat(ffDecimal, 3)
      doAssert e < 1.0 and o < 4.0 and b.opaque
    block:
      var hi: seq[uint16]
      let b = heifDecode(readFile(dir / "deep.heic"), addr hi)
      doAssert b != nil and hi.len == b.w * b.h * 4
      let e = meanError16(hi, reference16)
      echo "libheif  deep.heic   10 bits, vs the 16-bit original ", e.formatFloat(ffDecimal, 3)
      doAssert e < 2.0 and hi[3] == 65535
    block:
      # through the API: the library first
      var hi: seq[uint16]
      let b = decodeWithSystem(dir / "deep.heic", addr hi)
      doAssert b != nil and hi.len == b.w * b.h * 4
  if not heifCan(HeifCompressionAv1):
    echo "SKIP libheif AVIF: no AV1 decoder plugin"
  else:
    block:
      let b = heifDecode(readFile(dir / "photo.avif"), nil)
      doAssert b != nil
      let e = meanError(b, picture("photo.avif.png"))
      echo "libheif  photo.avif  vs Pillow's decode ", e.formatFloat(ffDecimal, 3)
      doAssert e < 1.0
      let a = heifDecode(readFile(dir / "alpha.avif"), nil)
      doAssert a != nil and meanError(a, picture("alpha.avif.png"), alpha = true) < 1.0

# ---- the API ------------------------------------------------------------------

block:
  if loadAvif() or heifCan(HeifCompressionAv1):
    let b = decodeWithSystem(dir / "photo.avif")
    doAssert b != nil and meanError(b, reference) < 4.0
  # not a picture at all: nil (converters are tried and fail too)
  let junk = getTempDir() / "retro-test-not-a-picture.heic"
  writeFile(junk, "this is not a picture")
  doAssert decodeWithSystem(junk) == nil
  removeFile(junk)
  doAssert decodeWithSystem(dir / "no-such-file.avif") == nil
  doAssert systemImageNote().len > 0

# ---- writing --------------------------------------------------------------------

let kinds = systemEncodeExts()
echo "encoders found: ", (if kinds.len == 0: "none" else: kinds.join(", ")),
     "  (libavif AV1 encoder: ",
     (if loadAvif() and avif.codecName != nil and avif.codecName(0, AvifCodecFlagCanEncode) != nil:
        $avif.codecName(0, AvifCodecFlagCanEncode) else: "none"),
     "; libheif HEVC encoder: ", heifCanEncode(HeifCompressionHevc),
     ", AV1 encoder: ", heifCanEncode(HeifCompressionAv1), ")"
doAssert encodeWithSystem(reference, "png", 90) == ""
doAssert encodeWithSystem(nil, "avif", 90) == ""
for kind in ["heic", "avif"]:
  let bytes = encodeWithSystem(reference, kind, 90)
  if kind notin kinds:
    doAssert bytes.len == 0
    echo "SKIP writing ", kind, ": no encoder"
    continue
  doAssert bytes.len > 100 and bytes[4 .. 7] == "ftyp", kind
  doAssert isAvif(bytes) == (kind == "avif")
  let f = getTempDir() / ("retro-test-written." & kind)
  writeFile(f, bytes)
  let back = decodeWithSystem(f)
  removeFile(f)
  if back == nil:
    echo "SKIP reading back the written ", kind, ": no decoder"
    continue
  let e = meanError(back, reference)
  echo "written  ", kind, " (", bytes.len, " bytes), read back vs the original ", e.formatFloat(ffDecimal, 3)
  doAssert e < 4.0
  # see-through pixels stay see-through
  var t = newBitmap(reference.w, reference.h)
  for i in 0 ..< t.px.len: t.px[i] = (uint32(i mod reference.w * 255 div (reference.w - 1)) shl 24) or
                                     (reference.px[i] and 0xFFFFFF'u32)
  let tb = encodeWithSystem(t, kind, 95)
  doAssert tb.len > 0
  writeFile(f, tb)
  let tback = decodeWithSystem(f)
  removeFile(f)
  if tback != nil:
    doAssert not tback.opaque
    doAssert abs(int(tback.px[tback.w - 1] shr 24) - 255) < 8 and int(tback.px[0] shr 24) < 8
  # and through libheif too, when it has an encoder of its own for it
  if kind == "avif" and heifCanEncode(HeifCompressionAv1):
    let hb = heifEncode(reference, HeifCompressionAv1, 90)
    doAssert hb.len > 0 and isAvif(hb)
    let hback = avifDecode(hb, nil)
    if hback != nil:
      echo "written  avif by libheif, read back by libavif vs the original ",
           meanError(hback, reference).formatFloat(ffDecimal, 3)
      doAssert meanError(hback, reference) < 4.0

echo "systemimage tests passed"
