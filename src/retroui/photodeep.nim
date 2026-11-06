## Working at 16 and 32 bits a channel, as Photoshop does: a filter or an
## adjustment that knows how (`withHi` in `photofx`: Levels, Curves, every
## change of each pixel by itself, the blurs, sharpening, High Pass) is
## done on a layer's 16-bit pixels (`Layer.hi`) or its light (`Layer.hdr`),
## not on its 8 bits; the image is composited at 16 bits for saving (its
## layers, masks, blend modes, opacity and adjustment layers); a gradient
## is drawn at 16 bits. Tools that work at 8 bits still do: the pixels they
## change are taken at 8 bits there (`syncHi`), the others keep theirs.
##
## Importing it is enough: it sets the hooks of `photo` and `photofx`.
##
## ```nim
## import retroui/[photo, photofx, photodeep]
## d.setDepth(16)
## d.applyFilter(0, applyLuts(levelsLut(lv), identityLut(), identityLut(), identityLut()))  # at 16 bits
## let hi = d.flattened16()                    # composited at 16 bits
## ```

import std/math
import gfx, photo, photofx, photohdr, photopaint, parallel

{.push boundChecks: off, overflowChecks: off.}

template f32p(s: seq[float32]): ptr UncheckedArray[float32] =
  cast[ptr UncheckedArray[float32]](if s.len > 0: unsafeAddr s[0] else: nil)
template u16p(s: seq[uint16]): ptr UncheckedArray[uint16] =
  cast[ptr UncheckedArray[uint16]](if s.len > 0: unsafeAddr s[0] else: nil)
template u32p(s: seq[uint32]): ptr UncheckedArray[uint32] =
  cast[ptr UncheckedArray[uint32]](if s.len > 0: unsafeAddr s[0] else: nil)

# ---- tables read between their entries ---------------------------------------------------------------------

proc lutAt(t: ptr Lut; x: float32): float32 {.inline.} =
  ## Table `t` at `x` (0 .. 255, between entries: on the line between them).
  if x <= 0: return float32(t[0])
  if x >= 255: return float32(t[255])
  let i = int(x)
  let f = x - float32(i)
  float32(t[i]) * (1 - f) + float32(t[i + 1]) * f

const LN = 52           # (a change of each pixel: a table of 52 x 52 x 52 colors, 5 levels apart)

proc latticeOf(fn: proc (p: uint32): uint32): seq[float32] =
  ## What each grid color becomes (R G B 0 .. 255 each).
  result = newSeqUninit[float32](LN * LN * LN * 3)
  let o = f32p(result)
  for ri in 0 ..< LN:
    for gi in 0 ..< LN:
      for bi in 0 ..< LN:
        let v = fn(argb(255, ri * 5, gi * 5, bi * 5))
        let k = ((ri * LN + gi) * LN + bi) * 3
        o[k] = float32((v shr 16) and 255)
        o[k + 1] = float32((v shr 8) and 255)
        o[k + 2] = float32(v and 255)

proc latticeAt(t: ptr UncheckedArray[float32]; r, g, b: float32): array[3, float32] {.inline.} =
  ## The table at a color (0 .. 255 each), read between its 8 grid colors.
  let fr = clamp(r, 0'f32, 255'f32) / 5
  let fg = clamp(g, 0'f32, 255'f32) / 5
  let fb = clamp(b, 0'f32, 255'f32) / 5
  let r0 = min(int(fr), LN - 2)
  let g0 = min(int(fg), LN - 2)
  let b0 = min(int(fb), LN - 2)
  let tr = fr - float32(r0)
  let tg = fg - float32(g0)
  let tb = fb - float32(b0)
  template at(i, j, k, c: int): float32 = t[(((r0 + i) * LN + g0 + j) * LN + b0 + k) * 3 + c]
  for c in 0 .. 2:
    let c00 = at(0, 0, 0, c) * (1 - tb) + at(0, 0, 1, c) * tb
    let c01 = at(0, 1, 0, c) * (1 - tb) + at(0, 1, 1, c) * tb
    let c10 = at(1, 0, 0, c) * (1 - tb) + at(1, 0, 1, c) * tb
    let c11 = at(1, 1, 0, c) * (1 - tb) + at(1, 1, 1, c) * tb
    let c0 = c00 * (1 - tg) + c01 * tg
    let c1 = c10 * (1 - tg) + c11 * tg
    result[c] = c0 * (1 - tr) + c1 * tr

# ---- a layer's deep pixels ---------------------------------------------------------------------------------

proc encodeLight(v: float32): float32 {.inline.} =
  ## (light as a screen value: past 1 the rest kept, straight)
  if v <= 1: float32(linearToSrgb(max(0'f32, v).float)) else: v

proc decodeLight(e: float32): float32 {.inline.} =
  if e <= 1: float32(srgbToLinear(max(0'f32, e).float)) else: e

proc readDeep(d: Doc; L: Layer; r: Rect): DeepImg =
  ## `r` of the layer as floats: its 16 bits (0 .. 1), or its light at 32.
  result = DeepImg(w: r.w, h: r.h, px: newSeqUninit[float32](r.w * r.h * 4))
  let o = f32p(result.px)
  let w = d.w
  if d.depth == 32:
    let s = f32p(L.hdr)
    parallelRows(r.h, y):
      copyMem(addr o[y * r.w * 4], addr s[((r.y + y) * w + r.x) * 4], r.w * 16)
  else:
    let s = u16p(L.hi)
    parallelRows(r.h, y):
      let srow = ((r.y + y) * w + r.x) * 4
      for t in 0 ..< r.w * 4: o[y * r.w * 4 + t] = float32(s[srow + t]) * (1'f32 / 65535)

proc writeDeep(d: Doc; L: Layer; r: Rect; o: DeepImg) =
  ## `o` (`r`'s size) put into the layer's deep pixels in `r`: in the
  ## selection, keeping the channels not edited and (Preserve Transparency,
  ## the Background) the alpha; its 8 bits (or what is shown) made again.
  let w = d.w
  let deep32 = d.depth == 32
  let hs = u16p(L.hi)
  let fs = f32p(L.hdr)
  let op = f32p(o.px)
  let keepA = L.lockAlpha or L.background
  let all = d.colorChannelsAll
  let on = d.channelsOn
  let selected = d.sel.len > 0
  let sp = if selected: cast[ptr UncheckedArray[uint8]](unsafeAddr d.sel[0]) else: nil
  parallelRows(r.h, y):
    for x in 0 ..< r.w:
      let i = (r.y + y) * w + r.x + x
      let s = if sp != nil: int(sp[i]) else: 255
      if s == 0: continue
      let t = float32(s) / 255
      let q = (y * r.w + x) * 4
      for c in 0 .. 3:
        if c < 3 and not all and not on[c]: continue
        if c == 3 and keepA: continue
        var after = op[q + c]
        if not deep32 or c == 3: after = clamp(after, 0'f32, 1'f32)
        elif after < 0: after = 0
        if deep32:
          let before = fs[4 * i + c]
          fs[4 * i + c] = before + (after - before) * t
        else:
          let before = float32(hs[4 * i + c]) * (1'f32 / 65535)
          hs[4 * i + c] = uint16(clamp(int((before + (after - before) * t) * 65535 + 0.5), 0, 65535))
  if deep32: d.showLightIn(L, r)
  else: d.hiToPx(L, r)

proc pointDeep(src: DeepImg; inner: Rect; way: HiWay; deep32: bool): DeepImg =
  ## A change of each pixel by itself on floats (through its tables).
  result = DeepImg(w: inner.w, h: inner.h, px: newSeqUninit[float32](inner.w * inner.h * 4))
  let sp = f32p(src.px)
  let op = f32p(result.px)
  var lat: seq[float32]
  var luts: array[4, Lut]
  let useLuts = way.luts.len == 4
  if useLuts:
    for k in 0 .. 3: luts[k] = way.luts[k]
  else: lat = latticeOf(way.point)
  let lp = f32p(lat)
  let lu = cast[ptr array[4, Lut]](addr luts)
  let sw = src.w
  parallelRows(inner.h, y):
    for x in 0 ..< inner.w:
      let si = ((inner.y + y) * sw + inner.x + x) * 4
      let oi = (y * inner.w + x) * 4
      var e: array[3, float32]
      var extra: array[3, float32]
      for c in 0 .. 2:
        let v = sp[si + c]
        let en = if deep32: encodeLight(v) else: v
        extra[c] = max(0'f32, en - 1)
        e[c] = clamp(en, 0'f32, 1'f32) * 255
      var o: array[3, float32]
      if useLuts:
        for c in 0 .. 2:
          o[c] = lutAt(addr lu[0], lutAt(addr lu[c + 1], e[c]))
      else:
        o = latticeAt(lp, e[0], e[1], e[2])
      for c in 0 .. 2:
        let en = o[c] / 255 + extra[c]
        op[oi + c] = if deep32: decodeLight(en) else: en
      op[oi + 3] = sp[si + 3]

proc hiFilter(d: Doc; L: Layer; margin: int; f: FilterFn; r: Rect): bool =
  ## (`photofx`'s hook: `f` at 16 or 32 bits, when it knows how)
  let way = hiWayOf(f)
  if way.point == nil and way.deep == nil: return false
  if L == nil or L.group or L.px.len != d.w * d.h or L == d.maskLayer or L.gray: return false
  if not d.colorChannelsAll and d.mode notin {cmRGB, cmGray}: return false
  if d.depth == 32:
    if not d.hdrValid(L):
      L.hdr = d.hdrPixels(L)
    else: d.syncHdr(L)
  else:
    d.ensureHi(L)
  let deep32 = d.depth == 32
  d.touch(L, r)
  var o: DeepImg
  if way.deep != nil and (way.point == nil or margin > 0):
    let ext = d.clip(rect(r.x - margin, r.y - margin, r.w + 2 * margin, r.h + 2 * margin))
    let inner = rect(r.x - ext.x, r.y - ext.y, r.w, r.h)
    let src = readDeep(d, L, ext)
    let full = way.deep(src, inner)
    if full.w == r.w and full.h == r.h and (ext.w != r.w or ext.h != r.h) == false:
      o = full
    elif full.w == ext.w and full.h == ext.h:
      o = DeepImg(w: r.w, h: r.h, px: newSeqUninit[float32](r.w * r.h * 4))
      let fp = f32p(full.px)
      let dp = f32p(o.px)
      for y in 0 ..< r.h:
        copyMem(addr dp[y * r.w * 4], addr fp[((inner.y + y) * ext.w + inner.x) * 4], r.w * 16)
    else: o = full
  else:
    let src = readDeep(d, L, r)
    o = pointDeep(src, rect(0, 0, r.w, r.h), way, deep32)
  if o.w != r.w or o.h != r.h: return false
  d.writeDeep(L, r, o)
  true

# ---- the image composited at 16 bits ---------------------------------------------------------------------

proc lumF(r, g, b: float32): float32 {.inline.} = 0.3'f32 * r + 0.59'f32 * g + 0.11'f32 * b

proc clipColor(c: var array[3, float32]) =
  let l = lumF(c[0], c[1], c[2])
  let n = min(c[0], min(c[1], c[2]))
  let x = max(c[0], max(c[1], c[2]))
  if n < 0:
    for k in 0 .. 2: c[k] = l + (c[k] - l) * l / (l - n)
  if x > 1:
    for k in 0 .. 2: c[k] = l + (c[k] - l) * (1 - l) / (x - l)

proc setLum(c: var array[3, float32]; l: float32) =
  let dl = l - lumF(c[0], c[1], c[2])
  for k in 0 .. 2: c[k] += dl
  clipColor(c)

proc satF(c: array[3, float32]): float32 = max(c[0], max(c[1], c[2])) - min(c[0], min(c[1], c[2]))

proc setSat(c: var array[3, float32]; s: float32) =
  var mn = 0
  var mx = 0
  for k in 1 .. 2:
    if c[k] < c[mn]: mn = k
    if c[k] > c[mx]: mx = k
  if mn == mx:
    c = [0'f32, 0, 0]
    return
  let md = 3 - mn - mx
  if c[mx] > c[mn]:
    c[md] = (c[md] - c[mn]) * s / (c[mx] - c[mn])
    c[mx] = s
  else:
    c[md] = 0
    c[mx] = 0
  c[mn] = 0

proc sepF(m: BlendMode; cb, cs: float32): float32 {.inline.} =
  ## The separable modes on a channel, 0 .. 1.
  case m
  of bmMultiply: cb * cs
  of bmScreen: cb + cs - cb * cs
  of bmOverlay: (if cb < 0.5: 2 * cb * cs else: 1 - 2 * (1 - cb) * (1 - cs))
  of bmHardLight: (if cs < 0.5: 2 * cb * cs else: 1 - 2 * (1 - cb) * (1 - cs))
  of bmSoftLight:
    let dd = if cb <= 0.25: ((16 * cb - 12) * cb + 4) * cb else: sqrt(cb)
    if cs <= 0.5: cb - (1 - 2 * cs) * cb * (1 - cb) else: cb + (2 * cs - 1) * (dd - cb)
  of bmDarken: min(cb, cs)
  of bmLighten: max(cb, cs)
  of bmDifference: abs(cb - cs)
  of bmColorBurn: (if cb >= 1: 1'f32 elif cs <= 0: 0'f32 else: 1 - min(1'f32, (1 - cb) / cs))
  of bmColorDodge: (if cb <= 0: 0'f32 elif cs >= 1: 1'f32 else: min(1'f32, cb / (1 - cs)))
  of bmLinearBurn: max(0'f32, cb + cs - 1)
  of bmLinearDodge: min(1'f32, cb + cs)
  of bmVividLight:
    if cs < 0.5:
      let s2 = 2 * cs
      if cb >= 1: 1'f32 elif s2 <= 0: 0'f32 else: 1 - min(1'f32, (1 - cb) / s2)
    else:
      let s2 = 2 * (cs - 0.5)
      if cb <= 0: 0'f32 elif s2 >= 1: 1'f32 else: min(1'f32, cb / (1 - s2))
  of bmLinearLight: clamp(cb + 2 * cs - 1, 0'f32, 1'f32)
  of bmPinLight: (if cs < 0.5: min(cb, 2 * cs) else: max(cb, 2 * (cs - 0.5)))
  of bmHardMix: (if cb + cs >= 1: 1'f32 else: 0'f32)
  of bmExclusion: cb + cs - 2 * cb * cs
  of bmSubtract: max(0'f32, cb - cs)
  of bmDivide: (if cs <= 0: (if cb > 0: 1'f32 else: 0'f32) else: min(1'f32, cb / cs))
  else: cs

proc blendColor(m: BlendMode; b, s: array[3, float32]): array[3, float32] =
  ## What `s` over `b` makes in mode `m` (what is under it opaque).
  case m
  of bmHue:
    result = s
    setSat(result, satF(b)); setLum(result, lumF(b[0], b[1], b[2]))
  of bmSaturation:
    result = b
    setSat(result, satF(s)); setLum(result, lumF(b[0], b[1], b[2]))
  of bmColor:
    result = s
    setLum(result, lumF(b[0], b[1], b[2]))
  of bmLuminosity:
    result = b
    setLum(result, lumF(s[0], s[1], s[2]))
  of bmDarkerColor: result = (if lumF(s[0], s[1], s[2]) < lumF(b[0], b[1], b[2]): s else: b)
  of bmLighterColor: result = (if lumF(s[0], s[1], s[2]) > lumF(b[0], b[1], b[2]): s else: b)
  of bmNormal: result = s
  else:
    for k in 0 .. 2: result[k] = sepF(m, b[k], s[k])

proc over(dst: var array[4, float32]; s: array[3, float32]; sa: float32; m: BlendMode) {.inline.} =
  ## `s` (alpha `sa`) over `dst` in mode `m` (straight alpha, as `blendPx`).
  if sa <= 0: return
  let da = dst[3]
  if da <= 0:
    dst = [s[0], s[1], s[2], sa]
    return
  var c: array[3, float32]
  if m == bmNormal: c = s
  else:
    let bl = blendColor(m, [dst[0], dst[1], dst[2]], s)
    for k in 0 .. 2: c[k] = s[k] * (1 - da) + bl[k] * da
  let oa = sa + da * (1 - sa)
  let wd = da * (1 - sa)
  for k in 0 .. 2: dst[k] = (c[k] * sa + dst[k] * wd) / oa
  dst[3] = oa

proc deepLutAt(lut: ptr UncheckedArray[uint32]; r, g, b: float32): array[3, float32] {.inline.} =
  ## An adjustment layer's table (`LutN`^3) at a color 0 .. 1, read between.
  const n = LutN - 1
  let fr = clamp(r, 0'f32, 1'f32) * n
  let fg = clamp(g, 0'f32, 1'f32) * n
  let fb = clamp(b, 0'f32, 1'f32) * n
  let r0 = min(int(fr), n - 1)
  let g0 = min(int(fg), n - 1)
  let b0 = min(int(fb), n - 1)
  let tr = fr - float32(r0)
  let tg = fg - float32(g0)
  let tb = fb - float32(b0)
  template at(i, j, k: int): uint32 = lut[((r0 + i) * LutN + g0 + j) * LutN + b0 + k]
  for c in 0 .. 2:
    let sh = 16 - 8 * c
    template v(p: uint32): float32 = float32((p shr sh) and 255)
    let c00 = v(at(0, 0, 0)) * (1 - tb) + v(at(0, 0, 1)) * tb
    let c01 = v(at(0, 1, 0)) * (1 - tb) + v(at(0, 1, 1)) * tb
    let c10 = v(at(1, 0, 0)) * (1 - tb) + v(at(1, 0, 1)) * tb
    let c11 = v(at(1, 1, 0)) * (1 - tb) + v(at(1, 1, 1)) * tb
    result[c] = ((c00 * (1 - tg) + c01 * tg) * (1 - tr) + (c10 * (1 - tg) + c11 * tg) * tr) / 255

proc composite16(d: Doc): seq[uint16] =
  ## The layers composited at 16 bits: each layer's 16 bits (or 8), masks,
  ## opacity and fill, blend modes, clipping, adjustment layers (their
  ## tables read between at 16 bits). Empty when the image has what is only
  ## done at 8 bits (layer styles, Blend If, groups mixed on their own,
  ## feathered masks, Dissolve...): the caller composites at 8 bits then.
  let n = d.w * d.h
  # the groups: only open ones (pass through, all showing) are done here
  var parents = newSeq[int](d.layers.len)
  var stack: seq[int]
  for i in countdown(d.layers.high, 0):
    let dd = d.layers[i].depth
    while stack.len > 0 and d.layers[stack[^1]].depth >= dd: stack.setLen(stack.len - 1)
    parents[i] = if stack.len > 0: stack[^1] else: -1
    if d.layers[i].group: stack.add i
  type Item = object
    px: ptr UncheckedArray[uint32]
    hi: ptr UncheckedArray[uint16]
    mask: ptr UncheckedArray[uint32]
    lut: ptr UncheckedArray[uint32]
    op: float32
    mode: BlendMode
    base: int
    lo: float32                    # (its mask's density: the least it lets through)
  var items: seq[Item]
  var base = -1
  for i, L in d.layers:
    var hidden = false
    var p = parents[i]
    while p >= 0:
      let G = d.layers[p]
      if not G.visible or G.opacity <= 0: hidden = true
      elif not G.passThrough or G.opacity < 100 or (G.mask != nil and not G.maskOff) or G.mode != bmNormal or
           G.hasFx: return @[]
      p = parents[p]
    if L.group: continue
    let shown = not hidden and L.visible and L.opacity > 0 and L.px.len == n
    if L.clipped and base >= 0:
      if not shown: continue
    else:
      base = if shown: items.len else: -1
    if not shown: continue
    if L.hasFx or L.blendIf.isOn or L.mode in {bmDissolve, bmBehind, bmClear} or
       L.adjust.kind in AreaAdjustKinds: return @[]
    var it = Item(px: u32p(L.px), op: float32(L.opacity * L.fill) / 10000, mode: L.mode,
                  base: (if L.clipped and items.len > 0 and base >= 0 and base < items.len: base else: -1))
    if d.hiValid(L):
      d.syncHi(L)
      it.hi = u16p(L.hi)
    if L.mask != nil and not L.maskOff and L.mask.px.len == n:
      if L.maskFeather > 0.05: return @[]
      it.mask = u32p(L.mask.px)
      it.lo = float32(100 - L.maskDensity) / 100
    if L.adjust.kind.len > 0:
      let t = lutOf(L)
      if t == nil: return @[]
      it.lut = u32p(t[])
    items.add it
  if items.len == 0: return @[]
  result = newSeqUninit[uint16](n * 4)
  let o = u16p(result)
  let ip = cast[ptr UncheckedArray[Item]](addr items[0])
  let cnt = items.len
  let w = d.w
  parallelRows(d.h, y):
    for x in 0 ..< w:
      let i = y * w + x
      var acc = [0'f32, 0, 0, 0]
      for k in 0 ..< cnt:
        let it = ip[k]
        var a = it.op
        if it.mask != nil:
          let mv = float32((it.mask[i] shr 16) and 255) / 255
          a *= it.lo + mv * (1 - it.lo)
        if it.base >= 0:
          let b = ip[it.base]
          var ba = if b.hi != nil: float32(b.hi[4 * i + 3]) / 65535 else: float32(b.px[i] shr 24) / 255
          if b.lut != nil: ba = ba * float32((b.px[i] shr 16) and 255) / 255
          if b.mask != nil:
            ba *= b.lo + float32((b.mask[i] shr 16) and 255) / 255 * (1 - b.lo)
          a *= ba
        if a <= 0: continue
        if it.lut != nil:
          # an adjustment layer: what is under it, changed where its pixels say
          if acc[3] <= 0: continue
          let p = it.px[i]
          a *= float32((p shr 16) and 255) / 255 * float32(p shr 24) / 255
          if a <= 0: continue
          let v = deepLutAt(it.lut, acc[0], acc[1], acc[2])
          let bl = if it.mode == bmNormal: v else: blendColor(it.mode, [acc[0], acc[1], acc[2]], v)
          for c in 0 .. 2: acc[c] += (bl[c] - acc[c]) * min(a, 1'f32)
          continue
        var s: array[3, float32]
        var sa: float32
        if it.hi != nil:
          for c in 0 .. 2: s[c] = float32(it.hi[4 * i + c]) / 65535
          sa = float32(it.hi[4 * i + 3]) / 65535
        else:
          let p = it.px[i]
          s = [float32((p shr 16) and 255) / 255, float32((p shr 8) and 255) / 255, float32(p and 255) / 255]
          sa = float32(p shr 24) / 255
        over(acc, s, sa * a, it.mode)
      for c in 0 .. 3: o[4 * i + c] = uint16(clamp(int(acc[c] * 65535 + 0.5), 0, 65535))

proc flatten16(d: Doc): seq[uint16] = composite16(d)

# ---- the gradient at 16 bits ------------------------------------------------------------------------------

proc gradientDeep*(d: Doc; L: Layer; r: Rect; opacity: float32;
                   colorAt: proc (x, y: int): array[4, float32]) =
  ## Draws into `r` of `L` at 16 bits (or 32): `colorAt` gives each
  ## pixel's R G B A (0 .. 1, straight), put over what is there at
  ## `opacity` (0 .. 1), in the selection; its 8 bits made again. (The
  ## Gradient tool at 16 bits: no banding.)
  if d.depth < 16 or L.px.len != d.w * d.h: return
  let c = d.clip(r)
  if c.w <= 0 or c.h <= 0: return
  if d.depth == 32:
    if not d.hdrValid(L): L.hdr = d.hdrPixels(L)
    else: d.syncHdr(L)
  else: d.ensureHi(L)
  d.touch(L, c)
  var o = readDeep(d, L, c)
  let op = f32p(o.px)
  let deep32 = d.depth == 32
  for y in 0 ..< c.h:
    for x in 0 ..< c.w:
      var v = colorAt(c.x + x, c.y + y)
      if deep32:
        for k in 0 .. 2: v[k] = float32(srgbToLinear(clamp(v[k], 0'f32, 1'f32).float))
      let q = (y * c.w + x) * 4
      var dst = [op[q], op[q + 1], op[q + 2], op[q + 3]]
      over(dst, [v[0], v[1], v[2]], v[3] * opacity, bmNormal)
      for k in 0 .. 3: op[q + k] = dst[k]
  d.writeDeep(L, c, o)

{.pop.}

hiFilterHook = hiFilter
flatten16Hook = flatten16
deepGradientHook = gradientDeep
