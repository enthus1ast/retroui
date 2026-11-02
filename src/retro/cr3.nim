## Canon's CRX codec: the sensor's numbers in a CR3 (and a CRM movie's
## frame), as rawformats reads them (`readSensor` of a CR3).
##
## A CR3's raw picture is one or four planes (the four places of the 2 x 2
## mosaic, each half as wide and high), cut in tiles. Each plane of a tile
## is coded alone, line after line: the error of a prediction from the
## line above and the number on the left, in adaptive Golomb-Rice codes,
## with runs of repeated numbers. The lossless pictures ("RAW") are coded
## as they are; Canon's smaller C-RAW codes 3 levels of a 5/3 wavelet (ten
## subbands), quantized by a table of steps over the picture. The numbers
## come out as LibRaw's crx.cpp decodes them (Alexey Danilchenko and LibRaw
## LLC, whose layout of the format this follows): bit for bit, including
## its edge cases.
##
##   let h = crxHeader(data, cmp1At, cmp1Len)    # the track's CMP1 box
##   let px = decodeCrx(data, h, sampleAt, sampleLen)  # h.width x h.height

import std/bitops
import rawphoto, parallel

{.push overflowChecks: off, rangeChecks: off.}

type
  CrxHeader* = object
    ## A CR3 track's CMP1 box: how its pictures are coded.
    version*: int                 ## 0x100 or 0x200 (with quantization tables)
    width*, height*: int          ## the sensor's numbers: `height` rows of `width`
    tileW*, tileH*: int
    nBits*: int                   ## bits a number
    nPlanes*: int                 ## 4 (a mosaic) or 1
    cfaLayout*: int               ## 0 RGGB, 1 GRBG, 2 GBRG, 3 BGGR
    encType*: int                 ## 0, 1 (signed numbers) or 3 (planes in other colors)
    levels*: int                  ## the wavelet's levels (0: lossless)
    mdatHdrSize*: int             ## the picture's headers before its data
    medianBits*: int

  U8 = ptr UncheckedArray[uint8]
  I32 = ptr UncheckedArray[int32]
  U32 = ptr UncheckedArray[uint32]

proc bad(msg: string) {.noreturn.} = raise newException(RawError, msg)

template off(p: I32; k: int): I32 = cast[I32](cast[int](p) + k * sizeof(int32))

proc be(p: U8; at, n: int): int {.inline.} =
  ## `n` bytes big-endian.
  for i in 0 ..< n: result = (result shl 8) or int(p[at + i])

proc crxHeader*(data: string; at, len: int): CrxHeader =
  ## The CMP1 box's contents (`len` bytes at `at`). Raises `RawError` when
  ## they are not a picture this decoder reads.
  if len < 32 or at < 0 or at + len > data.len: bad("a damaged CR3 track")
  var c: array[85, int]
  for i in 0 ..< min(len, 85): c[i] = int(uint8(data[at + i]))
  template g(o, n: int): int =
    var v = 0
    for i in 0 ..< n: v = (v shl 8) or c[o + i]
    v
  result.version = g(4, 2)
  result.width = g(8, 4)
  result.height = g(12, 4)
  result.tileW = g(16, 4)
  result.tileH = g(20, 4)
  result.nBits = c[24]
  result.nPlanes = c[25] shr 4
  result.cfaLayout = c[25] and 15
  result.encType = c[26] shr 4
  result.levels = c[26] and 15
  let tileCols = c[27] shr 7
  let tileRows = (c[27] shr 6) and 1
  result.mdatHdrSize = g(28, 4)
  result.medianBits = result.nBits
  let n = min(len, 85)
  if (c[32] shr 7) != 0 and n >= 56 and result.nPlanes == 4 and ((c[56] shr 6) and 1) != 0 and n >= 84:
    result.medianBits = c[84]
  let h = result
  if (h.version != 0x100 and h.version != 0x200) or h.mdatHdrSize == 0: bad("a CR3 picture coded in a way we do not read")
  if h.encType == 1:
    if h.nBits > 15: bad("a CR3 picture coded in a way we do not read")
  elif (h.encType != 0 and h.encType != 3) or h.nBits > 14: bad("a CR3 picture coded in a way we do not read")
  if h.nPlanes == 1:
    if h.cfaLayout != 0 or h.encType != 0 or h.nBits != 8: bad("a CR3 picture coded in a way we do not read")
  elif h.nPlanes != 4 or (h.width and 1) != 0 or (h.height and 1) != 0 or (h.tileW and 1) != 0 or
       (h.tileH and 1) != 0 or h.cfaLayout > 3 or h.nBits == 8:
    bad("a CR3 picture coded in a way we do not read")
  if h.tileW > h.width or h.tileH > h.height or h.levels > 3 or tileCols > 1 or tileRows > 1:
    bad("a CR3 picture coded in a way we do not read")

# ---- bits ------------------------------------------------------------------------------------------------------

type
  Bits = object
    ## Bits read most significant first; zeros past the end.
    p: U8
    pos, stop: int
    acc: uint64                 ## the next `n` bits, from the top
    n: int

proc refill(b: var Bits) {.inline.} =
  if b.pos + 8 <= b.stop:
    while b.n <= 55:
      b.acc = b.acc or (uint64(b.p[b.pos]) shl (56 - b.n))
      inc b.pos
      b.n += 8
  else:
    while b.n <= 55:
      let c = if b.pos < b.stop: uint64(b.p[b.pos]) else: 0'u64
      inc b.pos
      b.acc = b.acc or (c shl (56 - b.n))
      b.n += 8

proc zeros(b: var Bits): int {.inline.} =
  ## The zeros before the next one (which is taken too).
  if b.acc == 0 or b.n <= 55:
    b.refill()
    while b.acc == 0:
      result += b.n
      b.n = 0
      if b.pos > b.stop + 16: return    # (damaged: past the end)
      b.refill()
  let z = countLeadingZeroBits(b.acc)
  result += z
  b.acc = b.acc shl (z + 1)
  b.n -= z + 1

proc get(b: var Bits; k: int): int {.inline.} =
  ## The next `k` bits (1 .. 32).
  if b.n < k: b.refill()
  result = int(b.acc shr (64 - k))
  b.acc = b.acc shl k
  b.n -= k

# ---- a subband's lines --------------------------------------------------------------------------------------------

const
  runSteps: array[32, int] = [1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 8, 8, 8, 8, 0x10, 0x10, 0x20, 0x20, 0x40, 0x40,
                              0x80, 0x80, 0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000, 0x4000, 0x8000]
  runBits: array[32, int] = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11,
                             12, 13, 14, 15]
  qSteps: array[6, int32] = [0x28'i32, 0x2D, 0x33, 0x39, 0x40, 0x48]
  tilesRight = 1
  tilesLeft = 2
  tilesBelow = 4
  tilesAbove = 8

type
  Param = object
    ## A subband's line decoder: two lines (`data`, each `width` + 2 long,
    ## the one above and the one being read) and, coded without the line
    ## above, a line of Golomb parameters (`nonProgr`).
    bits: Bits
    width, height: int
    mask: int32                 ## rounding (lossless lines with fewer bits)
    roundedBits: int32
    curLine: int
    s, k: int                   ## run and Golomb parameters
    line0, line1, line2: I32
    data, nonProgr: I32
    partial: bool               ## predicted from the line above

proc predictK(k, code: int; most = 0): int {.inline.} =
  let n = k - ord(code < ((1 shl k) shr 1)) + ord((code shr k) > 2) + ord((code shr k) > 5)
  if most == 0 or n < most: n else: most

template code(p: var Param): int =
  var c = p.bits.zeros()
  if c >= 41: c = p.bits.get(21)
  elif p.k != 0: c = p.bits.get(p.k) or (c shl p.k)
  c

template signed(c: int): int32 = int32((-(c and 1)) xor (c shr 1))

proc run(p: var Param; length: int): int {.inline.} =
  ## A run's length (after its first one bit): more than `length` when damaged.
  result = 1
  while p.bits.get(1) != 0:
    result += runSteps[p.s]
    if result > length:
      result = length
      break
    if p.s < 31: inc p.s
    if result == length: break
  if result < length:
    if runBits[p.s] != 0: result += p.bits.get(runBits[p.s])
    if p.s > 0: dec p.s

proc symbol(p: var Param; median, notLast: bool) {.inline.} =
  let l0 = p.line0
  let l1 = p.line1
  if median:
    let delta = l0[1] - l0[0]
    let neg = delta < 0
    let i = (ord((l0[0] < l1[0]) xor neg) shl 1) + ord((l1[0] < l0[1]) xor neg)
    l1[1] = (if i < 2: delta + l1[0] elif i == 2: l1[0] else: l0[1])
  else:
    l1[1] = l0[1]
  var c = p.code()
  l1[1] = l1[1] + signed(c)
  if notLast:
    let next = (l0[2] - l0[1]) shl 1
    c = (c + abs(int(next))) shr 1
    p.line0 = off(l0, 1)
  p.k = predictK(p.k, c, 15)
  p.line1 = off(l1, 1)

proc lineMedian(p: var Param): bool =
  var length = p.width
  p.line1[0] = p.line0[1]
  while length > 1:
    if p.line1[0] != p.line0[1] or p.line1[0] != p.line0[2]:
      p.symbol(true, true)
    else:
      if p.bits.get(1) != 0:
        let n = p.run(length)
        if n > length: return false
        length -= n
        p.line0 = off(p.line0, n)
        for _ in 0 ..< n:
          p.line1[1] = p.line1[0]
          p.line1 = off(p.line1, 1)
      if length > 0: p.symbol(false, length > 1)
    dec length
  if length == 1: p.symbol(true, false)
  p.line1[1] = p.line1[0] + 1
  true

proc symbolRounded(p: var Param; doSym = true; doCode = true) {.inline.} =
  let l0 = p.line0
  let l1 = p.line1
  var sym = l0[1]
  if doSym:
    let delta = l0[1] - l0[0]
    let neg = delta < 0
    let i = (ord((l0[0] < l1[0]) xor neg) shl 1) + ord((l1[0] < l0[1]) xor neg)
    sym = (if i < 2: delta + l1[0] elif i == 2: l1[0] else: l0[1])
  let c = p.code()
  var v = signed(c)
  l1[1] = p.mask * 2 * v + (if v < 0: -1'i32 else: 0'i32) + sym
  if doCode:
    if l0[2] > l0[1]: v = (l0[2] - l0[1] + p.mask - 1) shr p.roundedBits
    else: v = -((l0[1] - l0[2] + p.mask) shr p.roundedBits)
    p.k = predictK(p.k, (c + 2 * abs(int(v))) shr 1, 15)
  else:
    p.k = predictK(p.k, c, 15)
  p.line1 = off(l1, 1)

proc lineRounded(p: var Param): bool =
  var reached = false
  p.line0[0] = p.line0[1]
  p.line1[0] = p.line0[1]
  var length = p.width
  while length > 1:
    if abs(p.line0[2] - p.line0[1]) > p.mask:
      p.symbolRounded()
      p.line0 = off(p.line0, 1)
      reached = true
    elif reached or abs(p.line0[0] - p.line1[0]) > p.mask:
      p.symbolRounded()
      p.line0 = off(p.line0, 1)
      reached = false
    else:
      var n = 0
      if p.bits.get(1) != 0:
        n = p.run(length)
        if n > length: return false
      length -= n
      p.line0 = off(p.line0, n)
      for _ in 0 ..< n:
        p.line1[1] = p.line1[0]
        p.line1 = off(p.line1, 1)
      if length > 1:
        p.symbolRounded(false)
        p.line0 = off(p.line0, 1)
        reached = abs(p.line0[1] - p.line0[0]) > p.mask
      elif length == 1:
        p.symbolRounded(false, false)
    dec length
  if length == 1: p.symbolRounded(true, false)
  p.line1[1] = p.line1[0] + 1
  true

proc lineAlone(p: var Param): bool =
  ## A line coded without the one above (but for its Golomb parameters).
  let l0 = p.line0
  let l1 = p.line1
  let l2 = p.line2
  let w = p.width
  var i = 0
  while i < w - 1:
    if (l0[i + 2] or l0[i + 1] or l1[i]) != 0:
      let c = p.code()
      l1[i + 1] = signed(c)
      p.k = predictK(p.k, c)
      if l2[i + 1] - p.k <= 1:
        if p.k >= 15: p.k = 15
      else: inc p.k
    else:
      var n = 0
      if p.bits.get(1) != 0:
        n = p.run(w - i)
        if i + n > w: return false
      if n > 0:
        for j in 0 ..< n:
          l1[i + 1 + j] = 0
          l2[i + j] = 0
        i += n
      if i >= w - 1:
        if i == w - 1:
          let c = p.code()
          l1[i + 1] = signed(c + 1)
          p.k = predictK(p.k, c, 15)
          l2[i] = int32(p.k)
        inc i
        continue
      else:
        let c = p.code()
        l1[i + 1] = signed(c + 1)
        p.k = predictK(p.k, c)
        if l2[i + 1] - p.k <= 1:
          if p.k >= 15: p.k = 15
        else: inc p.k
    l2[i] = int32(p.k)
    inc i
  if i == w - 1:
    let c = p.code()
    l1[i + 1] = signed(c)
    p.k = predictK(p.k, c, 15)
    l2[i] = int32(p.k)
  true

proc topLine(p: var Param): bool =
  p.line1[0] = 0
  var length = p.width
  while length > 1:
    if p.line1[0] != 0:
      p.line1[1] = p.line1[0]
    else:
      if p.bits.get(1) != 0:
        let n = p.run(length)
        if n > length: return false
        length -= n
        for _ in 0 ..< n:
          p.line1[1] = p.line1[0]
          p.line1 = off(p.line1, 1)
        if length <= 0: break
      p.line1[1] = 0
    let c = p.code()
    p.line1[1] = p.line1[1] + signed(c)
    p.k = predictK(p.k, c, 15)
    p.line1 = off(p.line1, 1)
    dec length
  if length == 1:
    p.line1[1] = p.line1[0]
    let c = p.code()
    p.line1[1] = p.line1[1] + signed(c)
    p.k = predictK(p.k, c, 15)
    p.line1 = off(p.line1, 1)
  p.line1[1] = p.line1[0] + 1
  true

proc topLineRounded(p: var Param): bool =
  p.line1[0] = 0
  var length = p.width
  while length > 1:
    if abs(p.line1[0]) > p.mask:
      p.line1[1] = p.line1[0]
    else:
      var n = 0
      if p.bits.get(1) != 0:
        n = p.run(length)
        if n > length: return false
      length -= n
      for _ in 0 ..< n:
        p.line1[1] = p.line1[0]
        p.line1 = off(p.line1, 1)
      if length <= 0: break
      p.line1[1] = 0
    let c = p.code()
    let v = signed(c)
    p.line1[1] = p.line1[1] + p.mask * 2 * v + (if v < 0: -1'i32 else: 0'i32)
    p.k = predictK(p.k, c, 15)
    p.line1 = off(p.line1, 1)
    dec length
  if length == 1:
    let c = p.code()
    let v = signed(c)
    p.line1[1] = p.line1[1] + p.mask * 2 * v + (if v < 0: -1'i32 else: 0'i32)
    p.k = predictK(p.k, c, 15)
    p.line1 = off(p.line1, 1)
  p.line1[1] = p.line1[0] + 1
  true

proc topLineAlone(p: var Param): bool =
  p.line0[0] = 0
  p.line1[0] = 0
  var length = p.width
  while length > 1:
    if p.line1[0] != 0:
      let c = p.code()
      p.line1[1] = signed(c)
      p.k = predictK(p.k, c, 15)
    else:
      var n = 0
      if p.bits.get(1) != 0:
        n = p.run(length)
        if n > length: return false
      length -= n
      for _ in 0 ..< n:
        p.line2[0] = 0
        p.line1[1] = 0
        p.line1 = off(p.line1, 1)
        p.line2 = off(p.line2, 1)
      if length <= 0: break
      let c = p.code()
      p.line1[1] = signed(c + 1)
      p.k = predictK(p.k, c, 15)
    p.line2[0] = int32(p.k)
    p.line2 = off(p.line2, 1)
    p.line1 = off(p.line1, 1)
    dec length
  if length == 1:
    let c = p.code()
    p.line1[1] = signed(c)
    p.k = predictK(p.k, c, 15)
    p.line2[0] = int32(p.k)
    p.line1 = off(p.line1, 1)
  p.line1[1] = 0
  true

proc nextLine(p: var Param; dst: I32): bool =
  ## The subband's next line into `dst`.
  if p.curLine >= p.height: return false
  let ll = p.width + 2
  if p.curLine == 0:
    p.s = 0
    p.k = 0
    p.line0 = p.data
    p.line1 = off(p.data, ll)
    let src = off(p.line1, 1)
    if p.partial:
      if p.mask <= 0:
        if not p.topLine(): return false
      else:
        p.roundedBits = 1
        if (p.mask and not 1'i32) != 0:
          while (p.mask shr p.roundedBits) != 0: inc p.roundedBits
        if not p.topLineRounded(): return false
    else:
      p.line2 = p.nonProgr
      if not p.topLineAlone(): return false
    copyMem(dst, src, p.width * sizeof(int32))
  else:
    if (p.curLine and 1) != 0:
      p.line1 = p.data
      p.line0 = off(p.data, ll)
    else:
      p.line0 = p.data
      p.line1 = off(p.data, ll)
    let src = off(p.line1, 1)
    if not p.partial:
      p.line2 = p.nonProgr
      if not p.lineAlone(): return false
    elif p.mask <= 0:
      if not p.lineMedian(): return false
    else:
      if not p.lineRounded(): return false
    copyMem(dst, src, p.width * sizeof(int32))
  inc p.curLine
  true

# ---- subbands, quantization ---------------------------------------------------------------------------------------

type
  Subband = object
    param: Param
    buf: I32                    ## its current line
    width, height: int
    qParam, kParam: int
    qStepBase, qStepMult: uint32
    partial: bool               ## its quantizer changes line by line
    dataSize, dataOffset: int
    rowStartAddOn, rowEndAddOn, colStartAddOn, colEndAddOn, levelShift: int

  QStep = object
    tbl: U32
    width, height: int

proc updateQ(b: var Subband): bool =
  var c = b.param.bits.zeros()
  if c >= 23: c = b.param.bits.get(8)
  elif b.kParam != 0: c = b.param.bits.get(b.kParam) or (c shl b.kParam)
  b.qParam += int(signed(c))
  b.kParam = predictK(b.kParam, c)
  b.kParam <= 7

proc subbandRow(b: Subband; row: int): int {.inline.} =
  if row < b.rowStartAddOn: 0
  elif row < b.height - b.rowEndAddOn: row - b.rowEndAddOn
  else: b.height - b.rowEndAddOn - b.rowStartAddOn - 1

template quant(b: Subband; t: uint32): int32 =
  clamp(cast[int32](b.qStepBase + ((t * b.qStepMult) shr 3)), 1'i32, 0x168000'i32)

proc lineQuantized(b: var Subband; q: ptr QStep): bool =
  ## The subband's next line, its numbers scaled by their quantizer's step.
  if b.dataSize == 0:
    zeroMem(b.buf, b.width * sizeof(int32))
    return true
  if b.partial and q == nil and not b.updateQ(): return false
  if not b.param.nextLine(b.buf): return false
  if b.width <= 0: return true
  let buf = b.buf
  if q != nil:
    let t = cast[U32](addr q.tbl[q.width * b.subbandRow(b.param.curLine - 1)])
    for i in 0 ..< b.colStartAddOn: buf[i] = buf[i] * b.quant(t[0])
    for i in b.colStartAddOn ..< b.width - b.colEndAddOn:
      buf[i] = buf[i] * b.quant(t[(i - b.colStartAddOn) shr b.levelShift])
    let last = (b.width - b.colEndAddOn - b.colStartAddOn - 1) shr b.levelShift
    for i in b.width - b.colEndAddOn ..< b.width: buf[i] = buf[i] * b.quant(t[last])
  else:
    # (the first C-RAWs: one step a line, in sixths of an octave)
    let d = b.qParam div 6
    let m = b.qParam mod 6
    var scale = qSteps[max(0, m)] shr ((6 - d) and 31)
    if d >= 6: scale = qSteps[m] * (1'i32 shl ((d + 26) and 31))
    if scale != 1:
      for i in 0 ..< b.width: buf[i] = buf[i] * scale
  true

# ---- the 5/3 wavelet, undone line by line --------------------------------------------------------------------------

type
  Wavelet = object
    sb0, sb1, sb2, sb3: I32     ## the current lines of its low and high subbands
    lineBuf: array[8, I32]
    curLine, curH, fltTapH, height, width: int

  Comp = object
    ## A plane of a tile.
    bands: seq[Subband]
    wt: seq[Wavelet]
    arena: seq[int32]           ## the subbands' lines, the wavelet's
    params: seq[int32]          ## the subbands' decoders' lines
    dataOffset, size: int
    partial: bool
    mask: int32
    flag: int

  Tile = object
    comps: seq[Comp]
    flag, dataOffset, size, width, height: int
    hasQP: bool
    qpSize, extraSize: int
    qTbl: seq[uint32]
    qStep: seq[QStep]

  Img = ref object
    p: U8
    n: int
    version, nPlanes, planeW, planeH, nBits, encType, levels, bandCount, medianBits: int
    tileCols, tileRows: int
    tiles: seq[Tile]
    mdatOffset: int
    outp: ptr UncheckedArray[uint16]
    outOff: array[4, int]
    planeBuf: seq[int16]

template lowHigh(dst: var I32; lo, hi: var I32; flag: int; w: int) =
  ## A line made of its low (`lo`) and high (`hi`) halves.
  if (flag and tilesLeft) != 0:
    dst[0] = lo[0] - ((hi[0] + hi[1] + 2) shr 2)
    hi = off(hi, 1)
  else:
    dst[0] = lo[0] - ((hi[0] + 1) shr 1)
  lo = off(lo, 1)
  var i = 0
  while i < w - 3:
    let delta = lo[0] - ((hi[0] + hi[1] + 2) shr 2)
    dst[1] = hi[0] + ((dst[0] + delta) shr 1)
    dst[2] = delta
    lo = off(lo, 1)
    hi = off(hi, 1)
    dst = off(dst, 2)
    i += 2

proc horizontal53(la, lb: I32; w: var Wavelet; flag: int) =
  var lineA = la
  var lineB = lb
  var b0 = w.sb0
  var b1 = w.sb1
  var b2 = w.sb2
  var b3 = w.sb3
  if w.width <= 1:
    lineA[0] = b0[0]
    lineB[0] = b2[0]
  else:
    if (flag and tilesLeft) != 0:
      lineA[0] = b0[0] - ((b1[0] + b1[1] + 2) shr 2)
      lineB[0] = b2[0] - ((b3[0] + b3[1] + 2) shr 2)
      b1 = off(b1, 1)
      b3 = off(b3, 1)
    else:
      lineA[0] = b0[0] - ((b1[0] + 1) shr 1)
      lineB[0] = b2[0] - ((b3[0] + 1) shr 1)
    b0 = off(b0, 1)
    b2 = off(b2, 1)
    var i = 0
    while i < w.width - 3:
      var delta = b0[0] - ((b1[0] + b1[1] + 2) shr 2)
      lineA[1] = b1[0] + ((delta + lineA[0]) shr 1)
      lineA[2] = delta
      delta = b2[0] - ((b3[0] + b3[1] + 2) shr 2)
      lineB[1] = b3[0] + ((delta + lineB[0]) shr 1)
      lineB[2] = delta
      b0 = off(b0, 1)
      b1 = off(b1, 1)
      b2 = off(b2, 1)
      b3 = off(b3, 1)
      lineA = off(lineA, 2)
      lineB = off(lineB, 2)
      i += 2
    if (flag and tilesRight) != 0:
      let deltaA = b0[0] - ((b1[0] + b1[1] + 2) shr 2)
      lineA[1] = b1[0] + ((deltaA + lineA[0]) shr 1)
      let deltaB = b2[0] - ((b3[0] + b3[1] + 2) shr 2)
      lineB[1] = b3[0] + ((deltaB + lineB[0]) shr 1)
      if (w.width and 1) != 0:
        lineA[2] = deltaA
        lineB[2] = deltaB
    elif (w.width and 1) != 0:
      lineA[1] = b1[0] + ((lineA[0] + b0[0] - ((b1[0] + 1) shr 1)) shr 1)
      lineA[2] = b0[0] - ((b1[0] + 1) shr 1)
      lineB[1] = b3[0] + ((lineB[0] + b2[0] - ((b3[0] + 1) shr 1)) shr 1)
      lineB[2] = b2[0] - ((b3[0] + 1) shr 1)
    else:
      lineA[1] = lineA[0] + b1[0]
      lineB[1] = lineB[0] + b3[0]

proc horizontalOne(dst: I32; lo, hi: I32; w: Wavelet; flag: int; oddTail = true) =
  ## One line of a level from its low and high subbands' lines.
  var d = dst
  var b0 = lo
  var b1 = hi
  if w.width <= 1:
    d[0] = b0[0]
    return
  lowHigh(d, b0, b1, flag, w.width)
  if (flag and tilesRight) != 0:
    let delta = b0[0] - ((b1[0] + b1[1] + 2) shr 2)
    d[1] = b1[0] + ((d[0] + delta) shr 1)
    if not oddTail or (w.width and 1) != 0: d[2] = delta
  elif (w.width and 1) != 0:
    let delta = b0[0] - ((b1[0] + 1) shr 1)
    d[1] = b1[0] + ((d[0] + delta) shr 1)
    d[2] = delta
  else:
    d[1] = b1[0] + d[0]

proc getLine(c: var Comp; level: int): I32 {.inline.} =
  let w = addr c.wt[level]
  result = w.lineBuf[(w.fltTapH - w.curH + 5) mod 5 + 3]
  dec w.curH

proc qAt(q: ptr QStep; level: int): ptr QStep {.inline.} =
  if q == nil: nil else: cast[ptr QStep](cast[int](q) + level * sizeof(QStep))

proc filterDecode(c: var Comp; level: int; q: ptr QStep): bool =
  if c.wt[level].curH != 0: return true
  let sb = 3 * level
  let ql = qAt(q, level)
  if c.wt[level].height - 3 <= c.wt[level].curLine and (c.flag and tilesBelow) == 0:
    if (c.wt[level].height and 1) != 0:
      if level > 0:
        if not c.filterDecode(level - 1, q): return false
      elif not c.bands[sb].lineQuantized(ql): return false
      if not c.bands[sb + 1].lineQuantized(ql): return false
  else:
    if level > 0:
      if not c.filterDecode(level - 1, q): return false
    elif not c.bands[sb].lineQuantized(ql): return false
    if not c.bands[sb + 1].lineQuantized(ql) or not c.bands[sb + 2].lineQuantized(ql) or
       not c.bands[sb + 3].lineQuantized(ql): return false
  true

proc filterTransform(c: var Comp; level: int): bool =
  template w: untyped = c.wt[level]
  if w.curH != 0: return true
  if w.curLine >= w.height - 3:
    if (c.flag and tilesBelow) == 0:
      if (w.height and 1) != 0:
        if level > 0:
          if c.wt[level - 1].curH == 0:
            if not c.filterTransform(level - 1): return false
          w.sb0 = c.getLine(level - 1)
        let lineH0 = w.lineBuf[w.fltTapH + 3]
        let lineH1 = w.lineBuf[(w.fltTapH + 1) mod 5 + 3]
        let lineH2 = w.lineBuf[(w.fltTapH + 2) mod 5 + 3]
        let lineL0 = w.lineBuf[0]
        let lineL1 = w.lineBuf[1]
        w.lineBuf[1] = w.lineBuf[2]
        w.lineBuf[2] = lineL1
        # the L bands
        horizontalOne(lineL0, w.sb0, w.sb1, w, c.flag)
        # the H bands
        let l0 = w.lineBuf[0]
        let l1 = w.lineBuf[1]
        for i in 0 ..< w.width:
          let delta = l0[i] - ((l1[i] + 1) shr 1)
          lineH1[i] = l1[i] + ((delta + lineH0[i]) shr 1)
          lineH2[i] = delta
        w.curH += 3
        w.curLine += 3
        w.fltTapH = (w.fltTapH + 3) mod 5
      else:
        let lineL2 = w.lineBuf[2]
        let lineH0 = w.lineBuf[w.fltTapH + 3]
        let lineH1 = w.lineBuf[(w.fltTapH + 1) mod 5 + 3]
        w.lineBuf[1] = lineL2
        w.lineBuf[2] = w.lineBuf[1]
        for i in 0 ..< w.width: lineH1[i] = lineH0[i] + lineL2[i]
        w.curH += 2
        w.curLine += 2
        w.fltTapH = (w.fltTapH + 2) mod 5
  else:
    if level > 0:
      if c.wt[level - 1].curH == 0 and not c.filterTransform(level - 1): return false
      w.sb0 = c.getLine(level - 1)
    let lineL0 = w.lineBuf[0]
    let lineL1 = w.lineBuf[1]
    let lineH0 = w.lineBuf[w.fltTapH + 3]
    let lineH1 = w.lineBuf[(w.fltTapH + 1) mod 5 + 3]
    let lineH2 = w.lineBuf[(w.fltTapH + 2) mod 5 + 3]
    w.lineBuf[1] = w.lineBuf[2]
    w.lineBuf[2] = lineL1
    # the L bands
    horizontal53(lineL0, lineL1, w, c.flag)
    # the H bands
    let l0 = w.lineBuf[0]
    let l1 = w.lineBuf[1]
    let l2 = w.lineBuf[2]
    for i in 0 ..< w.width:
      let delta = l0[i] - ((l2[i] + l1[i] + 2) shr 2)
      lineH1[i] = l1[i] + ((delta + lineH0[i]) shr 1)
      lineH2[i] = delta
    if w.curLine >= w.height - 3 and (w.height and 1) != 0:
      w.curH += 3
      w.curLine += 3
      w.fltTapH = (w.fltTapH + 3) mod 5
    else:
      w.curH += 2
      w.curLine += 2
      w.fltTapH = (w.fltTapH + 2) mod 5
  true

proc filterInit(c: var Comp; levels: int; q: ptr QStep): bool =
  for level in 0 ..< levels:
    let band = 3 * level
    let ql = qAt(q, level)
    template w: untyped = c.wt[level]
    if level > 0: w.sb0 = c.getLine(level - 1)
    elif not c.bands[band].lineQuantized(ql): return false
    let lineH0 = w.lineBuf[w.fltTapH + 3]
    if w.height > 1:
      if not c.bands[band + 1].lineQuantized(ql) or not c.bands[band + 2].lineQuantized(ql) or
         not c.bands[band + 3].lineQuantized(ql): return false
      let lineL0 = w.lineBuf[0]
      let lineL1 = w.lineBuf[1]
      let lineL2 = w.lineBuf[2]
      if (c.flag and tilesAbove) != 0:
        horizontal53(lineL0, w.lineBuf[1], w, c.flag)
        if not c.bands[band + 3].lineQuantized(ql) or not c.bands[band + 2].lineQuantized(ql): return false
        # the L band
        horizontalOne(lineL2, w.sb2, w.sb3, w, c.flag)
        # the H band
        for i in 0 ..< w.width: lineH0[i] = lineL0[i] - ((lineL1[i] + lineL2[i] + 2) shr 2)
      else:
        horizontal53(lineL0, w.lineBuf[2], w, c.flag)
        for i in 0 ..< w.width: lineH0[i] = lineL0[i] - ((lineL2[i] + 1) shr 1)
      if not c.filterDecode(level, q) or not c.filterTransform(level): return false
    else:
      if not c.bands[band + 1].lineQuantized(ql): return false
      # the H band
      horizontalOne(lineH0, w.sb0, w.sb1, w, c.flag, oddTail = false)
      inc w.curLine
      inc w.curH
      w.fltTapH = (w.fltTapH + 1) mod 5
  true

# ---- the picture's headers ------------------------------------------------------------------------------------------

const exCoefs: array[144, int] = [
  1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0,
  0, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 0, 1, 0,
  0, 0, 1, 2, 2, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0, 1, 2, 2,
  1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 2, 2, 2, 2, 1, 1, 1,
  1, 2, 2, 1, 1, 1, 1, 2, 2, 1, 1, 0, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1]

proc setIdx(img: Img; b: var Subband; level, colStart, widthEx, rowStart, heightEx: int) =
  if img.version == 0x200:
    b.rowStartAddOn = rowStart
    b.rowEndAddOn = heightEx
    b.colStartAddOn = colStart
    b.colEndAddOn = widthEx
    b.levelShift = 3 - level
  else:
    b.rowStartAddOn = 0
    b.rowEndAddOn = 0
    b.colStartAddOn = 0
    b.colEndAddOn = 0
    b.levelShift = 0

proc subbandSizes(img: Img; tile: Tile; c: var Comp) =
  ## Each subband's size: half the level's above, and the coefficients it
  ## shares with the tiles beside it.
  var bi = img.bandCount - 1
  var bandH = tile.height
  var bandW = tile.width
  var widthEx, heightEx = 0
  if img.levels > 0:
    let rowEx = 0x30 * (img.levels - 1) + 6 * (tile.width and 7)
    let colEx = 0x30 * (img.levels - 1) + 6 * (tile.height and 7)
    for level in 0 ..< img.levels:
      let wOdd = bandW and 1
      let hOdd = bandH and 1
      bandW = (wOdd + bandW) shr 1
      bandH = (hOdd + bandH) shr 1
      var wEx0, wEx1, hEx0, hEx1, colStart, rowStart = 0
      if (tile.flag and tilesRight) != 0:
        wEx0 = exCoefs[rowEx + 2 * level]
        wEx1 = exCoefs[rowEx + 2 * level + 1]
      if (tile.flag and tilesLeft) != 0:
        inc wEx0
        colStart = 1
      if (tile.flag and tilesBelow) != 0:
        hEx0 = exCoefs[colEx + 2 * level]
        hEx1 = exCoefs[colEx + 2 * level + 1]
      if (tile.flag and tilesAbove) != 0:
        inc hEx0
        rowStart = 1
      c.bands[bi].width = bandW + wEx0 - wOdd
      c.bands[bi].height = bandH + hEx0 - hOdd
      img.setIdx(c.bands[bi], level + 1, colStart, wEx0 - colStart, rowStart, hEx0 - rowStart)
      c.bands[bi - 1].width = bandW + wEx1
      c.bands[bi - 1].height = bandH + hEx0 - hOdd
      img.setIdx(c.bands[bi - 1], level + 1, 0, wEx1, rowStart, hEx0 - rowStart)
      c.bands[bi - 2].width = bandW + wEx0 - wOdd
      c.bands[bi - 2].height = bandH + hEx1
      img.setIdx(c.bands[bi - 2], level + 1, colStart, wEx0 - colStart, 0, hEx1)
      bi -= 3
    if (tile.flag and tilesRight) != 0: widthEx = exCoefs[rowEx + 2 * img.levels - 1]
    if (tile.flag and tilesBelow) != 0: heightEx = exCoefs[colEx + 2 * img.levels - 1]
  c.bands[bi].width = widthEx + bandW
  c.bands[bi].height = heightEx + bandH
  if img.levels > 0: img.setIdx(c.bands[bi], img.levels, 0, widthEx, 0, heightEx)

proc subbandHeaders(img: Img; c: var Comp; at: var int; left: var int): bool =
  var offset = 0
  for i in 0 ..< img.bandCount:
    if left < 4: return false
    let sign = be(img.p, at, 2)
    let size = be(img.p, at + 2, 2)
    if left < size + 4: return false
    if (sign != 0xFF03 or size != 8) and (sign != 0xFF13 or size != 16): return false
    let bandSize = be(img.p, at + 4, 4)
    if i != (int(img.p[at + 8]) and 0xF0) shr 4: return false
    template b: untyped = c.bands[i]
    b.dataOffset = offset
    b.kParam = 0
    if sign == 0xFF03:
      let bits = be(img.p, at + 8, 4)
      b.dataSize = bandSize - (bits and 0x7FFFF)
      b.partial = (bits and 0x8000000) != 0
      b.qParam = (bits shr 19) and 0xFF
      b.qStepBase = 0
      b.qStepMult = 0
    else:
      if (be(img.p, at + 8, 2) and 0xFFF) != 0 or be(img.p, at + 18, 2) != 0: return false
      b.partial = false
      b.qParam = 0
      b.dataSize = bandSize - be(img.p, at + 16, 2)
      b.qStepBase = uint32(be(img.p, at + 12, 4))
      b.qStepMult = uint32(be(img.p, at + 10, 2))
    offset += bandSize
    at += size + 4
    left -= size + 4
  true

proc qpLine(bits: var Bits; k: var int): int {.inline.} =
  result = bits.zeros()
  if result >= 23: result = bits.get(8)
  elif k != 0: result = bits.get(k) or (result shl k)

proc qpStep(v: int): uint32 =
  if v div 6 >= 6: uint32(qSteps[v mod 6]) shl ((v div 6 - 6) and 31)
  else: uint32(qSteps[max(0, v mod 6)] shr ((6 - v div 6) and 31))

proc quantSteps(img: Img; tile: var Tile) =
  ## The tile's table of quantization steps, coded in its own bits.
  var bits = Bits(p: img.p, pos: img.mdatOffset + tile.dataOffset,
                  stop: min(img.n, img.mdatOffset + tile.dataOffset + tile.qpSize))
  let qpW = (tile.width shr 3) + ord((tile.width and 7) != 0)
  let qpH = (tile.height shr 1) + (tile.height and 1)
  let total = qpW * qpH
  var tbl = newSeq[int32](total + 2 * (qpW + 2) + 4)
  let base = cast[I32](addr tbl[0])
  let lines = off(base, total)
  var k = 0
  var cur = 0
  for row in 0 ..< qpH:
    let line0 = if (row and 1) != 0: off(lines, qpW + 2) else: lines
    let line1 = if (row and 1) != 0: lines else: off(lines, qpW + 2)
    if row > 0:
      var l0 = line0
      var l1 = line1
      l1[0] = l0[1]
      var deltaH = l0[1] - l0[0]
      var width = qpW
      while width > 0:
        dec width
        # (the prediction: the left, the left plus the slope, or the one above)
        let left = l1[0]
        let top = l0[1]
        let deltaV = l0[0] - l1[0]
        let i = (ord((deltaV < 0) xor (deltaH < 0)) shl 1) + ord((left < top) xor (deltaH < 0))
        l1[1] = (if i < 2: left + deltaH elif i == 2: left else: top)
        let qp = bits.qpLine(k)
        l1[1] = l1[1] + signed(qp)
        if width > 0:
          deltaH = l0[2] - l0[1]
          k = predictK(k, (qp + 2 * abs(int(deltaH))) shr 1, 7)
          l0 = off(l0, 1)
        else:
          k = predictK(k, qp, 7)
        l1 = off(l1, 1)
      l1[1] = l1[0] + 1
    else:
      var l = line1
      l[0] = 0
      for _ in 0 ..< qpW:
        l[1] = l[0]
        let qp = bits.qpLine(k)
        l[1] = l[1] + signed(qp)
        k = predictK(k, qp, 7)
        l = off(l, 1)
      l[1] = l[0] + 1
    for col in 0 ..< qpW:
      tbl[cur] = line1[col + 1] + 4
      inc cur
  # each level's steps, the coarsest first: its rows of the table averaged
  # 4 by 4 (3 levels), 2 by 2 (2 levels), as they are (the finest)
  let qpH4 = (tile.height shr 2) + ord((tile.height and 3) != 0)
  let qpH8 = (tile.height shr 3) + ord((tile.height and 7) != 0)
  var levels: seq[(int, int)]                 # (rows averaged, height)
  if img.levels > 2: levels.add (4, qpH8)
  if img.levels > 1: levels.add (2, qpH4)
  levels.add (1, qpH)
  var size = 0
  for (_, h) in levels: size += h * qpW
  tile.qTbl = newSeq[uint32](size + 1)
  tile.qStep = newSeq[QStep](levels.len)
  var o = 0
  for li, (rows, h) in levels:
    tile.qStep[li] = QStep(tbl: cast[U32](addr tile.qTbl[o]), width: qpW, height: h)
    for row in 0 ..< h:
      for col in 0 ..< qpW:
        var v: int
        case rows
        of 4:
          v = 0
          for j in 0 .. 3: v += int(tbl[qpW * min(4 * row + j, qpH - 1) + col])
          v = (ord(v < 0) * 3 + v) shr 2
        of 2:
          v = (int(tbl[qpW * min(2 * row, qpH - 1) + col]) + int(tbl[qpW * min(2 * row + 1, qpH - 1) + col])) div 2
        else:
          v = int(tbl[row * qpW + col])
        tile.qTbl[o] = qpStep(v)
        inc o

proc imageHeaders(img: Img; tileW, tileH: int; at, size: int) =
  ## The tiles', planes' and subbands' headers (`size` bytes at `at`).
  let nTiles = img.tileRows * img.tileCols
  img.tiles = newSeq[Tile](nTiles)
  for t in 0 ..< nTiles:
    template tile: untyped = img.tiles[t]
    if (t + 1) mod img.tileCols != 0:
      tile.width = tileW
      if img.tileCols > 1:
        tile.flag = tilesRight
        if t mod img.tileCols != 0: tile.flag = tile.flag or tilesLeft
    else:
      tile.width = img.planeW - tileW * (img.tileCols - 1)
      if img.tileCols > 1: tile.flag = tilesLeft
    if t < nTiles - img.tileCols:
      tile.height = tileH
      if img.tileRows > 1:
        tile.flag = tile.flag or tilesBelow
        if t >= img.tileCols: tile.flag = tile.flag or tilesAbove
    else:
      tile.height = img.planeH - tileH * (img.tileRows - 1)
      if img.tileRows > 1: tile.flag = tile.flag or tilesAbove
    tile.comps = newSeq[Comp](img.nPlanes)
    for c in 0 ..< img.nPlanes:
      tile.comps[c].partial = true
      tile.comps[c].flag = tile.flag
      tile.comps[c].bands = newSeq[Subband](img.bandCount)
      for b in 0 ..< img.bandCount: tile.comps[c].bands[b].qParam = 4
  var left = size
  var p = at
  var tileOffset = 0
  for t in 0 ..< nTiles:
    template tile: untyped = img.tiles[t]
    if left < 4: bad("a damaged CR3 picture")
    let sign = be(img.p, p, 2)
    let hsize = be(img.p, p + 2, 2)
    if (sign != 0xFF01 or hsize != 8) and (sign != 0xFF11 or (hsize != 8 and hsize != 16)): bad("a damaged CR3 picture")
    if left < hsize + 4: bad("a damaged CR3 picture")
    let tail = be(img.p, p + 10, 2)
    if (hsize == 8 and tail != 0) or (hsize == 16 and tail != 0x4000): bad("a damaged CR3 picture")
    if be(img.p, p + 8, 2) != t: bad("a damaged CR3 picture")
    left -= hsize + 4
    tile.size = be(img.p, p + 4, 4)
    tile.dataOffset = tileOffset
    if hsize == 16:
      if be(img.p, p + 18, 2) != 0: bad("a damaged CR3 picture")
      tile.hasQP = true
      tile.qpSize = be(img.p, p + 12, 4)
      tile.extraSize = be(img.p, p + 16, 2)
    p += hsize + 4
    tileOffset += tile.size
    var compOffset = 0
    for ci in 0 ..< img.nPlanes:
      template c: untyped = tile.comps[ci]
      if left < 12: bad("a damaged CR3 picture")
      let s = be(img.p, p, 2)
      let z = be(img.p, p + 2, 2)
      if (s != 0xFF02 and s != 0xFF12) or z != 8: bad("a damaged CR3 picture")
      if ci != int(img.p[p + 8]) shr 4 or be(img.p, p + 9, 3) != 0: bad("a damaged CR3 picture")
      c.size = be(img.p, p + 4, 4)
      let rounded = (int(img.p[p + 8]) shr 1) and 3
      c.partial = (int(img.p[p + 8]) and 8) != 0
      c.dataOffset = compOffset
      c.flag = tile.flag
      compOffset += c.size
      left -= 12
      p += 12
      c.mask = 0
      if rounded != 0:
        if img.levels > 0 or not c.partial: bad("a damaged CR3 picture")
        c.mask = int32(1 shl (rounded - 1))
      if not img.subbandHeaders(c, p, left): bad("a damaged CR3 picture")
      img.subbandSizes(tile, c)
  if img.version == 0x200:
    for t in 0 ..< nTiles:
      if img.tiles[t].hasQP:
        if img.levels < 1 or img.levels > 3: bad("a damaged CR3 picture")
        img.quantSteps(img.tiles[t])

# ---- the planes -----------------------------------------------------------------------------------------------------

proc setupComp(img: Img; tile: Tile; c: var Comp; tileMdat: int) =
  ## The plane's buffers, and its subbands' decoders at their data.
  var total = 0
  for b in c.bands: total += max(0, b.width)
  var lines = 0
  if img.levels > 0:
    for level in 0 ..< img.levels:
      lines += 8 * (if level < img.levels - 1: c.bands[3 * (level + 1) + 2].width else: tile.width)
  c.arena = newSeq[int32](total + lines + 16)
  let base = cast[I32](addr c.arena[0])
  var o = 0
  for b in 0 ..< img.bandCount:
    c.bands[b].buf = off(base, o)
    o += max(0, c.bands[b].width)
  if img.levels > 0:
    c.wt = newSeq[Wavelet](img.levels)
    c.wt[0].sb0 = c.bands[0].buf
    for level in 0 ..< img.levels:
      let band = 3 * level + 1
      var tw: int
      if level >= img.levels - 1:
        c.wt[level].height = tile.height
        tw = tile.width
      else:
        c.wt[level].height = c.bands[band + 3].height
        tw = c.bands[band + 4].width
      c.wt[level].width = tw
      for k in 0 .. 7: c.wt[level].lineBuf[k] = off(base, o + k * tw)
      o += 8 * tw
      c.wt[level].sb1 = c.bands[band].buf
      c.wt[level].sb2 = c.bands[band + 1].buf
      c.wt[level].sb3 = c.bands[band + 2].buf
  var psize = 0
  for b in 0 ..< img.bandCount:
    if c.bands[b].dataSize != 0:
      let partial = c.partial and b == 0
      psize += 2 * c.bands[b].width + 4 + (if partial: 0 else: c.bands[b].width) + 8
  c.params = newSeq[int32](psize + 8)
  let pbase = cast[I32](addr c.params[0])
  o = 0
  for b in 0 ..< img.bandCount:
    template band: untyped = c.bands[b]
    if band.dataSize != 0:
      let partial = c.partial and b == 0
      let at = img.mdatOffset + tileMdat + band.dataOffset
      band.param = Param(bits: Bits(p: img.p, pos: at, stop: min(img.n, at + band.dataSize)),
                         width: band.width, height: band.height, partial: partial,
                         mask: (if partial: c.mask else: 0'i32))
      band.param.data = off(pbase, o)
      o += 2 * band.width + 4
      if not partial:
        band.param.nonProgr = off(pbase, o)
        o += band.width
      o += 8

proc convertLine(img: Img; row, col, plane: int; line: I32; n: int) =
  let o = img.outp
  case img.encType
  of 1:
    var hi = 1 shl (img.nBits - 1)
    let lo = -hi
    dec hi
    let at = img.outOff[plane] + 4 * img.planeW * row + 2 * col
    for i in 0 ..< n: o[at + 2 * i] = cast[uint16](int16(clamp(int(line[i]), lo, hi)))
  of 3:
    let at = plane * img.planeW * img.planeH + img.planeW * row + col
    for i in 0 ..< n: img.planeBuf[at + i] = int16(line[i])
  else:
    let median = 1 shl (img.nBits - 1)
    let hi = (1 shl img.nBits) - 1
    if img.nPlanes == 4:
      let at = img.outOff[plane] + 4 * img.planeW * row + 2 * col
      for i in 0 ..< n: o[at + 2 * i] = uint16(clamp(median + int(line[i]), 0, hi))
    elif img.nPlanes == 1:
      let at = img.planeW * row + col
      for i in 0 ..< n: o[at + i] = uint16(clamp(median + int(line[i]), 0, hi))

proc convertRow3(img: Img; row: int) =
  ## A row of the four planes in their colors (encType 3) as the mosaic's.
  let size = img.planeW * img.planeH
  let p0 = row * img.planeW
  let median = (1 shl (img.medianBits - 1)) shl 10
  let hi = (1 shl img.medianBits) - 1
  let at = 4 * img.planeW * row
  let o = img.outp
  for i in 0 ..< img.planeW:
    let a = int(img.planeBuf[p0 + i])
    let b = int(img.planeBuf[p0 + size + i])
    let c = int(img.planeBuf[p0 + 2 * size + i])
    let d = int(img.planeBuf[p0 + 3 * size + i])
    var gr = median + (a shl 10) - 168 * b - 585 * d
    gr = if gr < 0: -(((abs(gr) + 512) shr 9) and not 1) else: ((abs(gr) + 512) shr 9) and not 1
    o[img.outOff[0] + at + 2 * i] = uint16(clamp((median + (a shl 10) + 1510 * d + 512) shr 10, 0, hi))
    o[img.outOff[1] + at + 2 * i] = uint16(clamp((c + gr + 1) shr 1, 0, hi))
    o[img.outOff[2] + at + 2 * i] = uint16(clamp((gr - c + 1) shr 1, 0, hi))
    o[img.outOff[3] + at + 2 * i] = uint16(clamp((median + (a shl 10) + 1927 * b + 512) shr 10, 0, hi))

proc decodePlane(img: Img; plane: int): bool =
  var imageRow = 0
  for tRow in 0 ..< img.tileRows:
    var imageCol = 0
    for tCol in 0 ..< img.tileCols:
      template tile: untyped = img.tiles[tRow * img.tileCols + tCol]
      template c: untyped = tile.comps[plane]
      img.setupComp(tile, c, tile.dataOffset + tile.qpSize + tile.extraSize + c.dataOffset)
      let q = if tile.qStep.len > 0: addr tile.qStep[0] else: nil
      if img.levels > 0:
        if not c.filterInit(img.levels, q): return false
        for i in 0 ..< tile.height:
          if not c.filterDecode(img.levels - 1, q) or not c.filterTransform(img.levels - 1): return false
          img.convertLine(imageRow + i, imageCol, plane, c.getLine(img.levels - 1), tile.width)
      else:
        if c.bands[0].dataSize == 0:
          # (as LibRaw: the rest of the plane left as it is)
          return true
        for i in 0 ..< tile.height:
          if not c.bands[0].param.nextLine(c.bands[0].buf): return false
          img.convertLine(imageRow + i, imageCol, plane, c.bands[0].buf, tile.width)
      c.arena = @[]
      c.params = @[]
      c.wt = @[]
      imageCol += tile.width
    imageRow += img.tiles[tRow * img.tileCols].height
  true

proc decodeCrx*(data: string; h: CrxHeader; at, size: int): seq[uint16] =
  ## The sensor's numbers (`h.height` rows of `h.width`) of the picture
  ## coded in the `size` bytes at `at` (a track's sample), as LibRaw reads
  ## them. Raises `RawError` when it is damaged or cut short.
  if at < 0 or size < h.mdatHdrSize or at + h.mdatHdrSize > data.len: bad("the file ends early")
  if h.width * h.height > 400_000_000 or h.width <= 0 or h.height <= 0: bad("a CR3 picture of a size we do not read")
  var w = h.width
  var hh = h.height
  var tw = h.tileW
  var th = h.tileH
  if h.nPlanes == 4:
    w = w shr 1
    hh = hh shr 1
    tw = tw shr 1
    th = th shr 1
  let img = Img(p: cast[U8](unsafeAddr data[0]), n: data.len, version: h.version, nPlanes: h.nPlanes,
                planeW: w, planeH: hh, nBits: h.nBits, encType: h.encType, levels: h.levels,
                bandCount: 3 * h.levels + 1, medianBits: h.medianBits)
  if tw < 0x16 or th < 0x16 or w > 0x7FFF or hh > 0x7FFF: bad("a CR3 picture coded in a way we do not read")
  img.tileCols = (w + tw - 1) div tw
  img.tileRows = (hh + th - 1) div th
  if img.tileCols > 0xFF or img.tileRows > 0xFF or w - tw * (img.tileCols - 1) < 0x16 or
     hh - th * (img.tileRows - 1) < 0x16:
    bad("a CR3 picture coded in a way we do not read")
  img.mdatOffset = at + h.mdatHdrSize
  img.imageHeaders(tw, th, at, h.mdatHdrSize)
  # (all the data in the file)
  for t in img.tiles:
    if t.hasQP and img.mdatOffset + t.dataOffset + t.qpSize > data.len: bad("the file ends early")
    for c in t.comps:
      for b in c.bands:
        let start = img.mdatOffset + t.dataOffset + t.qpSize + t.extraSize + c.dataOffset + b.dataOffset
        if b.dataSize < 0 or b.width < 0 or b.height < 0 or start + b.dataSize > data.len:
          bad("the file ends early")
  result = newSeq[uint16](h.width * h.height)
  img.outp = cast[ptr UncheckedArray[uint16]](addr result[0])
  if img.encType == 3 and img.nPlanes == 4 and img.nBits > 8:
    img.planeBuf = newSeq[int16](w * hh * 4)
  let row = 2 * w
  img.outOff = case h.cfaLayout
               of 1: [1, 0, row + 1, row]
               of 2: [row, row + 1, 0, 1]
               of 3: [row + 1, row, 1, 0]
               else: [0, 1, row, row + 1]
  if img.nPlanes == 1: img.outOff = [0, 0, 0, 0]
  var ok = [true, true, true, true]
  parallelFor(img.nPlanes, proc (lo, hi: int) {.closure.} =
    for plane in lo ..< hi:
      ok[plane] = img.decodePlane(plane))
  for plane in 0 ..< img.nPlanes:
    if not ok[plane]: bad("a damaged CR3 picture")
  if img.encType == 3 and img.planeBuf.len > 0:
    parallelRows(img.planeH, y):
      img.convertRow3(y)

{.pop.}
