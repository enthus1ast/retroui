## Animated GIF pictures: `loadGif` decodes every frame (composited the
## way browsers show them: disposal, transparency, interlacing) into
## Bitmaps with their delays. Used by `retro/media` (the `animation`
## widget); safe with broken or hostile files: sizes are capped, a damaged
## frame ends the animation where it breaks, nothing reads out of bounds.

import gfx

type
  GifFrame* = tuple[image: Bitmap; delayMs: int]
    ## One frame of an animation: the whole picture, and how long it shows.

const
  MaxGifSide* = 4096          ## wider or taller GIFs are refused
  MaxGifFrames* = 2000        ## frames after these are left out
  MaxGifPixels* = 32_000_000  ## pixels of all frames together (memory cap)

type Reader = object
  data: ptr UncheckedArray[uint8]
  len, pos: int

proc u8(r: var Reader): int =
  if r.pos >= r.len: raise newException(ValueError, "GIF: cut short")
  result = int(r.data[r.pos])
  inc r.pos

proc u16(r: var Reader): int =
  let lo = r.u8
  lo or (r.u8 shl 8)

proc skipBlocks(r: var Reader) =
  ## Data sub-blocks up to their 0 terminator.
  while true:
    let n = r.u8
    if n == 0: return
    if r.pos + n > r.len: raise newException(ValueError, "GIF: cut short")
    r.pos += n

proc readTable(r: var Reader; n: int): seq[uint32] =
  if r.pos + 3 * n > r.len: raise newException(ValueError, "GIF: cut short")
  result = newSeq[uint32](n)
  for i in 0 ..< n:
    let p = r.pos + 3 * i
    result[i] = 0xFF000000'u32 or (uint32(r.data[p]) shl 16) or
                (uint32(r.data[p + 1]) shl 8) or uint32(r.data[p + 2])
  r.pos += 3 * n

proc lzw(r: var Reader; minCode: int; outBuf: var seq[uint8]; need: int): int =
  ## Decodes the image data into `outBuf` (color indices); returns how
  ## many came (less than `need` when the data is damaged or short).
  if minCode < 2 or minCode > 8:
    r.skipBlocks()
    return 0
  var prefix: array[4096, int16]
  var suffix, first: array[4096, uint8]
  var stack: array[4097, uint8]
  let clear = 1 shl minCode
  let eoi = clear + 1
  for i in 0 ..< clear:
    prefix[i] = -1
    suffix[i] = uint8(i)
    first[i] = uint8(i)
  var codeSize = minCode + 1
  var next = eoi + 1
  var prev = -1
  var bits = 0'u32
  var nbits = 0
  var done = false
  var n = 0
  while true:
    let blockLen = r.u8
    if blockLen == 0: break
    if r.pos + blockLen > r.len: raise newException(ValueError, "GIF: cut short")
    let blockEnd = r.pos + blockLen
    while r.pos < blockEnd:
      bits = bits or (uint32(r.data[r.pos]) shl nbits)
      inc r.pos
      nbits += 8
      while nbits >= codeSize and not done:
        let code = int(bits and ((1'u32 shl codeSize) - 1))
        bits = bits shr codeSize
        nbits -= codeSize
        if code == clear:
          codeSize = minCode + 1
          next = eoi + 1
          prev = -1
          continue
        if code == eoi:
          done = true
          break
        var c: int
        if prev < 0:
          if code >= clear:
            done = true                      # (a damaged stream: stop)
            break
          c = code
        elif code < next:
          c = code
          if next < 4096:
            prefix[next] = int16(prev)
            suffix[next] = first[code]
            first[next] = first[prev]
            inc next
        elif code == next and next < 4096:
          prefix[next] = int16(prev)
          suffix[next] = first[prev]
          first[next] = first[prev]
          inc next
          c = code
        else:
          done = true
          break
        # the string of `c`, last character first
        var sp = 0
        var k = c
        while k >= 0 and sp < stack.len:
          stack[sp] = suffix[k]
          inc sp
          k = if k < clear: -1 else: int(prefix[k])
        while sp > 0 and n < need:
          dec sp
          outBuf[n] = stack[sp]
          inc n
        if next >= (1 shl codeSize) and codeSize < 12: inc codeSize
        prev = code
    if done:
      r.pos = blockEnd
      r.skipBlocks()
      break
  n

proc isGif*(data: string): bool =
  ## `data` starts like a GIF file.
  data.len >= 6 and data[0 .. 5] in ["GIF87a", "GIF89a"]

proc loadGif*(data: string): seq[GifFrame] =
  ## Every frame of the GIF in `data`, each a whole picture (0xAARRGGBB,
  ## transparent where nothing was drawn yet), with its delay in
  ## milliseconds (very short delays become 100 ms, as browsers do). A
  ## still GIF gives one frame. Raises `ValueError` when `data` is not a
  ## GIF or no frame could be read; a frame damaged later on ends the list.
  if not isGif(data): raise newException(ValueError, "not a GIF")
  var r = Reader(data: cast[ptr UncheckedArray[uint8]](unsafeAddr data[0]), len: data.len, pos: 6)
  let w = r.u16
  let h = r.u16
  if w <= 0 or h <= 0 or w > MaxGifSide or h > MaxGifSide:
    raise newException(ValueError, "GIF: bad size")
  let packed = r.u8
  discard r.u8                             # background color index
  discard r.u8                             # aspect ratio
  var globalTable: seq[uint32]
  if (packed and 0x80) != 0:
    globalTable = r.readTable(1 shl ((packed and 7) + 1))
  var canvas = newSeq[uint32](w * h)
  var delay = 100
  var transparent = -1
  var disposal = 0
  var total = 0
  var indices: seq[uint8]
  try:
    while r.pos < r.len:
      case r.u8
      of 0x21:                             # an extension
        let label = r.u8
        if label == 0xF9:                  # graphic control
          let n = r.u8
          if n >= 4 and r.pos + n <= r.len:
            let p = int(r.data[r.pos])
            disposal = (p shr 2) and 7
            let d = int(r.data[r.pos + 1]) or (int(r.data[r.pos + 2]) shl 8)
            delay = if d <= 1: 100 else: d * 10
            transparent = if (p and 1) != 0: int(r.data[r.pos + 3]) else: -1
            r.pos += n
          elif r.pos + n <= r.len: r.pos += n
          else: raise newException(ValueError, "GIF: cut short")
          r.skipBlocks()
        else: r.skipBlocks()
      of 0x2C:                             # an image
        let fx = r.u16
        let fy = r.u16
        let fw = r.u16
        let fh = r.u16
        let ip = r.u8
        var table = globalTable
        if (ip and 0x80) != 0: table = r.readTable(1 shl ((ip and 7) + 1))
        let minCode = r.u8
        if fw <= 0 or fh <= 0 or fw > MaxGifSide or fh > MaxGifSide:
          r.skipBlocks()
          continue
        let need = fw * fh
        if indices.len < need: indices.setLen(need)
        let got = lzw(r, minCode, indices, need)
        if total + w * h > MaxGifPixels or result.len >= MaxGifFrames: break
        let saved = if disposal == 3: canvas else: @[]
        # the rows, in interlaced order when the frame says so
        var rowOf = newSeq[int](fh)
        if (ip and 0x40) != 0:
          var k = 0
          for (start, step) in [(0, 8), (4, 8), (2, 4), (1, 2)]:
            var y = start
            while y < fh:
              rowOf[k] = y
              inc k
              y += step
        else:
          for y in 0 ..< fh: rowOf[y] = y
        for i in 0 ..< min(got, need):
          let ci = int(indices[i])
          if ci == transparent or ci >= table.len: continue
          let x = fx + i mod fw
          let y = fy + rowOf[i div fw]
          if x < w and y < h: canvas[y * w + x] = table[ci]
        let b = newBitmap(w, h)
        b.px = canvas
        b.changed()
        result.add (b, delay)
        total += w * h
        # what is left for the next frame
        case disposal
        of 2:
          for y in max(0, fy) ..< min(h, fy + fh):
            for x in max(0, fx) ..< min(w, fx + fw): canvas[y * w + x] = 0
        of 3:
          if saved.len == canvas.len: canvas = saved
        else: discard
        delay = 100
        transparent = -1
        disposal = 0
        if got < need: break               # damaged: end here
      of 0x3B: break                       # the end
      else: break                          # not a block: end here
  except ValueError:
    if result.len == 0: raise
  if result.len == 0: raise newException(ValueError, "GIF: no picture in it")
