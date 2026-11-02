## 32 bits a channel, as Photoshop's: the light of a picture kept as it is
## (floating point, linear, 1 the white of the screen and more brighter) --
## from Merge to HDR, a Radiance (.hdr) or PFM file, or Image > Mode > 32
## Bits/Channel -- shown at an exposure and gamma (View > 32-bit Preview
## Options), and brought down to 8 or 16 bits by HDR Toning.
##
## Each layer keeps its light in `Layer.hdr` while `Layer.px` is what is
## shown (and what the tools edit, as at 16 bits): a layer edited since is
## its 8 bits made light again.
##
## ```nim
## d.toHdr()                          # Image > Mode > 32 Bits/Channel
## d.setExposure(1.5, 1.0)            # shown 1.5 stops brighter
## d.toneMap(16, tmHighlights, 0, 1)  # HDR Toning down to 16 bits
## writeFile("sky.hdr", writeHdr(w, h, d.flattenedHdr))
## ```

import std/[math, strutils]
import gfx, photo, parallel

{.push boundChecks: off, overflowChecks: off.}

# ---- light and the screen's numbers --------------------------------------------------------------------

proc srgbToLinear*(v: float): float {.inline.} =
  ## A screen (sRGB) value 0 .. 1 as light.
  if v <= 0.04045: v / 12.92 else: pow((v + 0.055) / 1.055, 2.4)

proc linearToSrgb*(v: float): float {.inline.} =
  ## Light 0 .. 1 as a screen (sRGB) value.
  if v <= 0.0031308: v * 12.92 else: 1.055 * pow(v, 1 / 2.4) - 0.055

var toLinear8: array[256, float32]
var toScreen12: array[4097, uint8]
for i in 0 .. 255: toLinear8[i] = float32(srgbToLinear(i / 255))
for i in 0 .. 4096: toScreen12[i] = uint8(clamp(int(linearToSrgb(i / 4096) * 255 + 0.5), 0, 255))

proc screen8(v: float32): int {.inline.} =
  ## (light 0 .. 1 as 0 .. 255 on the screen: by a table)
  if v <= 0: 0
  elif v >= 1: 255
  else: int(toScreen12[int(v * 4096 + 0.5)])

template fp(s: seq[float32]): ptr UncheckedArray[float32] =
  cast[ptr UncheckedArray[float32]](unsafeAddr s[0])
template up(s: seq[uint32]): ptr UncheckedArray[uint32] =
  cast[ptr UncheckedArray[uint32]](unsafeAddr s[0])

proc lightOf*(px: seq[uint32]): seq[float32] =
  ## 8-bit pixels as light (R G B A, alpha 0 .. 1).
  result = newSeqUninit[float32](px.len * 4)
  if px.len == 0: return
  let s = up(px)
  let o = fp(result)
  parallelRows((px.len + 4095) div 4096, b):
    for i in b * 4096 ..< min(px.len, b * 4096 + 4096):
      let p = s[i]
      o[4 * i] = toLinear8[(p shr 16) and 255]
      o[4 * i + 1] = toLinear8[(p shr 8) and 255]
      o[4 * i + 2] = toLinear8[p and 255]
      o[4 * i + 3] = float32(p shr 24) / 255

proc lightOf16*(hi: seq[uint16]): seq[float32] =
  ## 16-bit pixels (R G B A) as light.
  result = newSeqUninit[float32](hi.len)
  let n = hi.len div 4
  let o = fp(result)
  let s = cast[ptr UncheckedArray[uint16]](unsafeAddr hi[0])
  parallelRows((n + 4095) div 4096, b):
    for i in b * 4096 ..< min(n, b * 4096 + 4096):
      for c in 0 .. 2: o[4 * i + c] = float32(srgbToLinear(s[4 * i + c].float / 65535))
      o[4 * i + 3] = float32(s[4 * i + 3]) / 65535

proc shownAt*(light: seq[float32]; exposure = 0.0; gamma = 1.0): seq[uint32] =
  ## Light shown at an `exposure` (stops) and `gamma`: 8-bit pixels.
  let n = light.len div 4
  result = newSeqUninit[uint32](n)
  if n == 0: return
  let k = float32(pow(2.0, exposure))
  let g = if gamma <= 0: 1.0 else: gamma
  let s = fp(light)
  let o = up(result)
  parallelRows((n + 4095) div 4096, b):
    for i in b * 4096 ..< min(n, b * 4096 + 4096):
      var c: array[3, int]
      for ch in 0 .. 2:
        var v = s[4 * i + ch] * k
        if g != 1.0 and v > 0: v = float32(pow(v.float, 1 / g))
        c[ch] = screen8(v)
      o[i] = argb(clamp(int(s[4 * i + 3] * 255 + 0.5), 0, 255), c[0], c[1], c[2])

# ---- the document at 32 bits ------------------------------------------------------------------------------

proc shownPixel(s: ptr UncheckedArray[float32]; i: int; k: float32; g: float): uint32 {.inline.} =
  var c: array[3, int]
  for ch in 0 .. 2:
    var v = s[4 * i + ch] * k
    if g != 1.0 and v > 0: v = float32(pow(v.float, 1 / g))
    c[ch] = screen8(v)
  argb(clamp(int(s[4 * i + 3] * 255 + 0.5), 0, 255), c[0], c[1], c[2])

proc syncHdr*(d: Doc; L: Layer) =
  ## The layer's light made to agree with what is shown: each pixel a tool
  ## changed at 8 bits (no longer its light shown at the document's
  ## exposure) gets its light from what is shown; the others keep theirs.
  if not d.hdrValid(L): return
  let k = float32(pow(2.0, d.exposure))
  let g = if d.viewGamma <= 0: 1.0 else: d.viewGamma
  let s = fp(L.hdr)
  let p = up(L.px)
  let n = L.px.len
  parallelRows((n + 4095) div 4096, b):
    for i in b * 4096 ..< min(n, b * 4096 + 4096):
      let q = p[i]
      if shownPixel(s, i, k, g) == q: continue
      for ch in 0 .. 2:
        var v = toLinear8[(q shr (16 - 8 * ch)) and 255].float
        if g != 1.0 and v > 0: v = pow(v, g)
        s[4 * i + ch] = float32(v) / k
      s[4 * i + 3] = float32(q shr 24) / 255

proc hdrPixels*(d: Doc; L: Layer): seq[float32] =
  ## The layer's light: its own, where a tool changed it at 8 bits since
  ## what is shown made light.
  if d.hdrValid(L):
    d.syncHdr(L)
    return L.hdr
  if d.hiValid(L): return lightOf16(d.hiPixels(L))
  lightOf(L.px)

proc showLight(d: Doc; L: Layer) =
  ## (a layer's pixels from its light, at the document's exposure)
  L.px = shownAt(L.hdr, d.exposure, (if d.viewGamma <= 0: 1.0 else: d.viewGamma))
  inc L.ver
  L.hdrVer = L.ver

proc showLightIn*(d: Doc; L: Layer; r: Rect) =
  ## After the light of `r` was worked on: what is shown there made from it.
  let c = d.clip(r)
  if c.w <= 0 or c.h <= 0 or not d.hdrValid(L): return
  let k = float32(pow(2.0, d.exposure))
  let g = if d.viewGamma <= 0: 1.0 else: d.viewGamma
  let s = fp(L.hdr)
  let o = up(L.px)
  let w = d.w
  parallelRows(c.h, y):
    for x in c.x ..< c.x + c.w:
      let i = (c.y + y) * w + x
      o[i] = shownPixel(s, i, k, g)
  inc L.ver
  d.markDirty(c)

proc hdrToPx*(d: Doc; L: Layer) =
  ## After the light was worked on: what is shown made from it.
  if d.hdrValid(L) or (L.hdr.len == d.w * d.h * 4):
    d.showLight(L)
    d.markAll()

proc toHdr*(d: Doc) =
  ## Image > Mode > 32 Bits/Channel: each layer's light made from its 8 (or
  ## 16) bits; shown as it was.
  if d.depth == 32: return
  for L in d.layers:
    if L.group or L.px.len != d.w * d.h: continue
    L.hdr = d.hdrPixels(L)
    L.hdrVer = L.ver
  d.setDepth(32)
  for L in d.layers:
    if L.hdr.len > 0: L.hdrVer = L.ver
  d.exposure = 0
  d.viewGamma = 1

proc setExposure*(d: Doc; exposure: float; gamma = 1.0) =
  ## View > 32-bit Preview Options: the light shown `exposure` stops brighter
  ## (darker when less than 0), at `gamma`. The light itself is unchanged.
  if d.depth == 32:
    for L in d.layers: d.syncHdr(L)       # (tools' changes kept as light first)
  d.exposure = clamp(exposure, -20.0, 20.0)
  d.viewGamma = clamp(gamma, 0.1, 10.0)
  if d.depth != 32: return
  for L in d.layers:
    if d.hdrValid(L): d.showLight(L)
  d.markAll()

proc docFromLight*(w, h: int; light: sink seq[float32]; name = "Untitled"; dpi = 72.0): Doc =
  ## A 32-bit document of one layer from its light (a Radiance or PFM file,
  ## Merge to HDR).
  result = newDoc(w, h, 0, dpi = dpi, name = name)
  let L = result.layer
  L.hdr = light
  result.depth = 32
  result.exposure = 0
  result.viewGamma = 1
  result.showLight(L)
  result.markAll()

proc flattenedHdr*(d: Doc): seq[float32] =
  ## The image's light (R G B A): one visible normal layer with its light
  ## kept: that; else what is shown made light again.
  var only: Layer
  var n = 0
  for L in d.layers:
    if L.visible and not L.group:
      inc n
      only = L
  if n == 1 and only.opacity == 100 and only.mode == bmNormal and only.mask == nil and not only.hasFx and
     only.adjust.kind.len == 0 and d.hdrValid(only):
    return d.hdrPixels(only)              # (the light, whatever it is shown at)
  d.updateComposite()
  let k = float32(pow(2.0, -d.exposure))  # (the exposure taken back off)
  result = lightOf(d.compCopy)
  if k != 1:
    let o = fp(result)
    let m = d.w * d.h
    parallelRows((m + 4095) div 4096, b):
      for i in b * 4096 ..< min(m, b * 4096 + 4096):
        for c in 0 .. 2: o[4 * i + c] *= k

type ToneMethod* = enum
  ## HDR Toning's ways down to 8 or 16 bits.
  tmExposure = "Exposure and Gamma", tmHighlights = "Highlight Compression",
  tmEqualize = "Equalize Histogram", tmLocal = "Local Adaptation"

proc toneValue(v, white: float; m: ToneMethod): float {.inline.} =
  case m
  of tmHighlights: v * (1 + v / (white * white)) / (1 + v)       # (Reinhard, its white kept white)
  else: v

proc toneMap*(d: Doc; bits: int; m = tmHighlights; exposure = 0.0; gamma = 1.0; detail = 30.0) =
  ## Image > Mode > 8 or 16 Bits/Channel from 32 (HDR Toning): each layer's
  ## light brought into what a screen and paper show -- by an exposure and
  ## gamma, by compressing the highlights (nothing burnt out), by its
  ## histogram, or locally (the shadows lifted, the lights kept, `detail`
  ## %). The light is let go.
  if d.depth != 32: return
  let k = pow(2.0, exposure)
  let g = if gamma <= 0: 1.0 else: gamma
  for L in d.layers:
    if L.group or L.px.len != d.w * d.h: continue
    var light = d.hdrPixels(L)
    let n = d.w * d.h
    let s = fp(light)
    # (the brightest: the white of Highlight Compression; the order of the
    # lightness for Equalize Histogram)
    var white = 1.0
    var cdf: seq[float]
    if m == tmHighlights:
      for i in 0 ..< n:
        white = max(white, max(s[4 * i], max(s[4 * i + 1], s[4 * i + 2])).float * k)
    if m == tmEqualize:
      var hist = newSeq[int](1024)
      for i in 0 ..< n:
        let l = (s[4 * i] * 0.2126 + s[4 * i + 1] * 0.7152 + s[4 * i + 2] * 0.0722).float * k
        hist[clamp(int(log2(max(l, 1e-6)) * 40 + 600), 0, 1023)] += 1
      cdf = newSeq[float](1024)
      var acc = 0
      for i in 0 ..< 1024:
        acc += hist[i]
        cdf[i] = acc / max(1, n)
    var blurL: seq[float32]
    if m == tmLocal:
      # (the lightness round each pixel, in stops: what it is seen against)
      blurL = newSeqUninit[float32](n)
      let bp = fp(blurL)
      for i in 0 ..< n:
        bp[i] = float32(log2(max(1e-4, (s[4 * i] * 0.2126 + s[4 * i + 1] * 0.7152 + s[4 * i + 2] * 0.0722).float * k)))
      let r = max(2, int(max(d.w, d.h).float / 60))
      for pass in 0 ..< 3:
        var tmp = newSeq[float32](n)
        let tp = fp(tmp)
        let w = d.w
        let h = d.h
        parallelRows(h, y):
          var acc = 0'f32
          for x in -r .. r: acc += bp[y * w + clamp(x, 0, w - 1)]
          for x in 0 ..< w:
            tp[y * w + x] = acc / float32(2 * r + 1)
            acc += bp[y * w + min(w - 1, x + r + 1)] - bp[y * w + max(0, x - r)]
        parallelRows(w, x):
          var acc = 0'f32
          for y in -r .. r: acc += tp[clamp(y, 0, h - 1) * w + x]
          for y in 0 ..< h:
            bp[y * w + x] = acc / float32(2 * r + 1)
            acc += tp[min(h - 1, y + r + 1) * w + x] - tp[max(0, y - r) * w + x]
    let bp = if blurL.len > 0: fp(blurL) else: nil
    let dt = clamp(detail / 100, 0.0, 1.0)
    var mean = 0.0
    if bp != nil:
      for i in 0 ..< n: mean += bp[i].float
      mean /= max(1, n).float
    var px8 = newSeqUninit[uint32](n)
    var hi = if bits >= 16: newSeqUninit[uint16](n * 4) else: newSeq[uint16]()
    let o8 = up(px8)
    let oh = if hi.len > 0: cast[ptr UncheckedArray[uint16]](addr hi[0]) else: nil
    let cp = if cdf.len > 0: cast[ptr UncheckedArray[float]](addr cdf[0]) else: nil
    parallelRows((n + 4095) div 4096, b):
      for i in b * 4096 ..< min(n, b * 4096 + 4096):
        var c: array[3, float]
        let l = (s[4 * i] * 0.2126 + s[4 * i + 1] * 0.7152 + s[4 * i + 2] * 0.0722).float * k
        var scale = 1.0
        if cp != nil:
          let t = cp[clamp(int(log2(max(l, 1e-6)) * 40 + 600), 0, 1023)]
          scale = if l > 1e-6: srgbToLinear(t) / l else: 0.0
        elif bp != nil:
          # (the stops round it pulled toward the middle gray, its own
          # detail kept -- more of it with `detail`)
          let around = bp[i].float
          let target = (around - mean) * 0.55 + (log2(max(l, 1e-4)) - around) * (1 + dt) + log2(0.18)
          scale = pow(2.0, target) / max(l, 1e-4)
        for ch in 0 .. 2:
          var v = s[4 * i + ch].float * k * scale
          if bp == nil and cp == nil: v = toneValue(v, white, m)
          if g != 1.0 and v > 0: v = pow(v, 1 / g)
          c[ch] = clamp(linearToSrgb(clamp(v, 0.0, 1.0)), 0.0, 1.0)
        let a = clamp(s[4 * i + 3].float, 0.0, 1.0)
        o8[i] = argb(int(a * 255 + 0.5), int(c[0] * 255 + 0.5), int(c[1] * 255 + 0.5), int(c[2] * 255 + 0.5))
        if oh != nil:
          for ch in 0 .. 2: oh[4 * i + ch] = uint16(c[ch] * 65535 + 0.5)
          oh[4 * i + 3] = uint16(a * 65535 + 0.5)
    L.px = move px8
    inc L.ver
    L.hdr = @[]
    L.hdrVer = 0
    if hi.len > 0: d.setHi(L, move hi)
  d.setDepth(if bits >= 16: 16 else: 8)
  d.exposure = 0
  d.viewGamma = 1
  d.markAll()

# ---- Radiance (.hdr) and PFM files -------------------------------------------------------------------------

proc readHdr*(data: string): tuple[w, h: int; light: seq[float32]] =
  ## A Radiance picture (.hdr, RGBE, flat or run-length packed) as light.
  ## Raises `ValueError` when it is not one.
  if not (data.startsWith("#?RADIANCE") or data.startsWith("#?RGBE")):
    raise newException(ValueError, "not a Radiance picture")
  var i = 0
  var line = ""
  # (the header, to an empty line; then the size line)
  while i < data.len:
    let e = data.find('\n', i)
    if e < 0: raise newException(ValueError, "no picture in it")
    line = data[i ..< e]
    i = e + 1
    if line.len == 0: break
  let e = data.find('\n', i)
  if e < 0: raise newException(ValueError, "no size")
  let parts = data[i ..< e].splitWhitespace
  i = e + 1
  if parts.len != 4 or parts[0] != "-Y" or parts[2] != "+X": raise newException(ValueError, "an orientation not read")
  let h = parseInt(parts[1])
  let w = parseInt(parts[3])
  if w <= 0 or h <= 0 or w > 30000 or h > 30000: raise newException(ValueError, "too big")
  var rgbe = newSeq[uint8](w * h * 4)
  var scan = newSeq[uint8](w * 4)
  for y in 0 ..< h:
    if i + 4 <= data.len and data[i] == '\x02' and data[i + 1] == '\x02' and (ord(data[i + 2]) and 0x80) == 0 and
       (ord(data[i + 2]) shl 8 or ord(data[i + 3])) == w and w >= 8 and w < 32768:
      # (run-length packed: each component in turn)
      i += 4
      for c in 0 .. 3:
        var x = 0
        while x < w:
          if i >= data.len: raise newException(ValueError, "cut short")
          var n = ord(data[i])
          inc i
          if n > 128:
            n -= 128
            if i >= data.len or x + n > w: raise newException(ValueError, "damaged")
            let v = uint8(ord(data[i]))
            inc i
            for k in 0 ..< n: scan[(x + k) * 4 + c] = v
            x += n
          else:
            if n == 0 or x + n > w or i + n > data.len: raise newException(ValueError, "damaged")
            for k in 0 ..< n: scan[(x + k) * 4 + c] = uint8(ord(data[i + k]))
            i += n
            x += n
    else:
      if i + w * 4 > data.len: raise newException(ValueError, "cut short")
      for k in 0 ..< w * 4: scan[k] = uint8(ord(data[i + k]))
      i += w * 4
    copyMem(addr rgbe[y * w * 4], addr scan[0], w * 4)
  result.w = w
  result.h = h
  result.light = newSeqUninit[float32](w * h * 4)
  for p in 0 ..< w * h:
    let ex = int(rgbe[4 * p + 3])
    let f = if ex == 0: 0.0 else: pow(2.0, float(ex - 136))
    for c in 0 .. 2: result.light[4 * p + c] = float32((rgbe[4 * p + c].float + 0.5) * f)
    result.light[4 * p + 3] = 1

proc writeHdr*(w, h: int; light: openArray[float32]): string =
  ## Light as a Radiance picture (.hdr, RGBE, run-length packed).
  result = "#?RADIANCE\nFORMAT=32-bit_rle_rgbe\nSOFTWARE=Retro Nim UI\n\n-Y " & $h & " +X " & $w & "\n"
  var scan = newSeq[uint8](w * 4)
  for y in 0 ..< h:
    for x in 0 ..< w:
      let i = (y * w + x) * 4
      let r = light[i].float
      let g = light[i + 1].float
      let b = light[i + 2].float
      let m = max(r, max(g, b))
      if m < 1e-32:
        for c in 0 .. 3: scan[x * 4 + c] = 0
      else:
        var ex: int
        let f = frexp(m, ex)
        let k = f * 256 / m
        scan[x * 4] = uint8(clamp(int(r * k), 0, 255))
        scan[x * 4 + 1] = uint8(clamp(int(g * k), 0, 255))
        scan[x * 4 + 2] = uint8(clamp(int(b * k), 0, 255))
        scan[x * 4 + 3] = uint8(clamp(ex + 128, 0, 255))
    if w >= 8 and w < 32768:
      result.add char(2); result.add char(2); result.add char(w shr 8); result.add char(w and 255)
      for c in 0 .. 3:
        var x = 0
        while x < w:
          # (a run of 3 or more the same: packed; else plain bytes)
          var run = 1
          while x + run < w and run < 127 and scan[(x + run) * 4 + c] == scan[x * 4 + c]: inc run
          if run >= 3:
            result.add char(128 + run)
            result.add char(scan[x * 4 + c])
            x += run
          else:
            var n = 0
            while x + n < w and n < 128:
              if x + n + 2 < w and scan[(x + n) * 4 + c] == scan[(x + n + 1) * 4 + c] and
                 scan[(x + n) * 4 + c] == scan[(x + n + 2) * 4 + c]: break
              inc n
            n = max(1, n)
            result.add char(n)
            for k in 0 ..< n: result.add char(scan[(x + k) * 4 + c])
            x += n
    else:
      for k in 0 ..< w * 4: result.add char(scan[k])

proc readPfm*(data: string): tuple[w, h: int; light: seq[float32]] =
  ## A PFM picture (Portable Float Map: "PF" color, "Pf" gray) as light.
  if data.len < 3 or data[0] != 'P' or data[1] notin {'F', 'f'}: raise newException(ValueError, "not a PFM picture")
  let color = data[1] == 'F'
  var toks: seq[string]
  var i = 2
  while toks.len < 3 and i < data.len:
    while i < data.len and data[i] in Whitespace: inc i
    var t = ""
    while i < data.len and data[i] notin Whitespace:
      t.add data[i]
      inc i
    if t.len > 0: toks.add t
  inc i                                   # (the one white space after the scale)
  if toks.len < 3: raise newException(ValueError, "no size")
  let w = parseInt(toks[0])
  let h = parseInt(toks[1])
  let scale = parseFloat(toks[2])
  if w <= 0 or h <= 0 or w > 30000 or h > 30000: raise newException(ValueError, "too big")
  let ch = if color: 3 else: 1
  if i + w * h * ch * 4 > data.len: raise newException(ValueError, "cut short")
  let little = scale < 0
  result.w = w
  result.h = h
  result.light = newSeqUninit[float32](w * h * 4)
  for y in 0 ..< h:
    let row = h - 1 - y                   # (bottom row first)
    for x in 0 ..< w:
      for c in 0 ..< ch:
        let at = i + ((y * w + x) * ch + c) * 4
        var b: array[4, uint8]
        for k in 0 .. 3: b[k] = uint8(ord(data[at + (if little: k else: 3 - k)]))
        let v = cast[float32](b)
        let o = (row * w + x) * 4
        if color: result.light[o + c] = v
        else:
          for cc in 0 .. 2: result.light[o + cc] = v
      result.light[(row * w + x) * 4 + 3] = 1

proc writePfm*(w, h: int; light: openArray[float32]): string =
  ## Light as a PFM picture (color, little-endian floats).
  result = "PF\n" & $w & " " & $h & "\n-1.0\n"
  let at = result.len
  result.setLen(at + w * h * 12)
  var k = at
  for y in countdown(h - 1, 0):
    for x in 0 ..< w:
      for c in 0 .. 2:
        var v = light[(y * w + x) * 4 + c]
        copyMem(addr result[k], addr v, 4)
        k += 4

{.pop.}

syncHdrHook = syncHdr
showHdrHook = proc (d: Doc; L: Layer) {.nimcall.} = d.showLight(L)
