## QR codes made here, nothing to install: any text (UTF-8) to the dark and
## light modules of a QR code (ISO/IEC 18004, versions 1 to 40, error
## correction L, M, Q, H), drawn as a picture or as outlines for a vector
## shape layer.
##
## ```nim
## let q = qrEncode("WIFI:T:WPA;S:Hotel;P:secret;;", qrQ)
## echo q.version, " ", q.size, " x ", q.size, " mask ", q.mask
## let b = qrBitmap(q, scale = 8)                  # 4 modules of quiet zone around it
## for poly in qrPath(q): discard poly             # closed outlines, in modules
## ```
##
## The text is written in one segment: numeric when it is all digits,
## alphanumeric when it is all `0-9 A-Z space $ % * + - . / :`, else bytes
## (its UTF-8, without an ECI header: what phones read). The smallest
## version that holds it (from `minVersion`; `qrFits` tells) is taken, and
## the mask with the lowest penalty (ISO 18004:2015 7.8.3, judged before
## the format information is written, as segno judges it) unless one is
## given. The modules equal segno's and python-qrcode's for the same
## version and mask.

import gfx

type
  QrEcc* = enum
    ## How much of the code may be lost and still read: about 7 %, 15 %,
    ## 25 %, 30 %.
    qrL, qrM, qrQ, qrH
  QrMode* = enum
    ## How the text is written.
    qmNumeric, qmAlphanumeric, qmByte
  QrCode* = object
    ## A QR code: `size` x `size` modules, `q[x, y]` dark or light.
    version*: int          ## 1..40
    ecc*: QrEcc
    mask*: int             ## 0..7
    mode*: QrMode
    size*: int             ## modules a side: 17 + 4 * version
    dark: seq[bool]

const
  # error correction codewords per block, and blocks, by level and version (index 0 unused)
  eccPerBlock: array[QrEcc, array[41, int8]] = [
    [-1'i8, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28,
     28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    [-1'i8, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
     26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
    [-1'i8, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30,
     28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    [-1'i8, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28,
     30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]]
  eccBlocks: array[QrEcc, array[41, int8]] = [
    [-1'i8, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8,
     8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
    [-1'i8, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16,
     17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
    [-1'i8, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20,
     23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
    [-1'i8, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25,
     25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81]]
  eccFormatBits: array[QrEcc, int] = [1, 0, 3, 2]
  alnumChars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"

proc `[]`*(q: QrCode; x, y: int): bool {.inline.} =
  ## The module in column `x`, row `y` is dark (outside the code: light).
  x >= 0 and y >= 0 and x < q.size and y < q.size and q.dark[y * q.size + x]

# ---- the bits ------------------------------------------------------------------------------------

type Bits = object
  b: seq[bool]

proc add(s: var Bits; v, n: int) =
  for i in countdown(n - 1, 0): s.b.add ((v shr i) and 1) != 0

proc rawModules(ver: int): int =
  ## Modules left for data and error correction (with the remainder bits).
  result = (16 * ver + 128) * ver + 64
  if ver >= 2:
    let na = ver div 7 + 2
    result -= (25 * na - 10) * na - 55
    if ver >= 7: result -= 36

proc dataCodewords(ver: int; ecc: QrEcc): int =
  rawModules(ver) div 8 - int(eccPerBlock[ecc][ver]) * int(eccBlocks[ecc][ver])

proc countBits(mode: QrMode; ver: int): int =
  let k = if ver <= 9: 0 elif ver <= 26: 1 else: 2
  case mode
  of qmNumeric: [10, 12, 14][k]
  of qmAlphanumeric: [9, 11, 13][k]
  of qmByte: [8, 16, 16][k]

proc modeOf(text: string): QrMode =
  if text.len == 0: return qmByte
  var num, alnum = true
  for c in text:
    if c notin {'0'..'9'}: num = false
    if alnumChars.find(c) < 0: alnum = false
  if num: qmNumeric elif alnum: qmAlphanumeric else: qmByte

proc dataBits(text: string; mode: QrMode): Bits =
  case mode
  of qmNumeric:
    var i = 0
    while i < text.len:
      let n = min(3, text.len - i)
      var v = 0
      for k in 0 ..< n: v = v * 10 + (ord(text[i + k]) - ord('0'))
      result.add v, n * 3 + 1
      i += n
  of qmAlphanumeric:
    var i = 0
    while i + 1 < text.len:
      result.add alnumChars.find(text[i]) * 45 + alnumChars.find(text[i + 1]), 11
      i += 2
    if i < text.len: result.add alnumChars.find(text[i]), 6
  of qmByte:
    for c in text: result.add ord(c), 8

# ---- Reed-Solomon over GF(256), x^8 + x^4 + x^3 + x^2 + 1 --------------------------------------------

proc gfMul(x, y: int): int =
  var z = 0
  for i in countdown(7, 0):
    z = (z shl 1) xor ((z shr 7) * 0x11D)
    z = z xor (((y shr i) and 1) * x)
  z

proc rsDivisor(degree: int): seq[int] =
  result = newSeq[int](degree)
  result[degree - 1] = 1
  var root = 1
  for i in 0 ..< degree:
    for j in 0 ..< degree:
      result[j] = gfMul(result[j], root)
      if j + 1 < degree: result[j] = result[j] xor result[j + 1]
    root = gfMul(root, 2)

proc rsRemainder(data: openArray[int]; divisor: seq[int]): seq[int] =
  result = newSeq[int](divisor.len)
  for b in data:
    let factor = b xor result[0]
    for i in 0 ..< result.len - 1: result[i] = result[i + 1]
    result[^1] = 0
    for i in 0 ..< result.len: result[i] = result[i] xor gfMul(divisor[i], factor)

proc interleaved(data: seq[int]; ver: int; ecc: QrEcc): seq[int] =
  ## The data codewords in their blocks, each with its error correction,
  ## then interleaved.
  let nb = int(eccBlocks[ecc][ver])
  let el = int(eccPerBlock[ecc][ver])
  let raw = rawModules(ver) div 8
  let numShort = nb - raw mod nb
  let shortLen = raw div nb
  let divisor = rsDivisor(el)
  var blocks: seq[seq[int]]
  var k = 0
  for i in 0 ..< nb:
    let dl = shortLen - el + (if i < numShort: 0 else: 1)
    var blk = data[k ..< k + dl]
    k += dl
    let e = rsRemainder(blk, divisor)
    if i < numShort: blk.add 0                 # (a place kept, skipped below)
    blk.add e
    blocks.add blk
  for i in 0 ..< blocks[0].len:
    for j in 0 ..< nb:
      if i != shortLen - el or j >= numShort: result.add blocks[j][i]

# ---- the symbol -------------------------------------------------------------------------------------

type Grid = object
  n: int
  m, fn: seq[bool]           # dark; part of a function pattern

proc put(g: var Grid; x, y: int; dark: bool) =
  g.m[y * g.n + x] = dark
  g.fn[y * g.n + x] = true

proc alignPositions(ver: int; size: int): seq[int] =
  if ver == 1: return
  let na = ver div 7 + 2
  let step = (ver * 8 + na * 3 + 5) div (na * 4 - 4) * 2
  result = newSeq[int](na)
  result[0] = 6
  var pos = size - 7
  for i in countdown(na - 1, 1):
    result[i] = pos
    pos -= step

proc formatBits(ecc: QrEcc; mask: int): int =
  let data = eccFormatBits[ecc] shl 3 or mask
  var rem = data
  for i in 0 ..< 10: rem = (rem shl 1) xor ((rem shr 9) * 0x537)
  (data shl 10 or rem) xor 0x5412

proc drawFormat(g: var Grid; bits: int) =
  ## The format information (-1: its places, light).
  template bit(i: int): bool = bits >= 0 and ((bits shr i) and 1) != 0
  for i in 0 .. 5: g.put(8, i, bit(i))
  g.put(8, 7, bit(6))
  g.put(8, 8, bit(7))
  g.put(7, 8, bit(8))
  for i in 9 .. 14: g.put(14 - i, 8, bit(i))
  for i in 0 .. 7: g.put(g.n - 1 - i, 8, bit(i))
  for i in 8 .. 14: g.put(8, g.n - 15 + i, bit(i))
  g.put(8, g.n - 8, bits >= 0)                 # the dark module (light while masks are judged)

proc drawVersion(g: var Grid; ver: int; blank: bool) =
  if ver < 7: return
  var rem = ver
  for i in 0 ..< 12: rem = (rem shl 1) xor ((rem shr 11) * 0x1F25)
  let bits = ver shl 12 or rem
  for i in 0 ..< 18:
    let b = not blank and ((bits shr i) and 1) != 0
    let a = g.n - 11 + i mod 3
    g.put(a, i div 3, b)
    g.put(i div 3, a, b)

proc functionPatterns(ver: int): Grid =
  let n = 17 + 4 * ver
  result = Grid(n: n, m: newSeq[bool](n * n), fn: newSeq[bool](n * n))
  for i in 0 ..< n:
    result.put(6, i, i mod 2 == 0)
    result.put(i, 6, i mod 2 == 0)
  for (cx, cy) in [(3, 3), (n - 4, 3), (3, n - 4)]:
    for dy in -4 .. 4:
      for dx in -4 .. 4:
        let x = cx + dx
        let y = cy + dy
        if x >= 0 and x < n and y >= 0 and y < n:
          let d = max(abs(dx), abs(dy))
          result.put(x, y, d != 2 and d != 4)
  let ap = alignPositions(ver, n)
  for i in 0 ..< ap.len:
    for j in 0 ..< ap.len:
      if (i == 0 and j == 0) or (i == 0 and j == ap.high) or (i == ap.high and j == 0): continue
      for dy in -2 .. 2:
        for dx in -2 .. 2:
          result.put(ap[i] + dx, ap[j] + dy, max(abs(dx), abs(dy)) != 1)
  # the format and version areas, and the dark module: light while the masks are judged
  result.drawFormat(-1)
  result.drawVersion(ver, blank = true)

proc placeCodewords(g: var Grid; cw: seq[int]) =
  let n = g.n
  var i = 0
  let total = cw.len * 8
  var right = n - 1
  while right >= 1:
    if right == 6: right = 5
    for vert in 0 ..< n:
      for j in 0 .. 1:
        let x = right - j
        let upward = ((right + 1) and 2) == 0
        let y = if upward: n - 1 - vert else: vert
        if not g.fn[y * n + x]:
          if i < total:
            g.m[y * n + x] = ((cw[i shr 3] shr (7 - (i and 7))) and 1) != 0
            inc i
          else: g.m[y * n + x] = false    # remainder bits
    right -= 2

proc maskBit(mask, x, y: int): bool {.inline.} =
  case mask
  of 0: (x + y) mod 2 == 0
  of 1: y mod 2 == 0
  of 2: x mod 3 == 0
  of 3: (x + y) mod 3 == 0
  of 4: (x div 3 + y div 2) mod 2 == 0
  of 5: x * y mod 2 + x * y mod 3 == 0
  of 6: (x * y mod 2 + x * y mod 3) mod 2 == 0
  else: ((x + y) mod 2 + x * y mod 3) mod 2 == 0

proc applyMask(g: var Grid; mask: int) =
  for y in 0 ..< g.n:
    for x in 0 ..< g.n:
      let i = y * g.n + x
      if not g.fn[i] and maskBit(mask, x, y): g.m[i] = not g.m[i]

proc findPattern(line: openArray[bool]; start: int): int =
  const pat = [true, false, true, true, true, false, true]
  var i = max(0, start)
  while i + 7 <= line.len:
    var ok = true
    for k in 0 ..< 7:
      if line[i + k] != pat[k]:
        ok = false
        break
    if ok: return i
    inc i
  -1

proc lightRange(line: openArray[bool]; a, b: int): bool =
  for k in max(a, 0) ..< min(b, line.len):
    if line[k]: return false
  true

proc n3Score(line: openArray[bool]): int =
  ## Finder-like 1:1:3:1:1 runs with 4 light modules before or after (or
  ## the symbol's edge), the way segno counts them.
  let n = line.len
  var idx = findPattern(line, 0)
  while idx != -1:
    var offset = idx + 7
    if idx == 0 or idx == n - 7 or lightRange(line, idx - 4, idx) or
       lightRange(line, offset, offset + 4):
      result += 40
    else:
      offset = idx + 4
    idx = findPattern(line, offset)

proc penalty(g: Grid): int =
  let n = g.n
  var dark = 0
  var col = newSeq[bool](n)
  var row = newSeq[bool](n)
  for i in 0 ..< n:
    var rowRun, colRun = 0
    for j in 0 ..< n:
      let r = g.m[i * n + j]
      let c = g.m[j * n + i]
      row[j] = r
      col[j] = c
      if r: inc dark
      if j > 0 and r == g.m[i * n + j - 1]: inc rowRun
      else:
        if rowRun >= 5: result += rowRun - 2
        rowRun = 1
      if j > 0 and c == g.m[(j - 1) * n + i]: inc colRun
      else:
        if colRun >= 5: result += colRun - 2
        colRun = 1
      if i > 0 and j > 0 and r == g.m[i * n + j - 1] and r == g.m[(i - 1) * n + j] and
         r == g.m[(i - 1) * n + j - 1]:
        result += 3
    if rowRun >= 5: result += rowRun - 2
    if colRun >= 5: result += colRun - 2
    result += n3Score(row) + n3Score(col)
  let percent = float(dark) / float(n * n)
  result += 10 * int(abs(percent * 100 - 50) / 5)

proc qrFits*(text: string; ec = qrM; version: int): bool =
  ## `text` fits in a QR code of `version` at `ec`.
  if version notin 1 .. 40: return false
  let mode = modeOf(text)
  let bits = dataBits(text, mode)
  let cb = countBits(mode, version)
  version in 1 .. 40 and text.len < (1 shl cb) and
    4 + cb + bits.b.len <= dataCodewords(version, ec) * 8

proc qrEncode*(text: string; ec = qrM; minVersion = 1; mask = -1): QrCode =
  ## The QR code of `text` (UTF-8): the smallest version from `minVersion`
  ## that holds it at the error correction `ec`; the best mask, or `mask`
  ## (0..7). Raises `ValueError` when it is too long for version 40 (2953
  ## bytes at L, 2331 at M, 1663 at Q, 1273 at H; more digits).
  if mask notin -1 .. 7: raise newException(ValueError, "QR mask must be -1..7")
  let mode = modeOf(text)
  let payload = dataBits(text, mode)
  var ver = max(1, minVersion)
  while ver <= 40:
    let cb = countBits(mode, ver)
    if text.len < (1 shl cb) and 4 + cb + payload.b.len <= dataCodewords(ver, ec) * 8: break
    inc ver
  if ver > 40: raise newException(ValueError, "the text is too long for a QR code")
  # the bit stream: mode, count, data, terminator, padding
  let capacity = dataCodewords(ver, ec) * 8
  var bs: Bits
  bs.add [1, 2, 4][ord(mode)], 4
  bs.add text.len, countBits(mode, ver)
  bs.b.add payload.b
  bs.add 0, min(4, capacity - bs.b.len)
  bs.add 0, (8 - bs.b.len mod 8) mod 8
  var data: seq[int]
  for i in countup(0, bs.b.len - 1, 8):
    var v = 0
    for k in 0 ..< 8: v = v shl 1 or ord(bs.b[i + k])
    data.add v
  var pad = 0xEC
  while data.len < capacity div 8:
    data.add pad
    pad = pad xor (0xEC xor 0x11)
  var g = functionPatterns(ver)
  g.placeCodewords(interleaved(data, ver, ec))
  var best = mask
  if best < 0:
    var low = high(int)
    for m in 0 .. 7:
      var t = g
      t.applyMask(m)
      let p = t.penalty()
      if p < low:
        low = p
        best = m
  g.applyMask(best)
  g.drawFormat(formatBits(ec, best))
  g.drawVersion(ver, blank = false)
  QrCode(version: ver, ecc: ec, mask: best, mode: mode, size: g.n, dark: g.m)

# ---- pictures and outlines -------------------------------------------------------------------------------

proc qrBitmap*(q: QrCode; scale = 4; border = 4; dark = color(0, 0, 0);
               light = color(255, 255, 255)): Bitmap =
  ## The code as a picture: `scale` pixels a module, `border` modules of
  ## quiet zone (`light`) around it (4 is what the standard asks).
  let s = max(1, scale)
  let bd = max(0, border)
  let side = (q.size + 2 * bd) * s
  template argb(c: Color): uint32 =
    uint32(c.a) shl 24 or uint32(c.r) shl 16 or uint32(c.g) shl 8 or uint32(c.b)
  let dk = argb(dark)
  let lt = argb(light)
  result = newBitmap(side, side, lt)
  result.opaque = dark.a == 255 and light.a == 255
  for y in 0 ..< q.size:
    for x in 0 ..< q.size:
      if q.dark[y * q.size + x]:
        for yy in 0 ..< s:
          let row = ((bd + y) * s + yy) * side + (bd + x) * s
          for xx in 0 ..< s: result.px[row + xx] = dk

proc qrPath*(q: QrCode; scale = 1.0; x = 0.0; y = 0.0): seq[seq[(float, float)]] =
  ## The dark modules as closed outlines (one per region of modules joined
  ## by their sides; a point only where they turn): the outside of each
  ## region clockwise (y down), its holes anticlockwise, so they fill
  ## right with the non-zero and the even-odd rule alike. In modules from
  ## the code's top left corner (no quiet zone), times `scale`, moved by
  ## `x`, `y`.
  let n = q.size
  let w = n + 1                               # corner points a row
  # an edge from each corner point along the side of a dark module, with
  # the dark on its right (y down): up to two leave a point (diagonal touch)
  type Edge = tuple[to, dir: int]             # dir: 0 right, 1 down, 2 left, 3 up
  var outs = newSeq[array[2, int]](w * w)     # edge ids + 1 leaving each point
  var edges: seq[Edge]
  var froms: seq[int]
  proc addEdge(a, b, dir: int) =
    edges.add (b, dir)
    froms.add a
    if outs[a][0] == 0: outs[a][0] = edges.len else: outs[a][1] = edges.len
  for yy in 0 ..< n:
    for xx in 0 ..< n:
      if not q[xx, yy]: continue
      let tl = yy * w + xx
      let tr = tl + 1
      let bl = tl + w
      let br = bl + 1
      if not q[xx, yy - 1]: addEdge(tl, tr, 0)
      if not q[xx + 1, yy]: addEdge(tr, br, 1)
      if not q[xx, yy + 1]: addEdge(br, bl, 2)
      if not q[xx - 1, yy]: addEdge(bl, tl, 3)
  var used = newSeq[bool](edges.len)
  for start in 0 ..< edges.len:
    if used[start]: continue
    var poly: seq[(float, float)]
    var e = start
    var lastDir = -1
    while not used[e]:
      used[e] = true
      let p = froms[e]
      if edges[e].dir != lastDir:
        poly.add (x + float(p mod w) * scale, y + float(p div w) * scale)
        lastDir = edges[e].dir
      # next: of the edges leaving where this one ends, the one turning right
      # (dark on the right: diagonal neighbours stay apart)
      let o = outs[edges[e].to]
      var nxt = o[0] - 1
      if o[1] != 0:
        let a = o[0] - 1
        let b = o[1] - 1
        nxt = if edges[a].dir == (edges[e].dir + 1) mod 4: a else: b
      if nxt < 0: break
      e = nxt
    # the first point may sit in the middle of a straight side
    if poly.len >= 3:
      let a = poly[^1]
      let b = poly[0]
      let c = poly[1]
      if (a[0] == b[0] and b[0] == c[0]) or (a[1] == b[1] and b[1] == c[1]): poly.delete(0)
    if poly.len >= 3: result.add poly
