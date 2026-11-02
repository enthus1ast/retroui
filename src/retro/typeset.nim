## Text layout: the built-in fonts, Arabic letter joining, right-to-left
## text and the icon font.
##
## Every string is turned into a `Run`: glyphs from the built-in faces, in
## visual order, with their positions in em units (so one run serves every
## size). Arabic letters take their joined forms (and lam + alef its
## ligature), mixed Arabic/Latin lines follow the Unicode bidirectional
## algorithm (paragraph direction from the first strong letter), and
## characters the base face lacks come from the other faces: Latin, Greek,
## Cyrillic and Arabic from DejaVu Sans, icons from the Nerd Fonts symbols.
##
## Retro Sans (the default UI font) comes as smooth outlines for large text
## and high-resolution screens (`fRetro`, `fRetroBold`, with Unifont's
## Arabic in `fRetroAr`); at one pixel per brick the kit draws its bitmaps
## instead (see `font.nim`).

import std/[tables, unicode, math, locks]
import ttf, arabicdata, codec

type
  FaceId* = enum
    fSans, fBold, fMono, fMonoBold, fIcons,
    fRetro, fRetroBold, fRetroAr,         ## Retro Sans HD and its Arabic
    fKawkab, fKawkabBold,                 ## Kawkab Mono (Arabic and Latin, monospaced)
    fW98, fW98Bold,                       ## MS W98 UI (MS Sans Serif made outlines; on an 11 grid)
    fW98HD, fW98HDBold,                   ## ... its staircases smoothed (large text, HD screens)
    fUser, fUserBold                      ## a font from a file (`setUserFont`)

  PGlyph* = object
    face*: FaceId
    gid*: uint16
    x*, y*: float32          ## em units from the run's start; y is up

  Run* = object
    glyphs*: seq[PGlyph]
    width*: float32          ## em units
    missing*: bool           ## a character no built-in face has
    rtl*: bool               ## the text reads right to left

const
  # the fonts, zlib-compressed (tools/genfonts.py, tools/genretro.py): 590 KB
  # of TrueType take 325 KB in every app, and are unpacked when a face is
  # first used
  fontPacked: array[FaceId, string] = [
    staticRead("fonts/Sans.ttf.z"), staticRead("fonts/SansBold.ttf.z"),
    staticRead("fonts/Mono.ttf.z"), staticRead("fonts/MonoBold.ttf.z"),
    staticRead("fonts/Icons.ttf.z"), staticRead("fonts/RetroSansHD.ttf.z"),
    staticRead("fonts/RetroSansHDBold.ttf.z"), staticRead("fonts/RetroSansArabicHD.ttf.z"),
    (when defined(retroNoKawkab): "" else: staticRead("fonts/KawkabMono.ttf.z")),
    (when defined(retroNoKawkab): "" else: staticRead("fonts/KawkabMonoBold.ttf.z")),
    (when defined(retroNoW98): "" else: staticRead("fonts/MSW98UI.ttf.z")),
    (when defined(retroNoW98): "" else: staticRead("fonts/MSW98UIBold.ttf.z")),
    (when defined(retroNoW98): "" else: staticRead("fonts/MSW98UIHD.ttf.z")),
    (when defined(retroNoW98): "" else: staticRead("fonts/MSW98UIHDBold.ttf.z")), "", ""]
    ## (MS W98 UI has no licence: see fonts/NOTICE-MSW98UI.txt; -d:retroNoW98
    ## leaves it out, Retro Sans standing in. -d:retroNoKawkab leaves Kawkab
    ## Mono out, DejaVu Sans Mono standing in: for the smallest programs)
  IconCell = 1.25'f32        ## icons sit centered in cells this many ems wide
  TabStops = 4               ## a tab is this many spaces wide

var
  fontFiles: array[FaceId, string]          # unpacked, kept for the app's life
  faces: array[FaceId, Face]
  asciiAdv: array[FaceId, array[128, float32]]
  asciiKern: array[FaceId, seq[float32]]   ## 96 x 96 pairs of 32..127, in ems
  runCache, rtlCache: array[FaceId, Table[string, Run]]
  grids: array[FaceId, int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, -1, 0, 0, -1, -1]
    ## a pixel font's pixels per em (0: not one; -1: not known yet)

var unpackLock: Lock
initLock(unpackLock)

proc unpack(id: FaceId) =
  if id in {fUser, fUserBold} and fontFiles[id].len == 0:
    # (no font from a file yet: DejaVu stands in)
    unpack(if id == fUser: fSans else: fBold)
    fontFiles[id] = fontFiles[if id == fUser: fSans else: fBold]
    return
  if id in {fW98, fW98Bold, fW98HD, fW98HDBold} and fontPacked[id].len == 0 and fontFiles[id].len == 0:
    # (built without MS W98 UI: Retro Sans stands in)
    let r = if id in {fW98, fW98HD}: fRetro else: fRetroBold
    unpack(r)
    fontFiles[id] = fontFiles[r]
    return
  if id in {fKawkab, fKawkabBold} and fontPacked[id].len == 0 and fontFiles[id].len == 0:
    # (built without Kawkab Mono: DejaVu Sans Mono stands in)
    let r = if id == fKawkab: fMono else: fMonoBold
    unpack(r)
    fontFiles[id] = fontFiles[r]
    return
  if fontFiles[id].len == 0:
    let b = zlibDecompress(fontPacked[id].toOpenArrayByte(0, fontPacked[id].high))
    var s = newString(b.len)
    if b.len > 0: copyMem(addr s[0], unsafeAddr b[0], b.len)
    fontFiles[id] = move s

proc faceBytes*(id: FaceId): string =
  ## The font file of face `id`, a copy: for a worker thread to parse a face
  ## of its own (faces are not shared between threads).
  {.cast(gcsafe).}:
    withLock unpackLock:
      unpack(id)
      result = fontFiles[id]

proc face*(id: FaceId): Face =
  ## The parsed face `id` (parsed on first use).
  if faces[id] == nil:
    withLock unpackLock: unpack(id)
    faces[id] = parseFace(fontFiles[id])
    let f = faces[id]
    let em = float32(f.unitsPerEm)
    for c in 32 .. 126:
      asciiAdv[id][c] = float32(f.advance(f.glyphOf(c))) / em
    asciiAdv[id][9] = asciiAdv[id][32] * TabStops
    asciiKern[id] = newSeq[float32](96 * 96)
    for a in 32 .. 126:
      let ga = f.glyphOf(a)
      for b in 32 .. 126:
        let k = f.kerning(ga, f.glyphOf(b))
        if k != 0: asciiKern[id][(a - 32) * 96 + b - 32] = float32(k) / em
  faces[id]

proc isRetro*(id: FaceId): bool {.inline.} = id in {fRetro, fRetroBold, fRetroAr}
  ## A face of Retro Sans.

proc isKawkab*(id: FaceId): bool {.inline.} = id in {fKawkab, fKawkabBold}
  ## A face of Kawkab Mono.

proc isUser*(id: FaceId): bool {.inline.} = id in {fUser, fUserBold}
  ## A face of the font from a file.

proc isW98*(id: FaceId): bool {.inline.} = id in {fW98, fW98Bold}
  ## A face of MS W98 UI.

proc isW98HD*(id: FaceId): bool {.inline.} = id in {fW98HD, fW98HDBold}
  ## A face of MS W98 UI HD (its smoothed outlines).

proc hasW98*(): bool = not defined(retroNoW98)
  ## MS W98 UI is built in (not left out with -d:retroNoW98).

proc setUserFont*(regular: string; bold = "") =
  ## The font from a file (TrueType bytes; `bold` its bold, when it has
  ## one): the faces `fUser` and `fUserBold`. Raises `FontError` when it
  ## is not a TrueType font we read.
  let f = parseFace(regular)
  if f == nil or f.unitsPerEm <= 0 or f.glyphOf(ord('A')) == 0: raise newException(FontError, "not a font we read")
  if bold.len > 0:
    let b = parseFace(bold)
    if b == nil or b.unitsPerEm <= 0: raise newException(FontError, "the bold is not a font we read")
  fontFiles[fUser] = regular
  fontFiles[fUserBold] = if bold.len > 0: bold else: regular
  for id in [fUser, fUserBold]:
    faces[id] = nil
    grids[id] = -1
  for id in FaceId:
    runCache[id].clear()
    rtlCache[id].clear()

proc hasUserFont*(): bool = fontFiles[fUser].len > 0 and fontFiles[fUser] != fontFiles[fSans]
  ## A font from a file was given (`setUserFont`).

proc pixelGrid*(id: FaceId): int =
  ## A pixel font's pixels per em: its letters are drawn on a grid (the
  ## bitmap fonts of old, made outlines), so at that size -- or twice,
  ## three times it -- every edge falls on a pixel; 0 when it is not one.
  if not (isUser(id) or isW98(id)): return 0
  if grids[id] >= 0 and faces[id] != nil: return grids[id]
  let f = face(id)
  let em = f.unitsPerEm.float
  # (the advances of the letters and digits: on a grid of some size?)
  var vals: seq[float]
  for c in "AaBbCcHhMmNnOoWwXxIil0123456789.,:;!?-":
    let g = f.glyphOf(ord(c))
    if g != 0: vals.add f.advance(g).float
  result = 0
  if vals.len >= 20:
    for n in 6 .. 40:
      let step = em / n.float
      var off = 0
      for v in vals:
        let k = v / step
        if abs(k - round(k)) > 0.04: inc off
      if off == 0:
        result = n
        break
  grids[id] = result

proc lineFactor*(id: FaceId): float32 =
  ## Height of a line of face `id`, in ems (ascent + descent; a font from
  ## a file: with its line gap).
  let f = face(id)
  let gap = if isUser(id) or isW98(id) or isW98HD(id): max(0, f.lineGap) else: 0
  float32(f.ascent - f.descent + gap) / float32(f.unitsPerEm)

proc ascentFactor*(id: FaceId): float32 =
  ## Height of face `id` above the baseline, in ems (a font from a file:
  ## with half its line gap).
  let f = face(id)
  let gap = if isUser(id) or isW98(id) or isW98HD(id): max(0, f.lineGap) else: 0
  float32(f.ascent + gap div 2) / float32(f.unitsPerEm)

proc lineFactor*(retro = false): float32 =
  ## Height of a line of DejaVu (or Retro Sans), in ems (ascent + descent).
  lineFactor(if retro: fRetro else: fSans)

proc ascentFactor*(retro = false): float32 =
  ## Height of DejaVu (or Retro Sans) above the baseline, in ems.
  ascentFactor(if retro: fRetro else: fSans)

proc advanceFactor*(id: FaceId): float32 =
  ## A monospaced face's advance, in ems (0: not monospaced).
  let f = face(id)
  let g = f.glyphOf(ord('0'))
  if g == 0: return 0
  let a = f.advance(g)
  if a == f.advance(f.glyphOf(ord('i'))) and a == f.advance(f.glyphOf(ord('M'))):
    float32(a) / float32(f.unitsPerEm)
  else: 0

# ---- character classes ----------------------------------------------------------------

proc isMark*(cp: int): bool =
  ## A combining mark (drawn over or under the letter before it).
  case cp
  of 0x0300..0x036F, 0x0483..0x0489, 0x0591..0x05BD, 0x05BF, 0x05C1, 0x05C2,
     0x05C4, 0x05C5, 0x05C7, 0x0610..0x061A, 0x064B..0x065F, 0x0670,
     0x06D6..0x06DC, 0x06DF..0x06E4, 0x06E7, 0x06E8, 0x06EA..0x06ED,
     0x1AB0..0x1AFF, 0x1DC0..0x1DFF, 0x20D0..0x20FF, 0xFE00..0xFE0F,
     0xFE20..0xFE2F: true
  else: false

proc isInvisible(cp: int): bool =
  cp < 32 and cp != 9 or cp in 0x200B..0x200F or cp in 0x202A..0x202E or
    cp in 0x2060..0x2064 or cp == 0xFEFF or cp == 0x061C

type BidiClass = enum
  bL, bR, bAL, bEN, bAN, bES, bET, bCS, bNSM, bWS, bON

proc bidiClass(cp: int): BidiClass =
  if cp in 0x30..0x39 or cp in 0x06F0..0x06F9 or cp in [0xB2, 0xB3, 0xB9]: bEN
  elif cp in 0x0660..0x0669 or cp == 0x066B or cp == 0x066C: bAN
  elif cp in [ord('+'), ord('-'), 0x2212]: bES
  elif cp in [ord('#'), ord('$'), ord('%'), 0xB0, 0xB1, 0x066A] or
       cp in 0xA2..0xA5 or cp in 0x2030..0x2034 or cp in 0x20A0..0x20CF: bET
  elif cp in [ord(','), ord('.'), ord(':'), ord('/'), 0xA0, 0x060C]: bCS
  elif cp == 9 or cp == 32 or cp in 0x2000..0x200A: bWS
  elif cp == 0x200F: bR                  # the right-to-left mark
  elif cp == 0x061C: bAL                 # the Arabic letter mark
  elif isMark(cp): bNSM
  elif cp in 0x0590..0x05FF or cp in 0x07C0..0x085F or cp in 0xFB1D..0xFB4F: bR
  elif cp in 0x0600..0x06FF or cp in 0x0750..0x077F or cp in 0x08A0..0x08FF or
       cp in 0xFB50..0xFDFF or cp in 0xFE70..0xFEFF: bAL
  elif cp in 0x21..0x2F or cp in 0x3A..0x40 or cp in 0x5B..0x60 or
       cp in 0x7B..0x7E or cp in 0xA1..0xBF or cp == 0xD7 or cp == 0xF7 or
       cp in 0x2010..0x2027 or cp in 0x2035..0x205E or cp in 0x2100..0x2BFF: bON
  else: bL

proc isRtlChar(cp: int): bool {.inline.} = bidiClass(cp) in {bR, bAL}

var rtlInterface = false   # (`setRtlInterface`)
var visualCache: Table[string, seq[tuple[cp: int; rtl: bool]]]

proc textIsRtl*(s: string): bool =
  ## Whether `s` reads right to left: its first letter is Arabic or Hebrew.
  for r in s.runes:
    case bidiClass(int(r))
    of bL: return false
    of bR, bAL: return true
    else: discard
  false

proc strongDir*(s: string): int =
  ## The direction of `s` from its first strong character: 0 left to
  ## right, 1 right to left, 2 a number, -1 none (punctuation, spaces).
  for r in s.runes:
    case bidiClass(int(r))
    of bL: return 0
    of bR, bAL: return 1
    of bEN, bAN: return 2
    else: discard
  -1

proc mirror(cp: int): int =
  case cp
  of ord('('): ord(')')
  of ord(')'): ord('(')
  of ord('['): ord(']')
  of ord(']'): ord('[')
  of ord('{'): ord('}')
  of ord('}'): ord('{')
  of ord('<'): ord('>')
  of ord('>'): ord('<')
  of 0xAB: 0xBB
  of 0xBB: 0xAB
  of 0x2039: 0x203A
  of 0x203A: 0x2039
  else: cp

# ---- Arabic joining ---------------------------------------------------------------------

var formsOf: Table[int, array[4, uint16]]
var lamAlefOf: Table[int, (uint16, uint16)]

proc initArabic() =
  if formsOf.len > 0: return
  for (k, v) in arabicForms: formsOf[int(k)] = v
  for (k, iso, fin) in lamAlef: lamAlefOf[int(k)] = (iso, fin)

type Joining = enum jNone, jRight, jDual, jTransparent

proc joining(cp: int): Joining =
  if isMark(cp): return jTransparent
  if cp == 0x0640 or cp == 0x200D: return jDual
  let v = formsOf.getOrDefault(cp, [0'u16, 0, 0, 0])
  if v[2] != 0 or v[3] != 0: jDual
  elif v[1] != 0: jRight
  else: jNone

proc shapeArabic(cps: var seq[int]) =
  ## Replaces the Arabic letters of `cps` (logical order) by their joined
  ## presentation forms; a letter swallowed by a ligature becomes -1.
  initArabic()
  let n = cps.len
  var jt = newSeq[Joining](n)
  for i in 0 ..< n: jt[i] = joining(cps[i])
  var outp = cps
  for i in 0 ..< n:
    if jt[i] notin {jRight, jDual} or cps[i] < 0: continue
    var p = i - 1
    while p >= 0 and (jt[p] == jTransparent or cps[p] < 0): dec p
    var q = i + 1
    while q < n and jt[q] == jTransparent: inc q
    if q >= n: q = -1
    let joinsPrev = p >= 0 and jt[p] == jDual
    var joinsNext = q >= 0 and jt[i] == jDual and jt[q] in {jRight, jDual}
    if cps[i] == 0x0644 and q >= 0 and lamAlefOf.hasKey(cps[q]):
      let (iso, fin) = lamAlefOf[cps[q]]
      outp[i] = int(if joinsPrev: fin else: iso)
      outp[q] = -1
      cps[q] = -1
      jt[q] = jNone
      continue
    # (tatweel and the zero width joiner join, but have no forms of their own)
    let v = formsOf.getOrDefault(cps[i], [0'u16, 0, 0, 0])
    let slot = if joinsPrev and joinsNext: 3
               elif joinsPrev: 1
               elif joinsNext: 2
               else: 0
    var f = int(v[slot])
    if f == 0 and slot == 3: f = int(v[1])      # no medial: use final
    if f == 0 and slot == 2: f = int(v[0])
    if f == 0: f = int(v[0])
    if f != 0 and (face(fSans).hasGlyph(f) or face(fRetroAr).hasGlyph(f) or face(fKawkab).hasGlyph(f)):
      outp[i] = f
  cps = outp

# ---- bidi -----------------------------------------------------------------------------------

proc bidiLevels(cps: seq[int]; rtlPara: bool): seq[int8] =
  ## Embedding levels of a single line (UAX #9 without explicit embeddings).
  let n = cps.len
  var t = newSeq[BidiClass](n)
  for i in 0 ..< n: t[i] = if cps[i] < 0: bNSM else: bidiClass(cps[i])
  let para = if rtlPara: bR else: bL
  # W1: marks take the class before them
  var prev = para
  for i in 0 ..< n:
    if t[i] == bNSM: t[i] = prev
    else: prev = t[i]
  # W2, W3: numbers after Arabic letters are Arabic numbers
  var strong = para
  for i in 0 ..< n:
    case t[i]
    of bL, bR, bAL: strong = t[i]
    of bEN:
      if strong == bAL: t[i] = bAN
    else: discard
  for i in 0 ..< n:
    if t[i] == bAL: t[i] = bR
  # W4: one separator between two numbers of the same kind joins them
  for i in 1 ..< n - 1:
    if t[i] == bES and t[i-1] == bEN and t[i+1] == bEN: t[i] = bEN
    elif t[i] == bCS and t[i-1] == t[i+1] and t[i-1] in {bEN, bAN}: t[i] = t[i-1]
  # W5: terminators next to European numbers ("50%", "$3")
  var i = 0
  while i < n:
    if t[i] == bET:
      var j = i
      while j < n and t[j] == bET: inc j
      if (i > 0 and t[i-1] == bEN) or (j < n and t[j] == bEN):
        for k in i ..< j: t[k] = bEN
      i = j
    else: inc i
  # W6: the other separators are neutral
  for k in 0 ..< n:
    if t[k] in {bES, bET, bCS}: t[k] = bON
  # W7: European numbers after Latin text are Latin
  strong = para
  for k in 0 ..< n:
    case t[k]
    of bL, bR: strong = t[k]
    of bEN:
      if strong == bL: t[k] = bL
    else: discard
  proc dirOf(c: BidiClass): BidiClass =
    if c in {bR, bEN, bAN}: bR else: bL
  # N0: a pair of brackets takes the direction of what it encloses
  var stack: seq[(int, int)]
  var pairs: seq[(int, int)]
  for k in 0 ..< n:
    let c = cps[k]
    if c in [ord('('), ord('['), ord('{')] and stack.len < 63:
      stack.add (k, c)
    elif c in [ord(')'), ord(']'), ord('}')]:
      let want = if c == ord(')'): ord('(') elif c == ord(']'): ord('[') else: ord('{')
      var s = stack.high
      while s >= 0 and stack[s][1] != want: dec s
      if s >= 0:
        pairs.add (stack[s][0], k)
        stack.setLen(s)
  for (a, b) in pairs:
    var same, other = false
    for k in a + 1 ..< b:
      if t[k] in {bL, bR, bEN, bAN}:
        if dirOf(t[k]) == para: same = true else: other = true
    var d = bON
    if same: d = para
    elif other:
      var before = para
      var k = a - 1
      while k >= 0:
        if t[k] in {bL, bR, bEN, bAN}:
          before = dirOf(t[k])
          break
        dec k
      d = if before != para: before else: para
    if d != bON:
      t[a] = d
      t[b] = d
  # N1, N2: neutrals between two of the same direction take it
  i = 0
  while i < n:
    if t[i] in {bON, bWS}:
      var j = i
      while j < n and t[j] in {bON, bWS}: inc j
      let before = if i == 0: para else: dirOf(t[i-1])
      let after = if j >= n: para else: dirOf(t[j])
      let d = if before == after: before else: para
      for k in i ..< j: t[k] = d
      i = j
    else: inc i
  # I1, I2
  result = newSeq[int8](n)
  let base = if rtlPara: 1'i8 else: 0'i8
  for k in 0 ..< n:
    result[k] =
      if base == 0:
        (case t[k]
         of bR: 1'i8
         of bEN, bAN: 2'i8
         else: 0'i8)
      else:
        (case t[k]
         of bL, bEN, bAN: 2'i8
         else: 1'i8)
  # L1: trailing white space goes back to the paragraph level
  var k = n - 1
  while k >= 0 and (cps[k] == 32 or cps[k] == 9):
    result[k] = base
    dec k

proc visualOrder(levels: seq[int8]): seq[int] =
  ## L2: reverse every run at each level from the highest down to 1.
  let n = levels.len
  result = newSeq[int](n)
  for i in 0 ..< n: result[i] = i
  var hi = 0'i8
  for l in levels: hi = max(hi, l)
  var lvl = hi
  while lvl >= 1:
    var i = 0
    while i < n:
      if levels[result[i]] >= lvl:
        var j = i
        while j < n and levels[result[j]] >= lvl: inc j
        var a = i
        var b = j - 1
        while a < b:
          swap(result[a], result[b])
          inc a
          dec b
        i = j
      else: inc i
    dec lvl

# ---- for laying out styled text -----------------------------------------------------------------

proc bidiInfo*(s: string; rtl = -1): tuple[cps: seq[int]; levels: seq[int8]; rtlPara: bool] =
  ## The characters of `s` (one paragraph, by rune) ready to lay out with
  ## styles: Arabic letters in their joined forms (-1 for a character
  ## joined into another, or invisible), and each one's bidirectional level
  ## (odd: right to left; empty when all is left to right). Show a line's
  ## characters in `visualOrderOf(levels[line])`, mirrored (`mirrored`)
  ## where the level is odd.
  for r in s.runes: result.cps.add int(r)
  var arabic = false
  var anyRtl = false
  for c in result.cps:
    if c in 0x0600..0x06FF or c in 0x0750..0x077F: arabic = true
    if isRtlChar(c): anyRtl = true
  if arabic: shapeArabic(result.cps)
  result.rtlPara = if rtl >= 0: rtl == 1 else: textIsRtl(s)
  if anyRtl or result.rtlPara:
    result.levels = bidiLevels(result.cps, result.rtlPara)
  for c in result.cps.mitems:
    if c >= 0 and isInvisible(c): c = -1

proc visualOrderOf*(levels: openArray[int8]): seq[int] =
  ## The order to show characters with these bidi levels in (their indexes).
  if levels.len == 0: return
  visualOrder(@levels)

proc mirrored*(cp: int): int = mirror(cp)
  ## The mirror image of a bracket (shown in a right-to-left run).

# ---- for bitmap fonts -------------------------------------------------------------------------

proc visualCodepoints*(s: string): seq[tuple[cp: int; rtl: bool]] =
  ## The characters of `s` (one line) in the order they are shown, Arabic
  ## letters in their joined forms, brackets mirrored in right-to-left runs,
  ## invisible controls left out -- for drawing with a bitmap font. `rtl`:
  ## the character is in a right-to-left run (its marks come before it).
  visualCache.withValue(s, v):
    return v[]
  var cps: seq[int]
  for r in s.runes: cps.add int(r)
  var arabic = false
  var anyRtl = false
  for c in cps:
    if c in 0x0600..0x06FF or c in 0x0750..0x077F: arabic = true
    if isRtlChar(c): anyRtl = true
  if arabic: shapeArabic(cps)
  let rtlPara = textIsRtl(s) or (rtlInterface and anyRtl)
  var levels: seq[int8]
  var order: seq[int]
  if anyRtl or rtlPara:
    levels = bidiLevels(cps, rtlPara)
    order = visualOrder(levels)
  else:
    order = newSeq[int](cps.len)
    for i in 0 ..< cps.len: order[i] = i
  for li in order:
    var cp = cps[li]
    if cp < 0 or isInvisible(cp): continue
    let odd = levels.len > 0 and (levels[li] and 1) == 1
    if odd: cp = mirror(cp)
    result.add (cp, odd)
  if visualCache.len > 2000: visualCache.clear()
  visualCache[s] = result

# ---- runs ---------------------------------------------------------------------------------

proc fallbacks(base: FaceId): array[4, FaceId] =
  case base
  of fSans: [fSans, fIcons, fSans, fSans]
  of fBold: [fBold, fSans, fIcons, fBold]
  of fMono: [fMono, fSans, fIcons, fMono]
  of fMonoBold: [fMonoBold, fBold, fIcons, fMonoBold]
  of fIcons: [fIcons, fSans, fIcons, fIcons]
  of fRetro: [fRetro, fRetroAr, fSans, fIcons]
  of fRetroBold: [fRetroBold, fRetroAr, fBold, fIcons]
  of fRetroAr: [fRetroAr, fRetro, fSans, fIcons]
  of fKawkab: [fKawkab, fSans, fIcons, fKawkab]
  of fKawkabBold: [fKawkabBold, fBold, fIcons, fKawkabBold]
  of fW98: [fW98, fRetroAr, fSans, fIcons]
  of fW98Bold: [fW98Bold, fW98, fRetroAr, fBold]
  of fW98HD: [fW98HD, fRetroAr, fSans, fIcons]
  of fW98HDBold: [fW98HDBold, fW98HD, fRetroAr, fBold]
  of fUser: [fUser, fRetroAr, fSans, fIcons]
  of fUserBold: [fUserBold, fUser, fRetroAr, fBold]

proc pick(base: FaceId; cp: int): (FaceId, int) =
  if (cp in 0xE000 .. 0xF8FF or cp in 0xF0000 .. 0xFFFFD) and base != fIcons:
    # (the private use area is the icons': a font's own glyphs there -- MS
    # W98 UI has a few -- do not stand in for them)
    let g = face(fIcons).glyphOf(cp)
    if g != 0: return (fIcons, g)
  for id in fallbacks(base):
    let g = face(id).glyphOf(cp)
    if g != 0: return (id, g)
  (base, 0)

proc isAscii(s: string): bool =
  for c in s:
    if ord(c) < 32 or ord(c) > 126: return false
  true

proc em(id: FaceId): float32 {.inline.} = float32(face(id).unitsPerEm)

proc asciiWidth(s: string; base: FaceId): float32 =
  discard face(base)
  let kern = addr asciiKern[base]
  var prev = -1
  for c in s:
    let k = ord(c) - 32
    result += asciiAdv[base][ord(c)]
    if prev >= 0: result += kern[][prev * 96 + k]
    prev = k

proc build(s: string; base: FaceId; rtl: int): Run =
  ## `rtl`: -1 from the text, 0 left to right, 1 right to left.
  var cps: seq[int]
  for r in s.runes: cps.add int(r)
  var arabic = false
  var anyRtl = false
  for c in cps:
    if c in 0x0600..0x06FF or c in 0x0750..0x077F: arabic = true
    if isRtlChar(c): anyRtl = true
  if arabic: shapeArabic(cps)
  result.rtl = if rtl >= 0: rtl == 1 else: textIsRtl(s) or (rtlInterface and anyRtl)
  var order: seq[int]
  var levels: seq[int8]
  if anyRtl or result.rtl:
    levels = bidiLevels(cps, result.rtl)
    order = visualOrder(levels)
  else:
    order = newSeq[int](cps.len)
    for i in 0 ..< cps.len: order[i] = i
  # glyphs in visual order
  var at = newSeq[int](cps.len)          # logical index -> glyph index
  for i in 0 ..< at.len: at[i] = -1
  var x = 0'f32
  var prevFace = fIcons
  var prevGid = 0
  for li in order:
    var cp = cps[li]
    if cp < 0 or isInvisible(cp): continue
    if levels.len > 0 and (levels[li] and 1) == 1: cp = mirror(cp)
    if cp == 9:
      let (fid, g) = pick(base, 32)
      result.glyphs.add PGlyph(face: fid, gid: uint16(g), x: x)
      x += asciiAdv[fid][32] * TabStops
      prevGid = 0
      continue
    var (fid, g) = pick(base, cp)
    if g == 0:
      result.missing = true
      (fid, g) = (base, 0)
    let f = face(fid)
    var adv = float32(f.advance(g)) / em(fid)
    var gx = x
    if fid == fIcons:
      gx += (IconCell - adv) / 2
      adv = IconCell
    elif fid == prevFace and prevGid != 0:
      let k = float32(f.kerning(prevGid, g)) / em(fid)
      gx += k
      x += k
    at[li] = result.glyphs.len
    result.glyphs.add PGlyph(face: fid, gid: uint16(g), x: gx)
    x += adv
    if not isMark(cp):
      prevFace = fid
      prevGid = g
  result.width = x
  # marks without a positioning table: centered on their letter, and
  # lifted (or lowered) clear of it
  for li in 0 ..< cps.len:
    if cps[li] < 0 or not isMark(cps[li]) or at[li] < 0: continue
    var b = li - 1
    while b >= 0 and (cps[b] < 0 or isMark(cps[b])): dec b
    if b < 0 or at[b] < 0: continue
    let mg = addr result.glyphs[at[li]]
    let bg = result.glyphs[at[b]]
    let mf = face(mg.face)
    let bf = face(bg.face)
    let m = mf.bounds(int(mg.gid))
    let bb = bf.bounds(int(bg.gid))
    if m.x1 <= m.x0: continue
    let units = em(mg.face)
    mg.x = bg.x + (float32(bb.x0 + bb.x1) - float32(m.x0 + m.x1)) / 2 / units
    let gap = 0.06'f32 * units
    if m.y0 > 0:                          # above
      let lift = float32(bb.y1) + gap - float32(m.y0)
      if lift > 0: mg.y = lift / units
    elif m.y1 < 0:                        # below
      let drop = float32(m.y1) - (float32(bb.y0) - gap)
      if drop > 0: mg.y = -drop / units

proc setRtlInterface*(on: bool) =
  ## A right-to-left interface (Arabic, `setUiLanguage`): a line that mixes
  ## right-to-left letters with others reads right to left ("1.0 GB متاحة
  ## من 252 GB" in its order), as the interface does; a line without them
  ## (a file's name) keeps the direction of its first letter. Off: every
  ## line follows its first letter.
  if on == rtlInterface: return
  rtlInterface = on
  visualCache.clear()
  for id in FaceId:
    runCache[id].clear()
    rtlCache[id].clear()

proc shape*(s: string; base = fSans; rtl = -1): Run =
  ## The glyphs of `s` (one line) in `base`'s style; `rtl` 1 makes it a
  ## right-to-left paragraph, 0 left-to-right, -1 (the default) follows
  ## its first letter. Cached: the same string costs a table lookup the
  ## next time.
  if rtl == 0:
    return build(s, base, rtl)
  let cache = if rtl == 1: addr rtlCache[base] else: addr runCache[base]
  if cache[].len > 4000: cache[].clear()
  cache[].withValue(s, r):
    return r[]
  result = build(s, base, rtl)
  cache[][s] = result

proc widthEm*(s: string; base = fSans; rtl = -1): float32 =
  ## Width of `s` in ems.
  if s.len == 0: return 0
  discard face(base)
  if isAscii(s) and rtl != 1: asciiWidth(s, base)
  else: shape(s, base, rtl).width

iterator asciiGlyphs*(s: openArray[char]; base: FaceId): PGlyph =
  ## The glyphs of a plain ASCII string, without building a run.
  let f = face(base)
  let kern = addr asciiKern[base]
  var x = 0'f32
  var prev = -1
  for c in s:
    let k = ord(c) - 32
    if prev >= 0: x += kern[][prev * 96 + k]
    yield PGlyph(face: base, gid: uint16(f.glyphOf(ord(c))), x: x)
    x += asciiAdv[base][ord(c)]
    prev = k

proc plainAscii*(s: openArray[char]): bool =
  ## Every character of `s` is printable ASCII (no control characters).
  for c in s:
    if ord(c) < 32 or ord(c) > 126: return false
  true

proc hasGlyphs*(s: string; base = fSans): bool =
  ## Whether the built-in faces draw every character of `s`.
  if isAscii(s): true else: not shape(s, base).missing

proc fontData*(id: FaceId): lent string =
  ## The bytes of the built-in TrueType file of face `id` (DejaVu Sans,
  ## Sans Bold, Sans Mono, Sans Mono Bold, the icons) -- for code that
  ## embeds the glyphs elsewhere (`retro/pdf` puts their outlines into PDF
  ## files). The same bytes the screen uses: nothing is copied.
  unpack(id)
  fontFiles[id]
