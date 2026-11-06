## A canvas you draw on with the HTML5 Canvas 2D API.
##
## The names are the browser's, in Nim style: paths (`beginPath`, `moveTo`,
## `lineTo`, `bezierCurveTo`, `arc`, `ellipse`, `rect`, `roundRect`...),
## `fill`, `stroke`, `clip`, colors, gradients and patterns, line widths,
## caps, joins and dashes, transforms with `save` / `restore`, text,
## pictures, image data, shadows, compositing, hit tests. Everything is
## drawn by a built-in anti-aliased rasterizer into the canvas's own
## pixels, at the screen's resolution (crisp on 4K and phones); the
## numbers you give are logical pixels, like every size in the kit.
##
## In a window, `canvas2d` places a canvas in the layout and gives you its
## context for the frame; you draw everything each frame (immediate mode)
## and the canvas is rasterized again only when what you drew changed --
## an idle frame costs nothing. With `retained = true` the picture stays
## until you change it (a paint program). `newCanvas2D` makes a canvas
## without a window (an image to save as PNG).
##
## .. code-block:: nim
##   import retroui, retroui/canvas2d
##   var angle = 0.0
##   app "Canvas", 420, 320:
##     canvas2d(ctx, 400, 280):
##       let g = ctx.createLinearGradient(0, 0, 400, 0)
##       g.addColorStop(0, "#000080")
##       g.addColorStop(1, "#00a0ff")
##       ctx.fillStyle = g
##       ctx.fillRect(0, 0, 400, 280)
##       ctx.translate(200, 140)
##       ctx.rotate(angle)
##       ctx.fillStyle = "gold"
##       ctx.beginPath()
##       ctx.arc(0, 0, 60, 0, 2 * PI)
##       ctx.fill()
##       if ctx.input.down: angle += ctx.input.dx / 100   # drag to turn it
##
## The pointer, fingers and keys over a canvas are in `ctx.input`, in the
## canvas's coordinates; `isPointInPath` tells which shape is under them.
##
## Type names are the HTML IDL's (`CanvasLineCap`, `CanvasFillRule`,
## `DOMMatrix`, `ImageData`, `Path2D`...); a CSS string works wherever the
## browser takes one (`ctx.lineCap = "round"`, `ctx.fillStyle = "#f80"`).
## Numbers that are not finite are ignored, as in the browser.
##
## Text is shaped (Arabic joined, mixed lines in the bidi algorithm's
## order); `direction` "rtl" makes a line a right-to-left paragraph whose
## `start` is its right end, "ltr" a left-to-right one, "inherit" (the
## default) each line from its first letter, `start` at the left.
##
## Not supported: `filter`, font families other than the built-in FreeSans, FreeSerif
## and FreeMono (the others are drawn in the UI's font, see `font=`),
## characters the built-in fonts lack (CJK, emoji: an empty box);
## `strokeText` outlines the filled glyphs; a dash pattern finer than
## 20000 pieces in one stroke draws a solid line.

import std/[math, strutils, tables, hashes, algorithm]
import gfx, core, widgets, ttf, typeset, imaging

type
  Vec = tuple[x, y: float]

  DOMMatrix* = object
    ## An affine transform as HTML's DOMMatrix: a point (x, y) goes to
    ## (a*x + c*y + e, b*x + d*y + f).
    a*, b*, c*, d*, e*, f*: float   ## the matrix's six numbers (identity: 1, 0, 0, 1, 0, 0)

  CanvasLineCap* = enum
    ## How open line ends look.
    lcButt = "butt", lcRound = "round", lcSquare = "square"
  CanvasLineJoin* = enum
    ## How lines meet at corners.
    ljMiter = "miter", ljRound = "round", ljBevel = "bevel"
  CanvasFillRule* = enum
    ## Which parts of a path are inside.
    frNonZero = "nonzero", frEvenOdd = "evenodd"
  CanvasTextAlign* = enum
    ## Where `fillText`'s x is on the text.
    taStart = "start", taEnd = "end", taLeft = "left", taRight = "right",
    taCenter = "center"
  CanvasDirection* = enum
    ## Which way `fillText`'s text reads (`direction`).
    cdInherit = "inherit", cdLtr = "ltr", cdRtl = "rtl"
  CanvasTextBaseline* = enum
    ## Where `fillText`'s y is on the text.
    tbAlphabetic = "alphabetic", tbTop = "top", tbHanging = "hanging",
    tbMiddle = "middle", tbIdeographic = "ideographic", tbBottom = "bottom"
  CanvasCompositeOp* = enum
    ## How new drawing combines with what is there (`globalCompositeOperation`).
    coSourceOver = "source-over", coSourceIn = "source-in",
    coSourceOut = "source-out", coSourceAtop = "source-atop",
    coDestinationOver = "destination-over", coDestinationIn = "destination-in",
    coDestinationOut = "destination-out", coDestinationAtop = "destination-atop",
    coLighter = "lighter", coCopy = "copy", coXor = "xor",
    coMultiply = "multiply", coScreen = "screen", coDarken = "darken",
    coLighten = "lighten", coDifference = "difference"

  GradientKind = enum gkLinear, gkRadial, gkConic
  CanvasGradient* = ref object
    ## A gradient made by `createLinearGradient`, `createRadialGradient` or
    ## `createConicGradient`; give it colors with `addColorStop`, then make
    ## it a `fillStyle` or `strokeStyle`.
    kind: GradientKind
    x0, y0, r0, x1, y1, r1: float
    stops: seq[tuple[t: float; c: uint32]]     # straight 0xAARRGGBB
    lut: seq[uint32]                           # premultiplied
    version: int

  CanvasPattern* = ref object
    ## A picture repeated as a fill (`createPattern`).
    img: Bitmap
    repeatX, repeatY: bool

  PaintKind = enum paColor, paGradient, paPattern
  Paint = object
    kind: PaintKind
    color: uint32           # straight 0xAARRGGBB
    grad: CanvasGradient
    pat: CanvasPattern

  ImageData* = ref object
    ## Pixels as `getImageData` gives them: `width` x `height`, four bytes
    ## per pixel (red, green, blue, alpha; not premultiplied), row by row.
    width*, height*: int            ## its size in pixels
    data*: seq[uint8]               ## `width` * `height` * 4 bytes

  TextMetrics* = object
    ## What `measureText` tells about a text, in the canvas's units.
    width*: float                   ## how far the text advances
    actualBoundingBoxLeft*, actualBoundingBoxRight*: float
      ## how far the inked letters reach left and right of the text's
      ## `textAlign` point
    actualBoundingBoxAscent*, actualBoundingBoxDescent*: float
      ## how far the inked letters reach above and below the `textBaseline`
    fontBoundingBoxAscent*, fontBoundingBoxDescent*: float
      ## the font's ascent and descent from the `textBaseline` (the same for
      ## any text in that font)

  ClipMask = ref object
    a: seq[uint8]           # coverage per backing pixel

  State = object
    ctm: DOMMatrix
    fill, stroke: Paint
    lineWidth, miterLimit, dashOffset: float
    cap: CanvasLineCap
    join: CanvasLineJoin
    dash: seq[float]
    alpha: float
    op: CanvasCompositeOp
    font: string
    fontSize: float
    bold, italic, mono: bool
    serif: bool              ## FreeSerif ("serif", "Times"...)
    sans: bool               ## FreeSans, named ("FreeSans", "Helvetica", "Arial"); else the UI's font
    align: CanvasTextAlign
    baseline: CanvasTextBaseline
    dir: CanvasDirection
    shadowColor: uint32
    shadowBlur, shadowX, shadowY: float
    smoothing: bool
    clip: ClipMask

  SubPath = object
    pts: seq[Vec]           # backing (device) pixels
    closed: bool
    t0, t1: Vec             # the true direction at the start / end when that
                            # end is on a curve ((0, 0): along the first / last
                            # segment), so line caps sit square to the curve

  PathB = object
    subs: seq[SubPath]
    hasCur: bool

  PathOpKind = enum
    poMove, poLine, poQuad, poCubic, poArc, poArcTo, poEllipse, poRect,
    poRoundRect, poClose
  PathOp = object
    kind: PathOpKind
    f: array[8, float]
    radii: seq[float]

  Path2D* = ref object
    ## A path kept to fill, stroke or hit-test later (and again), like the
    ## browser's Path2D: build it with the same calls as the context's own
    ## path, in its own coordinates; the context's transform applies when
    ## it is used.
    ops: seq[PathOp]
    h: Hash

  OpKind = enum
    okSave, okRestore, okSetTransform, okTransform, okResetTransform,
    okFillStyle, okStrokeStyle, okLineWidth, okCap, okJoin, okMiter, okDash,
    okDashOffset, okAlpha, okComposite, okFont, okAlign, okBaseline, okDirection,
    okShadowColor, okShadowBlur, okShadowX, okShadowY, okSmoothing,
    okBeginPath, okPath, okFill, okStroke, okClip, okFillRect, okStrokeRect,
    okClearRect, okFillText, okStrokeText, okDrawImage, okPutImageData
  Op = object
    kind: OpKind
    f: array[8, float]
    n: int
    u: uint32
    s: string
    paint: Paint
    po: PathOp
    path: Path2D
    img: Bitmap
    data: ImageData
    fl: seq[float]

  CanvasInput* = object
    ## What the mouse, a finger and the keys did over a canvas this frame
    ## (`ctx.input`), in the canvas's logical pixels.
    x*, y*: float           ## the pointer (last place, also outside)
    over*: bool             ## the pointer is over the canvas (a finger: while down)
    down*: bool             ## the button or finger is held, and went down here
    pressed*: bool          ## it went down on the canvas this frame
    released*: bool         ## it was let go (or the press was taken by a
                            ## finger scrolling the page) this frame
    clicked*: bool          ## let go over the canvas (a click or a tap)
    doubleClicked*: bool    ## a double click (or double tap) this frame
    rightClicked*: bool     ## a right click this frame (or a long press, when
                            ## `captureDrag` is off)
    dragging*: bool         ## held, and it moved since it went down
    dx*, dy*: float         ## how far it moved this frame while held
    wheel*: int             ## wheel steps over the canvas (+: away from you)
    focused*: bool          ## the canvas has the keyboard (`focusable`)
    key*: KeyCode           ## the key pressed this frame while focused
    mods*: set[Modifier]    ## Ctrl, Shift, Alt held
    typed*: string          ## text typed this frame while focused
    finger*: bool           ## the press is a finger's

  Canvas2D* = ref object
    ## A canvas and its drawing context (one object, as in the browser
    ## `canvas.getContext("2d")`). Draw with the procs below.
    w, h: int               # backing pixels
    ratio: float
    pm: seq[uint32]         # premultiplied 0xAARRGGBB
    bmp: Bitmap             # straight, what the screen shows
    st: State
    stack: seq[State]
    path: PathB
    deferred, painting, dirty, retained: bool
    ops: seq[Op]
    hash, lastHash: Hash
    rasterized: int         ## how many times it was rasterized (for tests)
    input*: CanvasInput     ## what the pointer, fingers and keys did (in a window)
    id: Id
    screen: Rect
    lastX, lastY: float
    pressX, pressY: float
    moved: bool

const
  MaxSide = 8192            ## the largest backing store side, in pixels
  MaxPixels = 16_777_216    ## and the most pixels
  MaxStack = 512            ## `save` deeper than this is ignored
  Far = 1e7                 ## coordinates are kept within this (backing pixels)
  Tol = 0.2                 ## how far flattened curves may stray, backing pixels

# ---- small math -------------------------------------------------------------------------------

proc fin(x: float): bool {.inline.} = x == x and x != Inf and x != NegInf

const toIMax = when sizeof(int) > 4: 1_000_000_000_000_000 else: 1_000_000_000

proc toI(x: float): int {.inline.} =
  ## A float as an int, never overflowing (NaN: 0).
  if x != x: 0
  elif x >= float(toIMax): toIMax
  elif x <= -float(toIMax): -toIMax
  else: int(x)

proc identity(): DOMMatrix = DOMMatrix(a: 1, d: 1)

proc mul(m, n: DOMMatrix): DOMMatrix =
  ## `n` applied first, then `m`.
  DOMMatrix(a: m.a * n.a + m.c * n.b, b: m.b * n.a + m.d * n.b,
         c: m.a * n.c + m.c * n.d, d: m.b * n.c + m.d * n.d,
         e: m.a * n.e + m.c * n.f + m.e, f: m.b * n.e + m.d * n.f + m.f)

proc apply(m: DOMMatrix; x, y: float): Vec {.inline.} =
  (m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f)

proc invert(m: DOMMatrix; ok: var bool): DOMMatrix =
  let det = m.a * m.d - m.b * m.c
  ok = fin(det) and abs(det) > 1e-12
  if not ok: return identity()
  let id = 1 / det
  DOMMatrix(a: m.d * id, b: -m.b * id, c: -m.c * id, d: m.a * id,
         e: (m.c * m.f - m.d * m.e) * id, f: (m.b * m.e - m.a * m.f) * id)

proc clampFar(v: Vec): Vec {.inline.} =
  (clamp(v.x, -Far, Far), clamp(v.y, -Far, Far))

proc bits(f: float): uint64 {.inline.} = cast[uint64](f)

# ---- colors ---------------------------------------------------------------------------------

const namedColors = {
  "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000,
  "blue": 0x0000FF, "yellow": 0xFFFF00, "cyan": 0x00FFFF, "aqua": 0x00FFFF,
  "magenta": 0xFF00FF, "fuchsia": 0xFF00FF, "gray": 0x808080, "grey": 0x808080,
  "silver": 0xC0C0C0, "maroon": 0x800000, "olive": 0x808000, "lime": 0x00FF00,
  "navy": 0x000080, "teal": 0x008080, "purple": 0x800080, "orange": 0xFFA500,
  "gold": 0xFFD700, "pink": 0xFFC0CB, "brown": 0xA52A2A, "coral": 0xFF7F50,
  "crimson": 0xDC143C, "darkblue": 0x00008B, "darkgreen": 0x006400,
  "darkred": 0x8B0000, "darkgray": 0xA9A9A9, "darkgrey": 0xA9A9A9,
  "lightgray": 0xD3D3D3, "lightgrey": 0xD3D3D3, "lightblue": 0xADD8E6,
  "lightgreen": 0x90EE90, "skyblue": 0x87CEEB, "steelblue": 0x4682B4,
  "royalblue": 0x4169E1, "dodgerblue": 0x1E90FF, "indigo": 0x4B0082,
  "violet": 0xEE82EE, "orchid": 0xDA70D6, "salmon": 0xFA8072,
  "tomato": 0xFF6347, "orangered": 0xFF4500, "khaki": 0xF0E68C,
  "beige": 0xF5F5DC, "ivory": 0xFFFFF0, "tan": 0xD2B48C, "chocolate": 0xD2691E,
  "sienna": 0xA0522D, "turquoise": 0x40E0D0, "seagreen": 0x2E8B57,
  "forestgreen": 0x228B22, "limegreen": 0x32CD32, "slategray": 0x708090,
  "slategrey": 0x708090, "dimgray": 0x696969, "dimgrey": 0x696969,
  "whitesmoke": 0xF5F5F5, "gainsboro": 0xDCDCDC, "lavender": 0xE6E6FA,
  "plum": 0xDDA0DD, "wheat": 0xF5DEB3, "midnightblue": 0x191970,
  "cornflowerblue": 0x6495ED, "deepskyblue": 0x00BFFF, "hotpink": 0xFF69B4,
  "deeppink": 0xFF1493, "firebrick": 0xB22222, "goldenrod": 0xDAA520,
  "darkorange": 0xFF8C00, "mintcream": 0xF5FFFA, "honeydew": 0xF0FFF0,
  "aliceblue": 0xF0F8FF, "azure": 0xF0FFFF, "snow": 0xFFFAFA,
  "linen": 0xFAF0E6, "cadetblue": 0x5F9EA0, "darkcyan": 0x008B8B,
  "darkviolet": 0x9400D3, "rebeccapurple": 0x663399}.toTable

proc parseColor*(s: string; c: var uint32): bool =
  ## A CSS color -- "#rgb", "#rgba", "#rrggbb", "#rrggbbaa", "rgb(...)",
  ## "rgba(...)", "hsl(...)", "hsla(...)", a name ("gold"), "transparent" --
  ## as straight 0xAARRGGBB. False (and `c` untouched) when it is none.
  let t = s.strip.toLowerAscii
  if t.len == 0: return false
  proc hexv(ch: char): int =
    case ch
    of '0'..'9': ord(ch) - ord('0')
    of 'a'..'f': ord(ch) - ord('a') + 10
    else: -1
  if t[0] == '#':
    var v: seq[int]
    for ch in t[1 .. ^1]:
      let x = hexv(ch)
      if x < 0: return false
      v.add x
    var r, g, b, a: int
    a = 255
    case v.len
    of 3, 4:
      r = v[0] * 17; g = v[1] * 17; b = v[2] * 17
      if v.len == 4: a = v[3] * 17
    of 6, 8:
      r = v[0] * 16 + v[1]; g = v[2] * 16 + v[3]; b = v[4] * 16 + v[5]
      if v.len == 8: a = v[6] * 16 + v[7]
    else: return false
    c = (uint32(a) shl 24) or (uint32(r) shl 16) or (uint32(g) shl 8) or uint32(b)
    return true
  if t == "transparent":
    c = 0
    return true
  if namedColors.hasKey(t):
    c = 0xFF000000'u32 or uint32(namedColors[t])
    return true
  let open = t.find('(')
  if open < 0 or not t.endsWith(")"): return false
  let fn = t[0 ..< open].strip
  var inner = t[open + 1 ..< t.high].replace("/", " ").replace(",", " ")
  var parts: seq[string]
  for p in inner.splitWhitespace: parts.add p
  if parts.len < 3 or parts.len > 4: return false
  proc num(p: string; full: float; ok: var bool): float =
    try:
      if p.endsWith("%"): parseFloat(p[0 ..< ^1]) / 100 * full
      elif p.endsWith("deg"): parseFloat(p[0 ..< ^3])
      else: parseFloat(p)
    except ValueError:
      ok = false
      0.0
  var ok = true
  var alpha = 1.0
  if parts.len == 4: alpha = num(parts[3], 1, ok)
  var r, g, b: float
  if fn in ["rgb", "rgba"]:
    r = num(parts[0], 255, ok); g = num(parts[1], 255, ok); b = num(parts[2], 255, ok)
  elif fn in ["hsl", "hsla"]:
    let hh = num(parts[0], 360, ok)
    let ss = num(parts[1], 1, ok) / (if parts[1].endsWith("%"): 1.0 else: 100.0)
    let ll = num(parts[2], 1, ok) / (if parts[2].endsWith("%"): 1.0 else: 100.0)
    let hue = ((hh mod 360) + 360) mod 360 / 360
    proc f(n: float): float =
      let k = (n + hue * 12) mod 12
      ll - ss * min(ll, 1 - ll) * max(-1.0, min(k - 3, min(9 - k, 1.0)))
    r = f(0) * 255; g = f(8) * 255; b = f(4) * 255
  else: return false
  if not ok or not (fin(r) and fin(g) and fin(b) and fin(alpha)): return false
  template ch(v: float): uint32 = uint32(clamp(int(v + 0.5), 0, 255))
  c = (ch(alpha * 255) shl 24) or (ch(r) shl 16) or (ch(g) shl 8) or ch(b)
  true

proc colorText(c: uint32): string =
  let a = c shr 24
  if a == 255: "#" & toHex(int(c and 0xFFFFFF), 6).toLowerAscii
  else:
    "rgba(" & $((c shr 16) and 255) & ", " & $((c shr 8) and 255) & ", " &
      $(c and 255) & ", " & formatFloat(float(a) / 255, ffDecimal, 3) & ")"

proc premul(c: uint32): uint32 {.inline.} =
  let a = c shr 24
  if a == 255: return c
  if a == 0: return 0
  let r = ((c shr 16) and 255) * a div 255
  let g = ((c shr 8) and 255) * a div 255
  let b = (c and 255) * a div 255
  (a shl 24) or (r shl 16) or (g shl 8) or b

proc unpremul(c: uint32): uint32 {.inline.} =
  let a = c shr 24
  if a == 255 or a == 0: return (if a == 0: 0'u32 else: c)
  let r = min(255'u32, ((c shr 16) and 255) * 255 div a)
  let g = min(255'u32, ((c shr 8) and 255) * 255 div a)
  let b = min(255'u32, (c and 255) * 255 div a)
  (a shl 24) or (r shl 16) or (g shl 8) or b

proc scaleA(c: uint32; k: uint32): uint32 {.inline.} =
  ## Premultiplied `c` times k/255.
  if k >= 255: return c
  if k == 0: return 0
  let rb = ((c and 0x00FF00FF'u32) * k + 0x00800080'u32)
  let ag = (((c shr 8) and 0x00FF00FF'u32) * k + 0x00800080'u32)
  (((rb + ((rb shr 8) and 0x00FF00FF'u32)) shr 8) and 0x00FF00FF'u32) or
    ((ag + ((ag shr 8) and 0x00FF00FF'u32)) and 0xFF00FF00'u32)

proc over(s, d: uint32): uint32 {.inline.} =
  ## Premultiplied source-over.
  let sa = s shr 24
  if sa == 255: return s
  if sa == 0: return d
  let k = 255'u32 - sa
  let rb = ((d and 0x00FF00FF'u32) * k + 0x00800080'u32)
  let ag = (((d shr 8) and 0x00FF00FF'u32) * k + 0x00800080'u32)
  let dd = (((rb + ((rb shr 8) and 0x00FF00FF'u32)) shr 8) and 0x00FF00FF'u32) or
           ((ag + ((ag shr 8) and 0x00FF00FF'u32)) and 0xFF00FF00'u32)
  s + dd

# ---- gradients and patterns -------------------------------------------------------------------

proc addColorStop*(g: CanvasGradient; offset: float; color: string) =
  ## A color at `offset` (0 at the start, 1 at the end) of the gradient.
  ## Offsets outside 0..1 and colors that are not colors are ignored.
  if g == nil or not fin(offset) or offset < 0 or offset > 1: return
  var c: uint32
  if not parseColor(color, c): return
  var i = g.stops.len
  while i > 0 and g.stops[i - 1].t > offset: dec i
  g.stops.insert((offset, c), i)
  inc g.version
  g.lut.setLen(0)

proc addColorStop*(g: CanvasGradient; offset: float; color: Color) =
  ## A color (a kit `Color`) at `offset` of the gradient.
  addColorStop(g, offset, "rgba(" & $color.r & "," & $color.g & "," & $color.b & "," &
               $(float(color.a) / 255) & ")")

const LutN = 512

proc buildLut(g: CanvasGradient) =
  g.lut = newSeq[uint32](LutN)
  if g.stops.len == 0: return
  for i in 0 ..< LutN:
    let t = float(i) / float(LutN - 1)
    var k = 0
    while k < g.stops.len and g.stops[k].t <= t: inc k
    var c: uint32
    if k == 0: c = premul(g.stops[0].c)
    elif k == g.stops.len: c = premul(g.stops[^1].c)
    else:
      let a = g.stops[k - 1]
      let b = g.stops[k]
      let span = b.t - a.t
      let u = if span <= 0: 1.0 else: (t - a.t) / span
      let pa = premul(a.c)
      let pb = premul(b.c)
      var v: uint32
      for sh in [0'u32, 8, 16, 24]:
        let ca = float((pa shr sh) and 255)
        let cb = float((pb shr sh) and 255)
        v = v or (uint32(clamp(int(ca + (cb - ca) * u + 0.5), 0, 255)) shl sh)
      c = v
    g.lut[i] = c

proc createPattern*(img: Bitmap; repetition = "repeat"): CanvasPattern =
  ## The picture `img` repeated ("repeat", "repeat-x", "repeat-y" or
  ## "no-repeat") as a fill or stroke style; nil for an empty picture or
  ## another word (setting nil as a style is ignored).
  if img == nil or img.w <= 0 or img.h <= 0 or
     repetition notin ["repeat", "repeat-x", "repeat-y", "no-repeat", ""]:
    return nil
  CanvasPattern(img: img, repeatX: repetition in ["repeat", "repeat-x", ""],
                repeatY: repetition in ["repeat", "repeat-y", ""])

# ---- paths --------------------------------------------------------------------------------------

proc newSub(p: var PathB; v: Vec) =
  p.subs.add SubPath(pts: @[clampFar(v)])
  p.hasCur = true

proc cur(p: PathB): Vec =
  ## The current point (after `closePath`: where that subpath started).
  let s = p.subs[^1]
  if s.closed: s.pts[0] else: s.pts[^1]

proc addPt(p: var PathB; v: Vec) =
  let v = clampFar(v)
  let s = addr p.subs[^1]
  if s.closed:
    # after closePath, a new subpath from the same point
    let start = s.pts[0]
    p.subs.add SubPath(pts: @[start])
  let q = p.subs[^1].pts[^1]
  if abs(q.x - v.x) > 1e-9 or abs(q.y - v.y) > 1e-9:
    p.subs[^1].pts.add v
    p.subs[^1].t1 = (0.0, 0.0)

proc dirOf(vs: openArray[Vec]): Vec =
  ## The first of the differences that is not (nearly) zero.
  for v in vs:
    if abs(v.x) + abs(v.y) > 1e-9: return v
  (0.0, 0.0)

proc curveEnds(p: var PathB; starts: bool; d0, d1: Vec) =
  ## After flattening a curve: remember its true end directions.
  if p.subs.len == 0: return
  let s = addr p.subs[^1]
  if starts and s.pts.len >= 2: s.t0 = d0
  s.t1 = d1

proc startsSub(p: PathB): bool =
  p.subs.len > 0 and (p.subs[^1].closed or p.subs[^1].pts.len == 1)

proc pMoveTo(p: var PathB; m: DOMMatrix; x, y: float) =
  p.newSub(m.apply(x, y))

proc pLineTo(p: var PathB; m: DOMMatrix; x, y: float) =
  if not p.hasCur: p.pMoveTo(m, x, y)
  else: p.addPt(m.apply(x, y))

proc flatQuad(p: var PathB; a, b, c: Vec) =
  let ddx = a.x - 2 * b.x + c.x
  let ddy = a.y - 2 * b.y + c.y
  let dd = sqrt(ddx * ddx + ddy * ddy)
  let n = clamp(toI(ceil(sqrt(dd / (4 * Tol)))), 1, 1000)
  let starts = p.startsSub
  for i in 1 .. n:
    let t = float(i) / float(n)
    let u = 1 - t
    p.addPt((u * u * a.x + 2 * u * t * b.x + t * t * c.x,
             u * u * a.y + 2 * u * t * b.y + t * t * c.y))
  p.curveEnds(starts, dirOf([(b.x - a.x, b.y - a.y), (c.x - a.x, c.y - a.y)]),
              dirOf([(c.x - b.x, c.y - b.y), (c.x - a.x, c.y - a.y)]))

proc flatCubic(p: var PathB; a, b, c, d: Vec) =
  let d1 = hypot(a.x - 2 * b.x + c.x, a.y - 2 * b.y + c.y)
  let d2 = hypot(b.x - 2 * c.x + d.x, b.y - 2 * c.y + d.y)
  let dd = max(d1, d2)
  let n = if fin(dd): clamp(toI(ceil(sqrt(0.75 * dd / Tol))), 1, 1000) else: 1
  let starts = p.startsSub
  for i in 1 .. n:
    let t = float(i) / float(n)
    let u = 1 - t
    let w0 = u * u * u
    let w1 = 3 * u * u * t
    let w2 = 3 * u * t * t
    let w3 = t * t * t
    p.addPt((w0 * a.x + w1 * b.x + w2 * c.x + w3 * d.x,
             w0 * a.y + w1 * b.y + w2 * c.y + w3 * d.y))
  p.curveEnds(starts, dirOf([(b.x - a.x, b.y - a.y), (c.x - a.x, c.y - a.y),
                             (d.x - a.x, d.y - a.y)]),
              dirOf([(d.x - c.x, d.y - c.y), (d.x - b.x, d.y - b.y), (d.x - a.x, d.y - a.y)]))

proc pQuad(p: var PathB; m: DOMMatrix; cx, cy, x, y: float) =
  if not p.hasCur: p.pMoveTo(m, cx, cy)
  p.flatQuad(p.cur, clampFar(m.apply(cx, cy)), clampFar(m.apply(x, y)))

proc pCubic(p: var PathB; m: DOMMatrix; c1x, c1y, c2x, c2y, x, y: float) =
  if not p.hasCur: p.pMoveTo(m, c1x, c1y)
  p.flatCubic(p.cur, clampFar(m.apply(c1x, c1y)), clampFar(m.apply(c2x, c2y)),
              clampFar(m.apply(x, y)))

proc pClose(p: var PathB) =
  if p.subs.len > 0 and p.subs[^1].pts.len > 0:
    p.subs[^1].closed = true

proc pEllipse(p: var PathB; m: DOMMatrix; cx, cy, rx, ry, rot, a0, a1: float; ccw: bool) =
  ## An elliptic arc from angle `a0` to `a1` (radians), joined to the path
  ## by a line, as HTML's ellipse() and arc() do.
  if rx < 0 or ry < 0: return
  var sweep: float
  let tau = 2 * PI
  if not ccw and a1 - a0 >= tau: sweep = tau
  elif ccw and a0 - a1 >= tau: sweep = -tau
  else:
    if not ccw:
      sweep = (a1 - a0) mod tau
      if sweep < 0: sweep += tau
    else:
      sweep = (a0 - a1) mod tau
      if sweep < 0: sweep += tau
      sweep = -sweep
  let cr = cos(rot)
  let sr = sin(rot)
  proc at(t: float): Vec =
    let ex = rx * cos(t)
    let ey = ry * sin(t)
    (cx + cr * ex - sr * ey, cy + sr * ex + cr * ey)
  proc der(t: float): Vec =
    let ex = -rx * sin(t)
    let ey = ry * cos(t)
    (cr * ex - sr * ey, sr * ex + cr * ey)
  let s = at(a0)
  if p.hasCur: p.addPt(m.apply(s.x, s.y)) else: p.pMoveTo(m, s.x, s.y)
  if sweep == 0: return
  let n = max(1, toI(ceil(abs(sweep) / (PI / 2) - 1e-9)))
  let step = sweep / float(n)
  let k = 4 / 3 * tan(step / 4)
  var t = a0
  for i in 0 ..< n:
    let t1 = t + step
    let p0 = at(t)
    let p3 = at(t1)
    let d0 = der(t)
    let d1 = der(t1)
    let c1: Vec = (p0.x + k * d0.x, p0.y + k * d0.y)
    let c2: Vec = (p3.x - k * d1.x, p3.y - k * d1.y)
    p.flatCubic(p.cur, clampFar(m.apply(c1.x, c1.y)), clampFar(m.apply(c2.x, c2.y)),
                clampFar(m.apply(p3.x, p3.y)))
    t = t1

proc pArcTo(p: var PathB; m: DOMMatrix; x1, y1, x2, y2, r: float) =
  if r < 0: return
  if not p.hasCur:
    p.pMoveTo(m, x1, y1)
  var ok: bool
  let inv = m.invert(ok)
  if not ok: return
  let c0 = p.cur
  let p0 = inv.apply(c0.x, c0.y)
  let v1 = (p0.x - x1, p0.y - y1)
  let v2 = (x2 - x1, y2 - y1)
  let l1 = hypot(v1[0], v1[1])
  let l2 = hypot(v2[0], v2[1])
  let cross = v1[0] * v2[1] - v1[1] * v2[0]
  if r == 0 or l1 < 1e-9 or l2 < 1e-9 or abs(cross) < 1e-9 * l1 * l2:
    p.pLineTo(m, x1, y1)
    return
  let cosA = (v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2)
  let ang = arccos(clamp(cosA, -1.0, 1.0))
  let dist = r / tan(ang / 2)
  let t1 = (x1 + v1[0] / l1 * dist, y1 + v1[1] / l1 * dist)
  let t2 = (x1 + v2[0] / l2 * dist, y1 + v2[1] / l2 * dist)
  # the center: from t1 along the normal toward the inside of the corner
  var nx = -v1[1] / l1
  var ny = v1[0] / l1
  if nx * v2[0] + ny * v2[1] < 0:
    nx = -nx
    ny = -ny
  let cx = t1[0] + nx * r
  let cy = t1[1] + ny * r
  let a0 = arctan2(t1[1] - cy, t1[0] - cx)
  let a1 = arctan2(t2[1] - cy, t2[0] - cx)
  var d = a1 - a0
  while d > PI: d -= 2 * PI
  while d < -PI: d += 2 * PI
  p.pEllipse(m, cx, cy, r, r, 0, a0, a0 + d, d < 0)

proc pRect(p: var PathB; m: DOMMatrix; x, y, w, h: float) =
  p.pMoveTo(m, x, y)
  p.addPt(m.apply(x + w, y))
  p.addPt(m.apply(x + w, y + h))
  p.addPt(m.apply(x, y + h))
  p.pClose()
  p.pMoveTo(m, x, y)

proc pRoundRect(p: var PathB; m: DOMMatrix; x, y, w, h: float; radii: seq[float]) =
  var x = x
  var y = y
  var w = w
  var h = h
  if w < 0:
    x += w
    w = -w
  if h < 0:
    y += h
    h = -h
  var r: array[4, float]          # top-left, top-right, bottom-right, bottom-left
  case radii.len
  of 0: discard
  of 1: r = [radii[0], radii[0], radii[0], radii[0]]
  of 2: r = [radii[0], radii[1], radii[0], radii[1]]
  of 3: r = [radii[0], radii[1], radii[2], radii[1]]
  else: r = [radii[0], radii[1], radii[2], radii[3]]
  for v in r.mitems: v = if fin(v): max(0.0, v) else: 0.0
  # radii that do not fit are scaled down together (as CSS does)
  var k = 1.0
  for (a, b, side) in [(r[0], r[1], w), (r[3], r[2], w), (r[0], r[3], h), (r[1], r[2], h)]:
    if a + b > side and a + b > 0: k = min(k, side / (a + b))
  for v in r.mitems: v *= k
  p.pMoveTo(m, x + r[0], y)
  p.pLineTo(m, x + w - r[1], y)
  if r[1] > 0: p.pEllipse(m, x + w - r[1], y + r[1], r[1], r[1], 0, -PI / 2, 0, false)
  p.pLineTo(m, x + w, y + h - r[2])
  if r[2] > 0: p.pEllipse(m, x + w - r[2], y + h - r[2], r[2], r[2], 0, 0, PI / 2, false)
  p.pLineTo(m, x + r[3], y + h)
  if r[3] > 0: p.pEllipse(m, x + r[3], y + h - r[3], r[3], r[3], 0, PI / 2, PI, false)
  p.pLineTo(m, x, y + r[0])
  if r[0] > 0: p.pEllipse(m, x + r[0], y + r[0], r[0], r[0], 0, PI, 1.5 * PI, false)
  p.pClose()
  p.pMoveTo(m, x, y)

proc applyOp(p: var PathB; m: DOMMatrix; o: PathOp) =
  let f = o.f
  case o.kind
  of poMove: p.pMoveTo(m, f[0], f[1])
  of poLine: p.pLineTo(m, f[0], f[1])
  of poQuad: p.pQuad(m, f[0], f[1], f[2], f[3])
  of poCubic: p.pCubic(m, f[0], f[1], f[2], f[3], f[4], f[5])
  of poArc: p.pEllipse(m, f[0], f[1], f[2], f[2], 0, f[3], f[4], f[5] != 0)
  of poArcTo: p.pArcTo(m, f[0], f[1], f[2], f[3], f[4])
  of poEllipse: p.pEllipse(m, f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7] != 0)
  of poRect: p.pRect(m, f[0], f[1], f[2], f[3])
  of poRoundRect: p.pRoundRect(m, f[0], f[1], f[2], f[3], o.radii)
  of poClose: p.pClose()

proc polys(p: PathB): seq[seq[Vec]] =
  ## The subpaths as closed polygons (for filling).
  for s in p.subs:
    if s.pts.len >= 3: result.add s.pts

# ---- Path2D ---------------------------------------------------------------------------------------

proc newPath2D*(): Path2D =
  ## An empty path to build and keep.
  Path2D()

proc rec(p: Path2D; o: PathOp) =
  var h = p.h !& ord(o.kind)
  for v in o.f: h = h !& hash(bits(v))
  for v in o.radii: h = h !& hash(bits(v))
  p.h = h
  p.ops.add o

proc finite(xs: varargs[float]): bool =
  for v in xs:
    if not fin(v): return false
  true

proc moveTo*(p: Path2D; x, y: float) =
  ## Starts a new subpath at `x`, `y`.
  if finite(x, y): p.rec PathOp(kind: poMove, f: [x, y, 0, 0, 0, 0, 0, 0])
proc lineTo*(p: Path2D; x, y: float) =
  ## A straight line to `x`, `y`.
  if finite(x, y): p.rec PathOp(kind: poLine, f: [x, y, 0, 0, 0, 0, 0, 0])
proc quadraticCurveTo*(p: Path2D; cpx, cpy, x, y: float) =
  ## A curve to `x`, `y` pulled toward one control point.
  if finite(cpx, cpy, x, y): p.rec PathOp(kind: poQuad, f: [cpx, cpy, x, y, 0, 0, 0, 0])
proc bezierCurveTo*(p: Path2D; cp1x, cp1y, cp2x, cp2y, x, y: float) =
  ## A curve to `x`, `y` pulled toward two control points.
  if finite(cp1x, cp1y, cp2x, cp2y, x, y):
    p.rec PathOp(kind: poCubic, f: [cp1x, cp1y, cp2x, cp2y, x, y, 0, 0])
proc arc*(p: Path2D; x, y, radius, startAngle, endAngle: float; anticlockwise = false) =
  ## An arc of the circle at `x`, `y` from `startAngle` to `endAngle`
  ## (radians, 0 pointing right, growing clockwise on screen).
  if finite(x, y, radius, startAngle, endAngle) and radius >= 0:
    p.rec PathOp(kind: poArc, f: [x, y, radius, startAngle, endAngle,
                                  float(ord(anticlockwise)), 0, 0])
proc arcTo*(p: Path2D; x1, y1, x2, y2, radius: float) =
  ## A rounded corner: toward `x1`, `y1`, turning toward `x2`, `y2`.
  if finite(x1, y1, x2, y2, radius) and radius >= 0:
    p.rec PathOp(kind: poArcTo, f: [x1, y1, x2, y2, radius, 0, 0, 0])
proc ellipse*(p: Path2D; x, y, radiusX, radiusY, rotation, startAngle, endAngle: float;
              anticlockwise = false) =
  ## An arc of an ellipse, turned by `rotation` radians.
  if finite(x, y, radiusX, radiusY, rotation, startAngle, endAngle) and
     radiusX >= 0 and radiusY >= 0:
    p.rec PathOp(kind: poEllipse, f: [x, y, radiusX, radiusY, rotation, startAngle,
                                      endAngle, float(ord(anticlockwise))])
proc rect*(p: Path2D; x, y, w, h: float) =
  ## A closed rectangle.
  if finite(x, y, w, h): p.rec PathOp(kind: poRect, f: [x, y, w, h, 0, 0, 0, 0])
proc roundRect*(p: Path2D; x, y, w, h: float; radii: openArray[float] = [0.0]) =
  ## A closed rectangle with rounded corners: one radius for all, or 2, 3
  ## or 4 (top-left, top-right, bottom-right, bottom-left), as in CSS.
  if finite(x, y, w, h):
    p.rec PathOp(kind: poRoundRect, f: [x, y, w, h, 0, 0, 0, 0], radii: @radii)
proc roundRect*(p: Path2D; x, y, w, h, radius: float) =
  ## A closed rectangle with all corners rounded by `radius`.
  p.roundRect(x, y, w, h, [radius])
proc closePath*(p: Path2D) =
  ## A line back to where the subpath started.
  p.rec PathOp(kind: poClose)
proc addPath*(p, other: Path2D) =
  ## Adds the subpaths of `other`.
  if other != nil and other != p:
    for o in other.ops: p.rec o

# ---- the rasterizer -------------------------------------------------------------------------------
#
# Coverage by signed-area accumulation (font-rs): every edge adds, to the
# cells it crosses, the area to its right; a running sum along a row gives
# each pixel's winding, weighted by how much of the pixel is covered.
# Nonzero takes min(1, |w|), even-odd folds it: exact where one edge
# crosses a pixel, close where several do.

var acc {.threadvar.}: seq[float32]   # (each thread its own: pages drawn on workers)

{.push boundChecks: off, overflowChecks: off.}

proc accLine(a: ptr UncheckedArray[float32]; stride, h: int; x0, y0, x1, y1: float32) =
  if y0 == y1: return
  var (dir, ax, ay, bx, by) =
    if y0 < y1: (1'f32, x0, y0, x1, y1) else: (-1'f32, x1, y1, x0, y0)
  let dxdy = (bx - ax) / (by - ay)
  # x stays between the ends (float32 steps on a nearly flat edge could
  # otherwise wander out of the row)
  let lo = min(ax, bx)
  let hi = max(ax, bx)
  var x = ax
  if ay < 0: x = clamp(x - ay * dxdy, lo, hi)
  let ys = max(0, int(floor(ay)))
  let ye = min(h, int(ceil(by)))
  for y in ys ..< ye:
    let ls = y * stride
    let dy = min(float32(y + 1), by) - max(float32(y), ay)
    var xn = clamp(x + dxdy * dy, lo, hi)
    if dy <= 0:
      x = xn
      continue
    let d = dy * dir
    let (xa, xb) = if x < xn: (x, xn) else: (xn, x)
    let xaf = floor(xa)
    let xai = int(xaf)
    let xbc = ceil(xb)
    let xbi = int(xbc)
    if xbi <= xai + 1:
      let xm = 0.5'f32 * (x + xn) - xaf
      a[ls + xai] += d - d * xm
      a[ls + xai + 1] += d * xm
    else:
      let s = 1'f32 / (xb - xa)
      let x0f = xa - xaf
      let a0 = 0.5'f32 * s * (1 - x0f) * (1 - x0f)
      let x1f = xb - xbc + 1
      let am = 0.5'f32 * s * x1f * x1f
      a[ls + xai] += d * a0
      if xbi == xai + 2:
        a[ls + xai + 1] += d * (1 - a0 - am)
      else:
        let a1 = s * (1.5'f32 - x0f)
        a[ls + xai + 1] += d * (a1 - a0)
        for xi in xai + 2 ..< xbi - 1:
          a[ls + xi] += d * s
        let a2 = a1 + float32(xbi - xai - 3) * s
        a[ls + xbi - 1] += d * (1 - a2 - am)
      a[ls + xbi] += d * am
    x = xn

{.pop.}

proc addEdge(a: ptr UncheckedArray[float32]; stride, w, h: int; x0, y0, x1, y1: float) =
  ## An edge in the area's coordinates; what lies left of the area is
  ## pressed against its left side (it still counts), right of it is cut.
  if y0 == y1 or not (fin(x0) and fin(y0) and fin(x1) and fin(y1)): return
  if max(y0, y1) <= 0 or min(y0, y1) >= float(h): return
  let fw = float(w)
  let dx = x1 - x0
  if x0 >= 0 and x1 >= 0 and x0 <= fw and x1 <= fw:
    accLine(a, stride, h, float32(x0), float32(y0), float32(x1), float32(y1))
    return
  # cut where it crosses the left and right sides
  var ts: array[4, float]
  var nt = 0
  ts[nt] = 0.0
  inc nt
  if dx != 0:
    for edgeX in [0.0, fw]:
      let t = (edgeX - x0) / dx
      if t > 0 and t < 1:
        ts[nt] = t
        inc nt
  ts[nt] = 1.0
  inc nt
  if nt == 4 and ts[1] > ts[2]: swap(ts[1], ts[2])
  for i in 0 ..< nt - 1:
    let ta = ts[i]
    let tb = ts[i + 1]
    let ax = clamp(x0 + dx * ta, 0.0, fw)
    let bx = clamp(x0 + dx * tb, 0.0, fw)
    let ay = y0 + (y1 - y0) * ta
    let by = y0 + (y1 - y0) * tb
    accLine(a, stride, h, float32(ax), float32(ay), float32(bx), float32(by))

proc bounds(ps: openArray[seq[Vec]]): tuple[x0, y0, x1, y1: float] =
  result = (Inf, Inf, NegInf, NegInf)
  for p in ps:
    for v in p:
      result.x0 = min(result.x0, v.x)
      result.y0 = min(result.y0, v.y)
      result.x1 = max(result.x1, v.x)
      result.y1 = max(result.y1, v.y)

type Area = tuple[x, y, w, h: int]

proc areaOf(ps: openArray[seq[Vec]]; cw, ch: int; grow = 0; lx = 0, ly = 0): Area =
  ## The pixels the polygons touch, within `lx`, `ly` .. `cw`, `ch`.
  let b = bounds(ps)
  if not (b.x0 <= b.x1): return (0, 0, 0, 0)
  let x0 = clamp(toI(floor(b.x0)) - grow, lx, cw)
  let y0 = clamp(toI(floor(b.y0)) - grow, ly, ch)
  let x1 = clamp(toI(ceil(b.x1)) + 1 + grow, lx, cw)
  let y1 = clamp(toI(ceil(b.y1)) + 1 + grow, ly, ch)
  (x0, y0, max(0, x1 - x0), max(0, y1 - y0))

{.push boundChecks: off, overflowChecks: off.}

proc coverage(ps: openArray[seq[Vec]]; ar: Area; rule: CanvasFillRule; cov: var seq[uint8]) =
  ## How much of each pixel of `ar` the polygons `ps` cover (0..255).
  let stride = ar.w + 2
  let n = stride * ar.h
  if acc.len < n: acc.setLen(n)      # (kept all zero between uses)
  cov.setLen(ar.w * ar.h)
  if ar.w <= 0 or ar.h <= 0: return
  let a = cast[ptr UncheckedArray[float32]](addr acc[0])
  let fx = float(ar.x)
  let fy = float(ar.y)
  for p in ps:
    if p.len < 2: continue
    for i in 0 ..< p.len:
      let q = p[i]
      let r = p[(i + 1) mod p.len]
      addEdge(a, stride, ar.w, ar.h, q.x - fx, q.y - fy, r.x - fx, r.y - fy)
  for y in 0 ..< ar.h:
    var s = 0'f32
    let ro = y * stride
    let co = y * ar.w
    for x in 0 ..< ar.w:
      s += a[ro + x]
      a[ro + x] = 0
      var v = abs(s)
      if rule == frEvenOdd:
        v = v mod 2
        if v > 1: v = 2 - v
      cov[co + x] = uint8(min(1'f32, v) * 255 + 0.5)
    a[ro + ar.w] = 0
    a[ro + ar.w + 1] = 0

proc fillDirect(pm: ptr UncheckedArray[uint32]; cw: int; clip: ptr UncheckedArray[uint8];
                ps: openArray[seq[Vec]]; ar: Area; rule: CanvasFillRule; src: uint32) =
  ## The common case in one pass: polygons filled with one color painted
  ## over, coverage worked out row by row as it is painted.
  let stride = ar.w + 2
  let n = stride * ar.h
  if acc.len < n: acc.setLen(n)
  if ar.w <= 0 or ar.h <= 0: return
  let a = cast[ptr UncheckedArray[float32]](addr acc[0])
  let fx = float(ar.x)
  let fy = float(ar.y)
  for p in ps:
    if p.len < 2: continue
    for i in 0 ..< p.len:
      let q = p[i]
      let r = p[(i + 1) mod p.len]
      addEdge(a, stride, ar.w, ar.h, q.x - fx, q.y - fy, r.x - fx, r.y - fy)
  let opaque = (src shr 24) == 255
  for y in 0 ..< ar.h:
    var s = 0'f32
    let ro = y * stride
    let row = (ar.y + y) * cw + ar.x
    var x = 0
    while x < ar.w:
      s += a[ro + x]
      a[ro + x] = 0
      # the run of pixels up to the next edge has the same coverage
      var e = x + 1
      while e < ar.w and a[ro + e] == 0: inc e
      var v = abs(s)
      var k: uint32
      if rule == frNonZero:
        k = if v >= 0.998'f32: 255'u32 else: uint32(v * 255 + 0.5)
      else:
        v = v mod 2
        if v > 1: v = 2 - v
        k = uint32(v * 255 + 0.5)
      if k != 0:
        if clip != nil:
          for i in row + x ..< row + e:
            let kk = (k * uint32(clip[i]) + 127) div 255
            if kk != 0: pm[i] = over(scaleA(src, kk), pm[i])
        elif k == 255 and opaque:
          for i in row + x ..< row + e: pm[i] = src
        else:
          let sk = scaleA(src, k)
          let ik = 255'u32 - (sk shr 24)
          for i in row + x ..< row + e:
            let d = pm[i]
            let rb = (d and 0x00FF00FF'u32) * ik + 0x00800080'u32
            let ag = ((d shr 8) and 0x00FF00FF'u32) * ik + 0x00800080'u32
            pm[i] = sk + ((((rb + ((rb shr 8) and 0x00FF00FF'u32)) shr 8) and 0x00FF00FF'u32) or
                          ((ag + ((ag shr 8) and 0x00FF00FF'u32)) and 0xFF00FF00'u32))
      x = e
    a[ro + ar.w] = 0
    a[ro + ar.w + 1] = 0

{.pop.}

proc windingAt(ps: openArray[seq[Vec]]; px, py: float): int =
  ## The winding number of the polygons around a point.
  for p in ps:
    if p.len < 2: continue
    for i in 0 ..< p.len:
      let a = p[i]
      let b = p[(i + 1) mod p.len]
      if a.y <= py:
        if b.y > py and (b.x - a.x) * (py - a.y) - (px - a.x) * (b.y - a.y) > 0: inc result
      elif b.y <= py and (b.x - a.x) * (py - a.y) - (px - a.x) * (b.y - a.y) < 0: dec result

# ---- strokes --------------------------------------------------------------------------------------

proc signedArea(p: seq[Vec]): float =
  for i in 0 ..< p.len:
    let a = p[i]
    let b = p[(i + 1) mod p.len]
    result += a.x * b.y - b.x * a.y

proc oriented(p: seq[Vec]): seq[Vec] =
  ## The same polygon, turning the same way as every other stroke piece
  ## (so overlapping pieces add up instead of cancelling).
  if signedArea(p) < 0:
    result = newSeq[Vec](p.len)
    for i in 0 ..< p.len: result[i] = p[p.high - i]
  else: result = p

proc circlePoly(c: Vec; r: float; segs: int): seq[Vec] =
  for i in 0 ..< segs:
    let t = 2 * PI * float(i) / float(segs)
    result.add (c.x + r * cos(t), c.y + r * sin(t))

proc dashed(pts: seq[Vec]; closed: bool; dash: seq[float]; offset: float): seq[seq[Vec]] =
  ## The pieces of a polyline that the dash pattern draws.
  var total = 0.0
  for d in dash: total += d
  if total <= 0: return @[pts]
  var line = pts
  if closed and pts.len > 1: line.add pts[0]
  var idx = 0
  var left = (offset mod total + total) mod total
  # find where the pattern starts
  while left > 0:
    if left >= dash[idx]:
      left -= dash[idx]
      idx = (idx + 1) mod dash.len
    else: break
  var remain = dash[idx] - left
  var on = idx mod 2 == 0
  var piece: seq[Vec]
  if on: piece.add line[0]
  var guard = 0
  for i in 0 ..< line.high:
    var a = line[i]
    let b = line[i + 1]
    var segLen = hypot(b.x - a.x, b.y - a.y)
    while segLen > 0 and guard < 200_000:
      inc guard
      if remain >= segLen:
        remain -= segLen
        if on: piece.add b
        segLen = 0
      else:
        let t = remain / segLen
        let m = (a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        if on:
          piece.add m
          if piece.len >= 2: result.add piece
          piece = @[]
        else:
          piece = @[m]
        segLen -= remain
        a = m
        idx = (idx + 1) mod dash.len
        remain = dash[idx]
        on = not on
  if on and piece.len >= 2: result.add piece

proc arcPoints(res: var seq[Vec]; c: Vec; r, a0, sweep: float; segs: int) =
  ## Points on a circle from angle `a0` turning by `sweep` (both ends
  ## left out).
  let n = max(1, toI(ceil(abs(sweep) / (2 * PI) * float(segs))))
  for i in 1 ..< n:
    let t = a0 + sweep * float(i) / float(n)
    res.add (c.x + r * cos(t), c.y + r * sin(t))

proc strokePolys(pts0: seq[Vec]; closed: bool; hw: float; cap: CanvasLineCap; join: CanvasLineJoin;
                 miterLimit: float; segsFor: proc (r: float): int;
                 t0: Vec = (0.0, 0.0); t1: Vec = (0.0, 0.0)): seq[seq[Vec]] =
  ## The outline of a stroke of half width `hw` along `pts0`: a closed
  ## subpath gives two rings (filled nonzero, the band between them), an
  ## open one a single loop with its caps. At a corner the outer side gets
  ## the join; the inner side passes through the corner point, which keeps
  ## the band whole for any angle.
  var pts: seq[Vec]
  for v in pts0:
    if pts.len == 0 or hypot(v.x - pts[^1].x, v.y - pts[^1].y) > 1e-9: pts.add v
  if closed and pts.len > 1 and hypot(pts[0].x - pts[^1].x, pts[0].y - pts[^1].y) <= 1e-9:
    pts.setLen(pts.len - 1)
  let segs = segsFor(hw)
  if pts.len == 1:
    # a zero-length subpath: a dot with round or square caps
    let c = pts[0]
    case cap
    of lcRound: result.add circlePoly(c, hw, segs)
    of lcSquare:
      result.add @[(c.x - hw, c.y - hw), (c.x + hw, c.y - hw), (c.x + hw, c.y + hw),
                   (c.x - hw, c.y + hw)]
    of lcButt: discard
    return
  if pts.len < 2: return
  let n = pts.len
  let segN = if closed: n else: n - 1
  var dirs = newSeq[Vec](segN)
  var lens = newSeq[float](segN)
  for i in 0 ..< segN:
    let a = pts[i]
    let b = pts[(i + 1) mod n]
    let l = hypot(b.x - a.x, b.y - a.y)
    dirs[i] = ((b.x - a.x) / l, (b.y - a.y) / l)
    lens[i] = l
  # the directions at the open ends: a curve's own, else the end segment's
  proc unit(t, fallback: Vec): Vec =
    let l = hypot(t.x, t.y)
    if fin(l) and l > 1e-12: (t.x / l, t.y / l) else: fallback
  let d0 = unit(t0, dirs[0])
  let dl = unit(t1, dirs[segN - 1])
  proc side(sign: float): seq[Vec] =
    ## The offset line on one side, from the first point to the last.
    result = newSeqOfCap[Vec](n + 8)
    for j in 0 ..< n:
      let p = pts[j]
      let hasPrev = closed or j > 0
      let hasNext = closed or j < n - 1
      if not hasPrev or not hasNext:
        let d = if hasNext: d0 else: dl
        result.add (p.x - d.y * hw * sign, p.y + d.x * hw * sign)
        continue
      let da = dirs[(j - 1 + segN) mod segN]
      let db = dirs[j mod segN]
      let pa = (p.x - da.y * hw * sign, p.y + da.x * hw * sign)
      let pb = (p.x - db.y * hw * sign, p.y + db.x * hw * sign)
      let cross = da.x * db.y - da.y * db.x
      let dot = da.x * db.x + da.y * db.y
      if abs(cross) < 1e-12 and dot > 0:
        result.add pa
        continue
      if dot > 0.94:
        # a slight bend (a flattened curve): where the two offset lines
        # meet, when that point stays on both segments
        let k = 1 / (1 + dot)
        let spill = hw * abs(cross) * k           # hw * tan(angle / 2)
        let la = lens[(j - 1 + segN) mod segN]
        let lb = lens[j mod segN]
        if sign * cross < 0 or spill < 0.5 * min(la, lb):
          result.add (p.x - (da.y + db.y) * hw * sign * k, p.y + (da.x + db.x) * hw * sign * k)
          continue
      if sign * cross > 0:
        # the inner side of the turn: through the corner
        result.add pa
        result.add p
        result.add pb
        continue
      result.add pa
      case join
      of ljBevel: discard
      of ljRound:
        let a0 = arctan2(pa[1] - p.y, pa[0] - p.x)
        let a1 = arctan2(pb[1] - p.y, pb[0] - p.x)
        var sw = a1 - a0                 # the short way round: the outer side
        while sw > PI: sw -= 2 * PI
        while sw < -PI: sw += 2 * PI
        arcPoints(result, p, hw, a0, sw, segs)
      of ljMiter:
        let cosHalf = sqrt(max(0.0, (1 + dot) / 2))
        if cosHalf > 1e-9 and 1 / cosHalf <= miterLimit:
          let mx = -(da.y + db.y)
          let my = da.x + db.x
          let ml = hypot(mx, my)
          if ml > 1e-12:
            let len = hw / cosHalf
            result.add (p.x + mx / ml * len * sign, p.y + my / ml * len * sign)
      result.add pb
  let left = side(1)
  let right = side(-1)
  if closed:
    result.add left
    var r = right
    r.reverse()
    result.add r
    return
  # open: one loop -- the left side, the end cap, the right side back, the
  # start cap
  var loop = left
  if cap == lcSquare:
    loop[0] = (loop[0].x - d0.x * hw, loop[0].y - d0.y * hw)
    loop[^1] = (loop[^1].x + dl.x * hw, loop[^1].y + dl.y * hw)
  var r = right
  if cap == lcSquare:
    r[0] = (r[0].x - d0.x * hw, r[0].y - d0.y * hw)
    r[^1] = (r[^1].x + dl.x * hw, r[^1].y + dl.y * hw)
  if cap == lcRound:
    let e = pts[^1]
    arcPoints(loop, e, hw, arctan2(loop[^1].y - e.y, loop[^1].x - e.x), -PI, segs)
  r.reverse()
  loop.add r
  if cap == lcRound:
    let s0 = pts[0]
    arcPoints(loop, s0, hw, arctan2(loop[^1].y - s0.y, loop[^1].x - s0.x), -PI, segs)
  result.add loop

# ---- the canvas --------------------------------------------------------------------------------

proc defaultState(ratio: float): State =
  State(ctm: DOMMatrix(a: ratio, d: ratio), lineWidth: 1, miterLimit: 10, alpha: 1,
        fill: Paint(kind: paColor, color: 0xFF000000'u32),
        stroke: Paint(kind: paColor, color: 0xFF000000'u32),
        font: "10px sans-serif", fontSize: 10, smoothing: true)

proc fitSize(w, h: int; ratio: float): tuple[w, h: int] =
  var bw = clamp(toI(ceil(float(max(0, w)) * ratio)), 0, MaxSide)
  var bh = clamp(toI(ceil(float(max(0, h)) * ratio)), 0, MaxSide)
  while bw * bh > MaxPixels:
    bw = bw * 3 div 4
    bh = bh * 3 div 4
  (bw, bh)

proc newCanvas2D*(w, h: int; pixelRatio = 1.0): Canvas2D =
  ## A canvas of `w` x `h` (logical pixels) without a window: draw on it,
  ## then take `toBitmap`, `getImageData` or `savePng`. `pixelRatio`:
  ## backing pixels per logical pixel (2 for a sharper picture). Sizes are
  ## capped at 8192 pixels a side.
  let r = if fin(pixelRatio) and pixelRatio > 0: min(pixelRatio, 8.0) else: 1.0
  let (bw, bh) = fitSize(w, h, r)
  result = Canvas2D(w: bw, h: bh, ratio: r, painting: true)
  result.pm = newSeq[uint32](bw * bh)
  result.st = defaultState(r)

proc width*(c: Canvas2D): float = float(c.w) / c.ratio
  ## The canvas's width in logical pixels.
proc height*(c: Canvas2D): float = float(c.h) / c.ratio
  ## The canvas's height in logical pixels.
proc pixelWidth*(c: Canvas2D): int = c.w
  ## The width of its pixels (logical width x `pixelRatio`): what
  ## `getImageData` and `putImageData` count in.
proc pixelHeight*(c: Canvas2D): int = c.h
  ## The height of its pixels.
proc pixelRatio*(c: Canvas2D): float = c.ratio
  ## Backing pixels per logical pixel (the screen's scale in a window).
proc timesRasterized*(c: Canvas2D): int = c.rasterized
  ## How many times the canvas was drawn again from what the app drew (in
  ## a window); stays put while the drawing does not change.

# ---- painting pixels -----------------------------------------------------------------------------

type Sampler = object
  kind: PaintKind
  solid: uint32           # premultiplied, with the global alpha
  alpha: uint32           # 0..255 for gradients and patterns
  inv: DOMMatrix             # backing pixel -> user space
  g: CanvasGradient
  lx, ly, ldx, ldy, linv: float          # linear
  rcx, rcy, rdx, rdy, rr0, rdr, ra: float # radial
  ang: float                             # conic
  pat: CanvasPattern
  smooth: bool

proc samplerFor(c: Canvas2D; p: Paint; alpha: float): Sampler =
  let a8 = uint32(clamp(int(alpha * 255 + 0.5), 0, 255))
  result.kind = p.kind
  result.alpha = a8
  result.smooth = c.st.smoothing
  var ok: bool
  result.inv = c.st.ctm.invert(ok)
  case p.kind
  of paColor: result.solid = scaleA(premul(p.color), a8)
  of paGradient:
    let g = p.grad
    if g == nil or g.stops.len == 0 or not ok:
      result.kind = paColor
      result.solid = 0
      return
    if g.lut.len == 0: buildLut(g)
    result.g = g
    case g.kind
    of gkLinear:
      result.lx = g.x0
      result.ly = g.y0
      result.ldx = g.x1 - g.x0
      result.ldy = g.y1 - g.y0
      let l2 = result.ldx * result.ldx + result.ldy * result.ldy
      if l2 <= 1e-18:
        result.kind = paColor
        result.solid = 0
        return
      result.linv = 1 / l2
    of gkRadial:
      result.rcx = g.x0
      result.rcy = g.y0
      result.rdx = g.x1 - g.x0
      result.rdy = g.y1 - g.y0
      result.rr0 = g.r0
      result.rdr = g.r1 - g.r0
      result.ra = result.rdx * result.rdx + result.rdy * result.rdy - result.rdr * result.rdr
    of gkConic:
      result.rcx = g.x0
      result.rcy = g.y0
      result.ang = g.r0
  of paPattern:
    if p.pat == nil or p.pat.img == nil or p.pat.img.w <= 0 or p.pat.img.h <= 0 or
       p.pat.img.px.len < p.pat.img.w * p.pat.img.h or not ok:
      result.kind = paColor
      result.solid = 0
      return
    result.pat = p.pat

proc lutAt(g: CanvasGradient; t: float): uint32 {.inline.} =
  let i = if t != t or t <= 0: 0 elif t >= 1: LutN - 1 else: int(t * float(LutN - 1) + 0.5)
  g.lut[i]

proc imgPixel(img: Bitmap; x, y: int): uint32 {.inline.} =
  premul(img.px[y * img.w + x])

proc bilinear(img: Bitmap; u, v: float; repX, repY: bool): uint32 =
  ## The picture at `u`, `v` (pixels), blended from the four nearest.
  let fx = u - 0.5
  let fy = v - 0.5
  let x0 = toI(floor(fx))
  let y0 = toI(floor(fy))
  let tx = fx - float(x0)
  let ty = fy - float(y0)
  proc px(x, y: int): uint32 =
    var xx = x
    var yy = y
    if repX: xx = ((xx mod img.w) + img.w) mod img.w
    else: xx = clamp(xx, 0, img.w - 1)
    if repY: yy = ((yy mod img.h) + img.h) mod img.h
    else: yy = clamp(yy, 0, img.h - 1)
    imgPixel(img, xx, yy)
  let p00 = px(x0, y0)
  let p10 = px(x0 + 1, y0)
  let p01 = px(x0, y0 + 1)
  let p11 = px(x0 + 1, y0 + 1)
  var r: uint32
  for sh in [0'u32, 8, 16, 24]:
    let a = float((p00 shr sh) and 255) * (1 - tx) + float((p10 shr sh) and 255) * tx
    let b = float((p01 shr sh) and 255) * (1 - tx) + float((p11 shr sh) and 255) * tx
    r = r or (uint32(clamp(int(a * (1 - ty) + b * ty + 0.5), 0, 255)) shl sh)
  r

proc sample(s: Sampler; px, py: float): uint32 =
  ## The paint at the center of backing pixel (`px`, `py`), premultiplied.
  case s.kind
  of paColor: s.solid
  of paGradient:
    let u = s.inv.apply(px + 0.5, py + 0.5)
    var t: float
    case s.g.kind
    of gkLinear:
      t = ((u.x - s.lx) * s.ldx + (u.y - s.ly) * s.ldy) * s.linv
    of gkRadial:
      let pdx = u.x - s.rcx
      let pdy = u.y - s.rcy
      let b = pdx * s.rdx + pdy * s.rdy + s.rr0 * s.rdr
      let cc = pdx * pdx + pdy * pdy - s.rr0 * s.rr0
      if abs(s.ra) < 1e-12:
        if abs(b) < 1e-12: return 0
        t = cc / (2 * b)
        if s.rr0 + t * s.rdr < 0: return 0
      else:
        let disc = b * b - s.ra * cc
        if disc < 0: return 0
        let sq = sqrt(disc)
        t = (b + sq) / s.ra
        if s.rr0 + t * s.rdr < 0:
          t = (b - sq) / s.ra
          if s.rr0 + t * s.rdr < 0: return 0
    of gkConic:
      t = (arctan2(u.y - s.rcy, u.x - s.rcx) - s.ang) / (2 * PI)
      t = t - floor(t)
    if not fin(t): return 0
    scaleA(lutAt(s.g, t), s.alpha)
  of paPattern:
    let u = s.inv.apply(px + 0.5, py + 0.5)
    let img = s.pat.img
    if (not s.pat.repeatX and (u.x < 0 or u.x >= float(img.w))) or
       (not s.pat.repeatY and (u.y < 0 or u.y >= float(img.h))): return 0
    let c =
      if s.smooth: bilinear(img, u.x, u.y, s.pat.repeatX, s.pat.repeatY)
      else:
        var x = toI(floor(u.x))
        var y = toI(floor(u.y))
        x = ((x mod img.w) + img.w) mod img.w
        y = ((y mod img.h) + img.h) mod img.h
        imgPixel(img, x, y)
    scaleA(c, s.alpha)

proc blendOp(op: CanvasCompositeOp; s, d: uint32): uint32 =
  ## Premultiplied `s` combined with `d` by `op`.
  if op == coSourceOver: return over(s, d)
  var sc, dc: array[4, float]
  for i in 0 .. 3:
    sc[i] = float((s shr (8 * i)) and 255) / 255
    dc[i] = float((d shr (8 * i)) and 255) / 255
  let sa = sc[3]
  let da = dc[3]
  var r: array[4, float]
  proc pd(fa, fb: float): array[4, float] =
    for i in 0 .. 3: result[i] = sc[i] * fa + dc[i] * fb
  case op
  of coSourceOver: r = pd(1, 1 - sa)
  of coSourceIn: r = pd(da, 0)
  of coSourceOut: r = pd(1 - da, 0)
  of coSourceAtop: r = pd(da, 1 - sa)
  of coDestinationOver: r = pd(1 - da, 1)
  of coDestinationIn: r = pd(0, sa)
  of coDestinationOut: r = pd(0, 1 - sa)
  of coDestinationAtop: r = pd(1 - da, sa)
  of coLighter: r = pd(1, 1)
  of coCopy: r = pd(1, 0)
  of coXor: r = pd(1 - da, 1 - sa)
  of coMultiply, coScreen, coDarken, coLighten, coDifference:
    for i in 0 .. 2:
      let b = case op
              of coMultiply: sc[i] * dc[i]
              of coScreen: sc[i] * da + dc[i] * sa - sc[i] * dc[i]
              of coDarken: min(sc[i] * da, dc[i] * sa)
              of coLighten: max(sc[i] * da, dc[i] * sa)
              else: abs(sc[i] * da - dc[i] * sa)
      r[i] = sc[i] * (1 - da) + dc[i] * (1 - sa) + b
    r[3] = sa + da - sa * da
  var o: uint32
  for i in 0 .. 3:
    o = o or (uint32(clamp(int(r[i] * 255 + 0.5), 0, 255)) shl (8 * i))
  # keep it premultiplied (no color above its alpha)
  let a = o shr 24
  for i in 0 .. 2:
    let v = (o shr (8 * i)) and 255
    if v > a: o = (o and not (255'u32 shl (8 * i))) or (a shl (8 * i))
  o

proc isGlobal(op: CanvasCompositeOp): bool {.inline.} =
  op in {coSourceIn, coSourceOut, coDestinationIn, coDestinationAtop, coCopy}

{.push boundChecks: off, overflowChecks: off.}

proc composite(c: Canvas2D; cov: seq[uint8]; ar: Area; s: Sampler; op: CanvasCompositeOp) =
  ## Paints `s` through the coverage `cov` of area `ar`, clipped.
  if c.w <= 0 or c.h <= 0 or c.pm.len == 0: return
  let clip = c.st.clip
  let pm = cast[ptr UncheckedArray[uint32]](addr c.pm[0])
  let solid = s.kind == paColor
  if not isGlobal(op):
    if ar.w <= 0 or ar.h <= 0 or cov.len < ar.w * ar.h: return
    c.dirty = true
    let cp = cast[ptr UncheckedArray[uint8]](unsafeAddr cov[0])
    if solid and op == coSourceOver and clip == nil:
      # the common case, kept short: one color, painted over
      let src = s.solid
      let opaque = (src shr 24) == 255
      for y in 0 ..< ar.h:
        let row = (ar.y + y) * c.w + ar.x
        let crow = y * ar.w
        for x in 0 ..< ar.w:
          let k = uint32(cp[crow + x])
          if k == 0: continue
          let i = row + x
          if k == 255:
            pm[i] = if opaque: src else: over(src, pm[i])
          else: pm[i] = over(scaleA(src, k), pm[i])
      return
    for y in 0 ..< ar.h:
      let row = (ar.y + y) * c.w + ar.x
      let crow = y * ar.w
      for x in 0 ..< ar.w:
        var k = uint32(cp[crow + x])
        if k == 0: continue
        let i = row + x
        if op == coSourceOver:
          if clip != nil:
            k = (k * uint32(clip.a[i]) + 127) div 255
            if k == 0: continue
          let src = if solid: s.solid else: s.sample(float(ar.x + x), float(ar.y + y))
          if k == 255:
            if (src shr 24) == 255: pm[i] = src
            else: pm[i] = over(src, pm[i])
          else: pm[i] = over(scaleA(src, k), pm[i])
        else:
          let src = scaleA(if solid: s.solid else: s.sample(float(ar.x + x), float(ar.y + y)), k)
          let d = pm[i]
          var r = blendOp(op, src, d)
          if clip != nil:
            let ck = uint32(clip.a[i])
            if ck == 0: continue
            if ck < 255: r = over(scaleA(r, ck), scaleA(d, 255 - ck))
          pm[i] = r
    return
  # what the op does outside the shape too (copy, source-in...): the
  # whole canvas, the shape's source where it is
  c.dirty = true
  for y in 0 ..< c.h:
    for x in 0 ..< c.w:
      let i = y * c.w + x
      var ck = 255'u32
      if clip != nil:
        ck = uint32(clip.a[i])
        if ck == 0: continue
      var cv = 0'u32
      if x >= ar.x and x < ar.x + ar.w and y >= ar.y and y < ar.y + ar.h and cov.len > 0:
        cv = uint32(cov[(y - ar.y) * ar.w + (x - ar.x)])
      let src = if cv > 0: scaleA(if solid: s.solid else: s.sample(float(x), float(y)), cv)
                else: 0'u32
      let d = pm[i]
      var r = blendOp(op, src, d)
      if ck < 255: r = over(scaleA(r, ck), scaleA(d, 255 - ck))
      pm[i] = r

{.pop.}

var blurTmp {.threadvar.}: seq[float32]      # the second buffer of a blur (kept)

{.push boundChecks: off, overflowChecks: off.}

proc blur3(buf: var seq[float32]; w, h, r: int) =
  ## Three box blurs of radius `r` (close to a Gaussian of sigma `r`):
  ## along the rows, then down the columns a row at a time with a running
  ## sum per column.
  if r <= 0 or w <= 0 or h <= 0 or buf.len < w * h: return
  if blurTmp.len < w * h: blurTmp.setLen(w * h)
  let k = 1'f32 / float32(2 * r + 1)
  var sums = newSeq[float32](w)
  let sp = cast[ptr UncheckedArray[float32]](addr sums[0])
  for pass in 0 .. 2:
    let a = cast[ptr UncheckedArray[float32]](addr buf[0])
    let t = cast[ptr UncheckedArray[float32]](addr blurTmp[0])
    # rows: buf -> tmp
    for y in 0 ..< h:
      let o = y * w
      var s = 0'f32
      for x in -r .. r: s += a[o + clamp(x, 0, w - 1)]
      for x in 0 ..< w:
        t[o + x] = s * k
        s += a[o + min(x + r + 1, w - 1)] - a[o + max(x - r, 0)]
    # columns: tmp -> buf
    for x in 0 ..< w: sp[x] = 0
    for yy in -r .. r:
      let o = clamp(yy, 0, h - 1) * w
      for x in 0 ..< w: sp[x] += t[o + x]
    for y in 0 ..< h:
      let o = y * w
      let ao = min(y + r + 1, h - 1) * w
      let ro = max(y - r, 0) * w
      for x in 0 ..< w:
        a[o + x] = sp[x] * k
        sp[x] += t[ao + x] - t[ro + x]

proc upsample(lo: seq[float32]; lw, lh, f, x0, y0, w, h: int; dst: var seq[uint8]) =
  ## The part `x0`, `y0`, `w` x `h` (in full-size pixels) of a picture kept
  ## `f` times smaller, scaled up smoothly (bilinear) into `dst` as 0..255.
  if w <= 0 or h <= 0 or lw <= 0 or lh <= 0: return
  let ff = float32(f)
  var ix = newSeq[int](w)
  var tx = newSeq[float32](w)
  var ilo = lw
  var ihi = 0
  for x in 0 ..< w:
    let u = (float32(x0 + x) + 0.5'f32) / ff - 0.5'f32
    let i = clamp(toI(floor(u)), 0, lw - 1)
    ix[x] = i
    tx[x] = clamp(u - float32(i), 0'f32, 1'f32)
    ilo = min(ilo, i)
    ihi = max(ihi, min(i + 1, lw - 1))
  var row = newSeq[float32](lw + 1)
  for y in 0 ..< h:
    let v = (float32(y0 + y) + 0.5'f32) / ff - 0.5'f32
    let iy = clamp(toI(floor(v)), 0, lh - 1)
    let iy1 = min(iy + 1, lh - 1)
    let ty = clamp(v - float32(iy), 0'f32, 1'f32)
    # the two low rows mixed, then across
    for i in ilo .. ihi: row[i] = lo[iy * lw + i] * (1 - ty) + lo[iy1 * lw + i] * ty
    row[lw] = row[lw - 1]
    let o = y * w
    for x in 0 ..< w:
      let i = ix[x]
      let t = tx[x]
      let a = row[i] * (1 - t) + row[i + 1] * t
      dst[o + x] = uint8(min(a, 1'f32) * 255 + 0.5'f32)

{.pop.}

proc paintCov(c: Canvas2D; cov: seq[uint8]; ar: Area; p: Paint) =
  ## A shape's coverage painted with `p`: its shadow first, then itself.
  if ar.w <= 0 or ar.h <= 0:
    if not isGlobal(c.st.op): return
  let st = c.st
  if (st.shadowColor shr 24) != 0 and (st.shadowBlur > 0 or st.shadowX != 0 or st.shadowY != 0) and
     ar.w > 0 and ar.h > 0:
    let r = toI(round(st.shadowBlur / 2 * c.ratio))
    let reach = 3 * r + 1                  # how far three box blurs spread it
    let ox = toI(round(st.shadowX * c.ratio))
    let oy = toI(round(st.shadowY * c.ratio))
    # where the shadow falls on the canvas
    let cx0 = max(0, ar.x - reach + ox)
    let cy0 = max(0, ar.y - reach + oy)
    let cx1 = min(c.w, ar.x + ar.w + reach + ox)
    let cy1 = min(c.h, ar.y + ar.h + reach + oy)
    # and what it is blurred from: that, moved back, and grown by the reach
    let bx0 = cx0 - ox - reach
    let by0 = cy0 - oy - reach
    let bw = cx1 - cx0 + 2 * reach
    let bh = cy1 - cy0 + 2 * reach
    if cx1 > cx0 and cy1 > cy0 and bw * bh <= MaxPixels:
      # a wide blur is made at a lower resolution (f times smaller), then
      # scaled up smoothly: the same look for a fraction of the work
      var f = 1
      var r2 = r
      if r >= 8:
        # the step and the smaller radius that give the same spread
        # (variance r(r+1) of three boxes; f*f/12 more from the averaging)
        let want = float(r * (r + 1))
        var best = Inf
        for ft in max(2, r div 6) .. max(2, r div 3):
          let q = (want - float(ft * ft) / 12) / float(ft * ft)
          let rt = max(1, toI(round((-1 + sqrt(1 + 4 * max(q, 0.0))) / 2)))
          let err = abs(float(ft * ft * rt * (rt + 1)) + float(ft * ft) / 12 - want) / want
          if err < best - 0.01:
            best = err
            f = ft
            r2 = rt
      let lw = (bw + f - 1) div f
      let lh = (bh + f - 1) div f
      var sb = newSeq[float32](lw * lh)
      let unit = 1'f32 / (255'f32 * float32(f * f))
      for y in max(ar.y, by0) ..< min(ar.y + ar.h, by0 + bh):
        let lrow = (y - by0) div f * lw
        let crow = (y - ar.y) * ar.w - ar.x
        for x in max(ar.x, bx0) ..< min(ar.x + ar.w, bx0 + bw):
          sb[lrow + (x - bx0) div f] += float32(cov[crow + x]) * unit
      blur3(sb, lw, lh, r2)
      let cw = cx1 - cx0
      var cut = newSeq[uint8](cw * (cy1 - cy0))
      if f == 1:
        for y in cy0 ..< cy1:
          let row = (y - oy - by0) * bw - ox - bx0
          for x in cx0 ..< cx1:
            cut[(y - cy0) * cw + x - cx0] = uint8(clamp(sb[row + x], 0'f32, 1'f32) * 255 + 0.5)
      else:
        upsample(sb, lw, lh, f, cx0 - ox - bx0, cy0 - oy - by0, cw, cy1 - cy0, cut)
      let shadow = c.samplerFor(Paint(kind: paColor, color: st.shadowColor), st.alpha)
      c.composite(cut, (cx0, cy0, cw, cy1 - cy0), shadow,
                  if isGlobal(st.op): coSourceOver else: st.op)
  if ar.x >= 0 and ar.y >= 0 and ar.x + ar.w <= c.w and ar.y + ar.h <= c.h:
    c.composite(cov, ar, c.samplerFor(p, st.alpha), st.op)
  else:
    # the coverage reaches past the canvas (for a shadow): only what is on it
    let x0 = max(0, ar.x)
    let y0 = max(0, ar.y)
    let x1 = min(c.w, ar.x + ar.w)
    let y1 = min(c.h, ar.y + ar.h)
    let inner: Area = (x0, y0, max(0, x1 - x0), max(0, y1 - y0))
    var cut = newSeq[uint8](inner.w * inner.h)
    for y in 0 ..< inner.h:
      for x in 0 ..< inner.w:
        cut[y * inner.w + x] = cov[(y0 - ar.y + y) * ar.w + x0 - ar.x + x]
    c.composite(cut, inner, c.samplerFor(p, st.alpha), st.op)

var scratch {.threadvar.}: seq[uint8]       # the coverage of the shape being painted

proc rectCoverage(q: seq[Vec]; ar: Area; cov: var seq[uint8]): bool =
  ## An upright rectangle's coverage, worked out directly (fast, exact);
  ## false when `q` is not one.
  if q.len != 4: return false
  let xs = [q[0].x, q[1].x, q[2].x, q[3].x]
  let ys = [q[0].y, q[1].y, q[2].y, q[3].y]
  let x0 = min(xs)
  let x1 = max(xs)
  let y0 = min(ys)
  let y1 = max(ys)
  for i in 0 .. 3:
    if (xs[i] != x0 and xs[i] != x1) or (ys[i] != y0 and ys[i] != y1): return false
    let j = (i + 1) mod 4
    if xs[i] != xs[j] and ys[i] != ys[j]: return false
  cov.setLen(ar.w * ar.h)
  if ar.w <= 0 or ar.h <= 0: return true
  var colK = newSeq[float32](ar.w)
  for x in 0 ..< ar.w:
    let px = float(ar.x + x)
    colK[x] = float32(max(0.0, min(px + 1, x1) - max(px, x0)))
  for y in 0 ..< ar.h:
    let py = float(ar.y + y)
    let rk = float32(max(0.0, min(py + 1, y1) - max(py, y0)))
    let o = y * ar.w
    for x in 0 ..< ar.w: cov[o + x] = uint8(colK[x] * rk * 255 + 0.5)
  true

proc toCov(f: seq[float32]): seq[uint8] =
  result = newSeq[uint8](f.len)
  for i, v in f: result[i] = uint8(clamp(v, 0'f32, 1'f32) * 255 + 0.5)

proc fillPolys(c: Canvas2D; ps: seq[seq[Vec]]; rule: CanvasFillRule; p: Paint) =
  var ar = areaOf(ps, c.w, c.h)
  let st = c.st
  if ps.len == 1 and ps[0].len == 4 and p.kind == paColor and st.op == coSourceOver and
     st.clip == nil and (st.shadowColor shr 24) == 0 and c.pm.len > 0:
    # an opaque upright rectangle on whole pixels: filled straight in
    let q = ps[0]
    let xs = [q[0].x, q[1].x, q[2].x, q[3].x]
    let ys = [q[0].y, q[1].y, q[2].y, q[3].y]
    let col = scaleA(premul(p.color), uint32(clamp(int(st.alpha * 255 + 0.5), 0, 255)))
    if (col shr 24) == 255 and xs[0] == floor(xs[0]) and ys[0] == floor(ys[0]) and
       xs[2] == floor(xs[2]) and ys[2] == floor(ys[2]) and
       ((xs[0] == xs[3] and xs[1] == xs[2] and ys[0] == ys[1] and ys[2] == ys[3]) or
        (xs[0] == xs[1] and xs[2] == xs[3] and ys[0] == ys[3] and ys[1] == ys[2])):
      let x0 = clamp(int(min(xs)), 0, c.w)
      let x1 = clamp(int(max(xs)), 0, c.w)
      let y0 = clamp(int(min(ys)), 0, c.h)
      let y1 = clamp(int(max(ys)), 0, c.h)
      for y in y0 ..< y1:
        for x in x0 ..< x1: c.pm[y * c.w + x] = col
      if x1 > x0 and y1 > y0: c.dirty = true
      return
  if p.kind == paColor and st.op == coSourceOver and (st.shadowColor shr 24) == 0 and
     c.pm.len > 0:
    let src = scaleA(premul(p.color), uint32(clamp(int(st.alpha * 255 + 0.5), 0, 255)))
    if ar.w > 0 and ar.h > 0 and src != 0:
      let clip = if st.clip == nil: nil
                 else: cast[ptr UncheckedArray[uint8]](addr st.clip.a[0])
      fillDirect(cast[ptr UncheckedArray[uint32]](addr c.pm[0]), c.w, clip, ps, ar, rule, src)
      c.dirty = true
    return
  if (st.shadowColor shr 24) != 0 and (st.shadowBlur > 0 or st.shadowX != 0 or st.shadowY != 0):
    # a shape off the canvas may still cast its shadow on it
    let pad = 3 * toI(round(st.shadowBlur / 2 * c.ratio)) + 1
    let ox = toI(round(st.shadowX * c.ratio))
    let oy = toI(round(st.shadowY * c.ratio))
    let lx = min(0, -ox - pad)
    let ly = min(0, -oy - pad)
    let hx = max(c.w, c.w - ox + pad)
    let hy = max(c.h, c.h - oy + pad)
    if (hx - lx) * (hy - ly) <= 4_194_304:
      ar = areaOf(ps, hx, hy, lx = lx, ly = ly)
  if not (ps.len == 1 and rectCoverage(ps[0], ar, scratch)):
    coverage(ps, ar, rule, scratch)
  c.paintCov(scratch, ar, p)

proc segsFor(r: float): int = clamp(toI(ceil(PI / arccos(clamp(1 - Tol / max(r, Tol), -1.0, 1.0)))), 8, 512)

proc strokeOutline(c: Canvas2D; path: PathB): seq[seq[Vec]] =
  ## The stroke of `path` with the current line style, as polygons in
  ## backing pixels: made in user space (so a scaled transform scales the
  ## width), then transformed.
  let st = c.st
  if not fin(st.lineWidth) or st.lineWidth <= 0: return
  var ok: bool
  let inv = st.ctm.invert(ok)
  if not ok: return
  let hw = min(st.lineWidth / 2, 1e6)
  let m = st.ctm
  let scale = sqrt(abs(m.a * m.d - m.b * m.c))
  # the subpaths in user space; how many dash pieces they would make (a
  # pattern finer than 20000 pieces in one stroke draws a solid line)
  var users = newSeq[seq[Vec]](path.subs.len)
  var dashes = newSeq[bool](path.subs.len)
  var total = 0.0
  for d in st.dash: total += d
  var piecesLeft = 20_000.0
  var work = 0
  for k, sp in path.subs:
    var u = newSeq[Vec](sp.pts.len)
    for i, v in sp.pts: u[i] = inv.apply(v.x, v.y)
    work += u.len
    if st.dash.len > 0 and total > 0:
      var len = 0.0
      for i in 1 ..< u.len: len += hypot(u[i].x - u[i - 1].x, u[i].y - u[i - 1].y)
      if sp.closed and u.len > 1: len += hypot(u[0].x - u[^1].x, u[0].y - u[^1].y)
      let n = len / total * float(st.dash.len) + 2
      if fin(n) and n <= piecesLeft:
        piecesLeft -= n
        dashes[k] = true
        work += 2 * int(n)
    users[k] = move u
  # round joins and caps get fewer points when there are very many of them
  let budget = max(8, 2_000_000 div max(1, work))
  proc segs(r: float): int = min(segsFor(r * scale), budget)
  for k, sp in path.subs:
    let u = users[k]
    let t0: Vec = (inv.a * sp.t0.x + inv.c * sp.t0.y, inv.b * sp.t0.x + inv.d * sp.t0.y)
    let t1: Vec = (inv.a * sp.t1.x + inv.c * sp.t1.y, inv.b * sp.t1.x + inv.d * sp.t1.y)
    var pieces: seq[tuple[pts: seq[Vec]; closed: bool]]
    if dashes[k]:
      for d in dashed(u, sp.closed, st.dash, st.dashOffset): pieces.add (d, false)
    else: pieces.add (u, sp.closed)
    for (pp, cl) in pieces:
      let whole = not dashes[k]
      for poly in strokePolys(pp, cl, hw, st.cap, st.join, st.miterLimit, segs,
                              if whole: t0 else: (0.0, 0.0), if whole: t1 else: (0.0, 0.0)):
        var dev = newSeq[Vec](poly.len)
        for i, v in poly: dev[i] = clampFar(m.apply(v.x, v.y))
        result.add dev

# ---- text ----------------------------------------------------------------------------------------

type
  GlyphKey = tuple[face: FaceId; gid: uint16; size: int32; frac: int8; hint: bool]
  MaskRef = ref Mask
var glyphCache {.threadvar.}: Table[GlyphKey, MaskRef]
var glyphBytes {.threadvar.}: int

proc glyphMask(f: FaceId; gid: uint16; size: float; frac: float; hint: bool): MaskRef =
  ## A glyph rendered at `size` backing pixels (kept: up to ~48 MB of them):
  ## fitted to the pixels when `hint` (small upright text); a style the
  ## font lacks made bold or slanted.
  let key = (f, gid, int32(round(size * 16)), int8(round(frac * 4)), hint)
  glyphCache.withValue(key, m):
    return m[]
  if glyphCache.len > 4000 or glyphBytes > 48_000_000:
    glyphCache.clear()
    glyphBytes = 0
  result = MaskRef()
  let fx = fauxStyle(f)
  let fc = face(f)
  result[] = fc.render(int(gid), float32(size), float32(round(frac * 4) / 4),
                       if fx.italic: 0.2'f32 else: 0'f32,
                       embolden = (if fx.bold: float32(size) * FauxBoldEm else: 0'f32),
                       hint = hint, fitStems = hint, bold = isBold(f),
                       darken = (if hint: fc.darkening(float32(size)) else: 0'f32))
  glyphBytes += result.a.len + 64
  glyphCache[key] = result

proc parseFont(c: Canvas2D; s: string): bool =
  ## "bold italic 16px sans-serif", "12pt monospace", "1.5em sans".
  var size = -1.0
  var bold, italic, mono, serif, sans = false
  for tok0 in s.toLowerAscii.replace(",", " ").splitWhitespace:
    let tok = tok0.strip(chars = {'"', '\''})
    if tok in ["bold", "bolder", "600", "700", "800", "900"]: bold = true
    elif tok in ["italic", "oblique"]: italic = true
    elif tok in ["normal", "lighter", "100", "200", "300", "400", "500", "small-caps"]: discard
    elif tok.endsWith("px") or tok.endsWith("pt") or tok.endsWith("em") or tok.endsWith("rem"):
      var numPart = tok
      var k = 1.0
      if tok.endsWith("rem"):
        numPart = tok[0 ..< ^3]
        k = 16
      elif tok.endsWith("px"): numPart = tok[0 ..< ^2]
      elif tok.endsWith("pt"):
        numPart = tok[0 ..< ^2]
        k = 4 / 3
      else:
        numPart = tok[0 ..< ^2]
        k = 16
      let slash = numPart.find('/')                 # "16px/20px": the line height left out
      if slash >= 0: numPart = numPart[0 ..< slash]
      try: size = parseFloat(numPart) * k
      except ValueError: return false
    elif "mono" in tok or tok in ["courier", "consolas", "menlo", "monaco"]: mono = true
    elif tok in ["serif", "ui-serif", "times", "georgia", "freeserif", "cambria", "garamond", "palatino"]:
      serif = true
    elif tok in ["freesans", "helvetica", "arial", "nimbus"]: sans = true
  if size <= 0 or not fin(size): return false
  c.st.fontSize = min(size, 2000)
  c.st.bold = bold
  c.st.italic = italic
  c.st.mono = mono
  # (named, FreeSans and FreeSerif; "sans-serif", "system-ui" and the
  # rest are the UI's font)
  c.st.serif = serif and not mono
  c.st.sans = sans and not mono and not serif
  c.st.font = s
  true

proc faceFor(st: State): FaceId =
  if st.mono: styled(fMono, st.bold, st.italic)
  elif st.serif: styled(fSerif, st.bold, st.italic)
  elif st.sans: styled(fSans, st.bold, st.italic)
  else: faceOf(style(bold = st.bold, italic = st.italic))

proc dirOf(st: auto): int {.inline.} =
  ## (`shape`'s direction for the state's `direction`: -1 from the text)
  case st.dir
  of cdRtl: 1
  of cdLtr: 0
  of cdInherit: -1

proc textMatrix(c: Canvas2D; s: string; x, y, maxWidth: float; run: Run): DOMMatrix =
  ## Where the text goes: the transform from its own space (one unit a
  ## pixel of the font size, baseline at 0) to backing pixels.
  let st = c.st
  let px = st.fontSize
  let f = face(faceFor(st))
  let upem = float(f.unitsPerEm)
  let asc = float(f.ascent) / upem * px
  let desc = -float(f.descent) / upem * px
  let w = float(run.width) * px
  var sx = 1.0
  if fin(maxWidth) and maxWidth > 0 and w > maxWidth: sx = maxWidth / w
  let ww = w * sx
  let ox = case st.align
           of taLeft: 0.0
           of taRight: -ww
           of taCenter: -ww / 2
           of taStart: (if st.dir == cdRtl: -ww else: 0.0)   # ("inherit": left to
           of taEnd: (if st.dir == cdRtl: 0.0 else: -ww)     # right, a browser's default)
  let oy = case st.baseline
           of tbAlphabetic: 0.0
           of tbTop: asc
           of tbHanging: asc * 0.8
           of tbMiddle: (asc - desc) / 2
           of tbIdeographic, tbBottom: -desc
  mul(st.ctm, DOMMatrix(a: sx, d: 1, e: x + ox, f: y + oy))

proc textCoverage(c: Canvas2D; s: string; x, y, maxWidth: float;
                  cov: var seq[float32]): Area =
  ## The coverage of `s` drawn at `x`, `y` with the current font.
  if c.w <= 0 or c.h <= 0: return (0, 0, 0, 0)
  let st = c.st
  let fid = faceFor(st)
  let run = shape(s, fid, dirOf(st))
  if run.glyphs.len == 0: return (0, 0, 0, 0)
  let px = st.fontSize
  let m = c.textMatrix(s, x, y, maxWidth, run)
  let axis = abs(m.b) < 1e-9 and abs(m.c) < 1e-9 and m.a > 0 and m.d > 0 and
             abs(m.a - m.d) <= 1e-6 * m.d
  # the glyphs' masks and where they go
  type Placed = tuple[mask: MaskRef; ox, oy: float]   # mask origin (pen) in text space
  var placed: seq[Placed]
  var minX, minY = Inf
  var maxX, maxY = NegInf
  let scale = if axis: m.a else: sqrt(abs(m.a * m.d - m.b * m.c))
  let size = px * scale
  if not fin(size) or size <= 0.5 or size > 4000: return (0, 0, 0, 0)
  # glyphs farther than this from the canvas are left out
  let reach = 2 * px * max(hypot(m.a, m.b), hypot(m.c, m.d)) + 2
  for g in run.glyphs:
    let gx = float(g.x) * px
    let gy = -float(g.y) * px
    let pen = m.apply(gx, gy)
    if not (pen.x > -reach and pen.y > -reach and pen.x < float(c.w) + reach and
            pen.y < float(c.h) + reach):
      continue
    if axis:
      let dev = m.apply(gx, gy)
      let ix = floor(dev.x)
      let mask = glyphMask(g.face, g.gid, size, dev.x - ix, size < 30)
      if mask.w <= 0: continue
      placed.add (mask, ix, round(dev.y))
      minX = min(minX, ix + float(mask.left))
      minY = min(minY, round(dev.y) + float(mask.top))
      maxX = max(maxX, ix + float(mask.left + mask.w))
      maxY = max(maxY, round(dev.y) + float(mask.top + mask.h))
    else:
      let mask = glyphMask(g.face, g.gid, size, 0, false)
      if mask.w <= 0: continue
      placed.add (mask, gx, gy)
      for (cx, cy) in [(mask.left, mask.top), (mask.left + mask.w, mask.top),
                       (mask.left, mask.top + mask.h), (mask.left + mask.w, mask.top + mask.h)]:
        let d = m.apply(gx + float(cx) / scale, gy + float(cy) / scale)
        minX = min(minX, d.x)
        minY = min(minY, d.y)
        maxX = max(maxX, d.x)
        maxY = max(maxY, d.y)
  if placed.len == 0 or not (minX <= maxX): return (0, 0, 0, 0)
  let ax0 = clamp(toI(floor(minX)) - 1, 0, c.w)
  let ay0 = clamp(toI(floor(minY)) - 1, 0, c.h)
  let ax1 = clamp(toI(ceil(maxX)) + 1, 0, c.w)
  let ay1 = clamp(toI(ceil(maxY)) + 1, 0, c.h)
  result = (ax0, ay0, max(0, ax1 - ax0), max(0, ay1 - ay0))
  cov = newSeq[float32](result.w * result.h)
  if result.w == 0 or result.h == 0: return
  var ok: bool
  let inv = m.invert(ok)
  for (mask, ox, oy) in placed:
    if axis:
      let mx0 = int(ox) + mask.left
      let my0 = int(oy) + mask.top
      for yy in 0 ..< mask.h:
        let cy = my0 + yy - result.y
        if cy < 0 or cy >= result.h: continue
        for xx in 0 ..< mask.w:
          let cx = mx0 + xx - result.x
          if cx < 0 or cx >= result.w: continue
          let v = float32(mask.a[yy * mask.w + xx]) / 255
          let i = cy * result.w + cx
          if v > cov[i]: cov[i] = v
    elif ok:
      # every backing pixel the glyph may touch: its mask sampled back
      var bx0, by0 = Inf
      var bx1, by1 = NegInf
      for (cx, cy) in [(mask.left, mask.top), (mask.left + mask.w, mask.top),
                       (mask.left, mask.top + mask.h), (mask.left + mask.w, mask.top + mask.h)]:
        let d = m.apply(ox + float(cx) / scale, oy + float(cy) / scale)
        bx0 = min(bx0, d.x); by0 = min(by0, d.y)
        bx1 = max(bx1, d.x); by1 = max(by1, d.y)
      for py in max(result.y, toI(floor(by0))) ..< min(result.y + result.h, toI(ceil(by1)) + 1):
        for pxx in max(result.x, toI(floor(bx0))) ..< min(result.x + result.w, toI(ceil(bx1)) + 1):
          let u = inv.apply(float(pxx) + 0.5, float(py) + 0.5)
          let mx = (u.x - ox) * scale - float(mask.left) - 0.5
          let my = (u.y - oy) * scale - float(mask.top) - 0.5
          let ix = toI(floor(mx))
          let iy = toI(floor(my))
          if ix < -1 or iy < -1 or ix >= mask.w or iy >= mask.h: continue
          let tx = mx - float(ix)
          let ty = my - float(iy)
          template at(x, y: int): float =
            (if x < 0 or y < 0 or x >= mask.w or y >= mask.h: 0.0
             else: float(mask.a[y * mask.w + x]) / 255)
          let v = (at(ix, iy) * (1 - tx) + at(ix + 1, iy) * tx) * (1 - ty) +
                  (at(ix, iy + 1) * (1 - tx) + at(ix + 1, iy + 1) * tx) * ty
          let i = (py - result.y) * result.w + pxx - result.x
          if float32(v) > cov[i]: cov[i] = float32(v)

proc outlineCov(cov: var seq[float32]; ar: Area; r: int) =
  ## The edge band of a coverage, `r` pixels each way (strokeText).
  if r <= 0 or ar.w <= 0 or ar.h <= 0: return
  var mx = cov
  var mn = cov
  # separable max (dilate) and min (erode)
  proc filt(a: var seq[float32]; useMax: bool) =
    var t = a
    for y in 0 ..< ar.h:
      for x in 0 ..< ar.w:
        var v = a[y * ar.w + x]
        for k in max(0, x - r) .. min(ar.w - 1, x + r):
          let q = a[y * ar.w + k]
          v = if useMax: max(v, q) else: min(v, q)
        t[y * ar.w + x] = v
    for y in 0 ..< ar.h:
      for x in 0 ..< ar.w:
        var v = t[y * ar.w + x]
        for k in max(0, y - r) .. min(ar.h - 1, y + r):
          let q = t[k * ar.w + x]
          v = if useMax: max(v, q) else: min(v, q)
        a[y * ar.w + x] = v
  filt(mx, true)
  filt(mn, false)
  for i in 0 ..< cov.len: cov[i] = clamp(mx[i] - mn[i], 0'f32, 1'f32)

# ---- running the drawing ---------------------------------------------------------------------------

proc hashPaint(h: var Hash; p: Paint) =
  h = h !& ord(p.kind) !& hash(p.color)
  if p.grad != nil:
    h = h !& ord(p.grad.kind) !& hash(bits(p.grad.x0)) !& hash(bits(p.grad.y0)) !&
        hash(bits(p.grad.r0)) !& hash(bits(p.grad.x1)) !& hash(bits(p.grad.y1)) !&
        hash(bits(p.grad.r1))
    for s in p.grad.stops: h = h !& hash(bits(s.t)) !& hash(s.c)
  if p.pat != nil and p.pat.img != nil:
    h = h !& hash(cast[uint](p.pat.img)) !& hash(stampOf(p.pat.img)) !&
        ord(p.pat.repeatX) !& ord(p.pat.repeatY)

proc hashOp(h: var Hash; o: Op) =
  h = h !& ord(o.kind) !& o.n !& hash(o.u)
  for v in o.f: h = h !& hash(bits(v))
  if o.s.len > 0: h = h !& hash(o.s)
  for v in o.fl: h = h !& hash(bits(v))
  if o.kind == okPath:
    h = h !& ord(o.po.kind)
    for v in o.po.f: h = h !& hash(bits(v))
    for v in o.po.radii: h = h !& hash(bits(v))
  if o.kind in {okFillStyle, okStrokeStyle}: hashPaint(h, o.paint)
  if o.path != nil: h = h !& o.path.h !& o.path.ops.len
  if o.img != nil: h = h !& hash(cast[uint](o.img)) !& hash(stampOf(o.img)) !& o.img.w !& o.img.h
  if o.data != nil:
    h = h !& o.data.width !& o.data.height !& hash(o.data.data)

proc pathFor(c: Canvas2D; o: Op): PathB =
  if o.path == nil: return c.path
  for po in o.path.ops: result.applyOp(c.st.ctm, po)

proc drawImageOp(c: Canvas2D; o: Op) =
  let img = o.img
  if img == nil or img.w <= 0 or img.h <= 0 or img.px.len < img.w * img.h: return
  var sx = o.f[0]
  var sy = o.f[1]
  var sw = o.f[2]
  var sh = o.f[3]
  let dx = o.f[4]
  let dy = o.f[5]
  let dw = o.f[6]
  let dh = o.f[7]
  if sw == 0 or sh == 0 or dw == 0 or dh == 0: return
  # the source picture, mapped onto the destination rectangle
  let toDest = DOMMatrix(a: dw / sw, d: dh / sh, e: dx - sx * dw / sw, f: dy - sy * dh / sh)
  let m = mul(c.st.ctm, toDest)
  var ok: bool
  let inv = m.invert(ok)
  if not ok: return
  let corners = @[m.apply(sx, sy), m.apply(sx + sw, sy), m.apply(sx + sw, sy + sh),
                  m.apply(sx, sy + sh)]
  var quad: seq[Vec]
  for v in corners: quad.add clampFar(v)
  let ps = @[quad]
  let ar = areaOf(ps, c.w, c.h)
  var cov: seq[uint8]
  coverage(ps, ar, frNonZero, cov)
  let a8 = uint32(clamp(int(c.st.alpha * 255 + 0.5), 0, 255))
  let x0s = min(sx, sx + sw)
  let x1s = max(sx, sx + sw)
  let y0s = min(sy, sy + sh)
  let y1s = max(sy, sy + sh)
  # the picture's colors through the coverage, pixel by pixel
  var colored = newSeq[uint32](ar.w * ar.h)
  for y in 0 ..< ar.h:
    for x in 0 ..< ar.w:
      if cov[y * ar.w + x] == 0: continue
      let u = inv.apply(float(ar.x + x) + 0.5, float(ar.y + y) + 0.5)
      let ux = clamp(u.x, x0s, x1s - 1e-6)
      let uy = clamp(u.y, y0s, y1s - 1e-6)
      let p =
        if c.st.smoothing and (abs(m.a) > 1.01 or abs(m.d) > 1.01 or abs(m.b) > 0.01 or
                               abs(m.c) > 0.01 or abs(m.a) < 0.99 or abs(m.d) < 0.99):
          bilinear(img, ux, uy, false, false)
        else:
          imgPixel(img, clamp(toI(floor(ux)), 0, img.w - 1), clamp(toI(floor(uy)), 0, img.h - 1))
      colored[y * ar.w + x] = scaleA(p, a8)
  # composite (a paint that reads the colors made above)
  let clip = c.st.clip
  let global = isGlobal(c.st.op)
  let (x0, y0, x1, y1) = if global: (0, 0, c.w, c.h) else: (ar.x, ar.y, ar.x + ar.w, ar.y + ar.h)
  if x1 <= x0 or y1 <= y0 or c.pm.len == 0: return
  c.dirty = true
  for y in y0 ..< y1:
    for x in x0 ..< x1:
      let inside = x >= ar.x and x < ar.x + ar.w and y >= ar.y and y < ar.y + ar.h
      let cv = if inside: uint32(cov[(y - ar.y) * ar.w + x - ar.x]) else: 0'u32
      if cv == 0 and not global: continue
      var k = 255'u32
      if clip != nil:
        k = uint32(clip.a[y * c.w + x])
        if k == 0: continue
      let src = if inside and cv > 0: scaleA(colored[(y - ar.y) * ar.w + x - ar.x], cv)
                else: 0'u32
      let i = y * c.w + x
      let d = c.pm[i]
      var r = blendOp(c.st.op, src, d)
      if k < 255: r = over(scaleA(r, k), scaleA(d, 255 - k))
      c.pm[i] = r

proc exec(c: Canvas2D; o: Op) =
  ## What an operation does: to the state and the path always, to the
  ## pixels when the canvas is painting.
  let f = o.f
  case o.kind
  of okSave:
    if c.stack.len < MaxStack: c.stack.add c.st
  of okRestore:
    if c.stack.len > 0: c.st = c.stack.pop()
  of okSetTransform:
    c.st.ctm = mul(DOMMatrix(a: c.ratio, d: c.ratio),
                   DOMMatrix(a: f[0], b: f[1], c: f[2], d: f[3], e: f[4], f: f[5]))
  of okTransform:
    c.st.ctm = mul(c.st.ctm, DOMMatrix(a: f[0], b: f[1], c: f[2], d: f[3], e: f[4], f: f[5]))
  of okResetTransform: c.st.ctm = DOMMatrix(a: c.ratio, d: c.ratio)
  of okFillStyle: c.st.fill = o.paint
  of okStrokeStyle: c.st.stroke = o.paint
  of okLineWidth: c.st.lineWidth = f[0]
  of okCap: c.st.cap = CanvasLineCap(o.n)
  of okJoin: c.st.join = CanvasLineJoin(o.n)
  of okMiter: c.st.miterLimit = f[0]
  of okDash: c.st.dash = o.fl
  of okDashOffset: c.st.dashOffset = f[0]
  of okAlpha: c.st.alpha = f[0]
  of okComposite: c.st.op = CanvasCompositeOp(o.n)
  of okFont: discard c.parseFont(o.s)
  of okAlign: c.st.align = CanvasTextAlign(o.n)
  of okBaseline: c.st.baseline = CanvasTextBaseline(o.n)
  of okDirection: c.st.dir = CanvasDirection(o.n)
  of okShadowColor: c.st.shadowColor = o.u
  of okShadowBlur: c.st.shadowBlur = f[0]
  of okShadowX: c.st.shadowX = f[0]
  of okShadowY: c.st.shadowY = f[0]
  of okSmoothing: c.st.smoothing = o.n != 0
  of okBeginPath: c.path = PathB()
  of okPath: c.path.applyOp(c.st.ctm, o.po)
  of okClip:
    # (only the pixels use the clip: nothing to do until they are painted)
    if not c.painting or c.pm.len == 0: return
    let p = c.pathFor(o)
    var cov: seq[uint8]
    let ps = polys(p)
    let ar = areaOf(ps, c.w, c.h)
    coverage(ps, ar, CanvasFillRule(o.n), cov)
    let old = c.st.clip
    let m = ClipMask(a: newSeq[uint8](c.w * c.h))
    for y in ar.y ..< ar.y + ar.h:
      for x in ar.x ..< ar.x + ar.w:
        let i = y * c.w + x
        let prev = if old == nil: 255'u32 else: uint32(old.a[i])
        m.a[i] = uint8((prev * uint32(cov[(y - ar.y) * ar.w + x - ar.x]) + 127) div 255)
    c.st.clip = m
  else:
    if not c.painting or c.pm.len == 0: return
    case o.kind
    of okFill: c.fillPolys(polys(c.pathFor(o)), CanvasFillRule(o.n), c.st.fill)
    of okStroke:
      let ps = c.strokeOutline(c.pathFor(o))
      if ps.len > 0: c.fillPolys(ps, frNonZero, c.st.stroke)
    of okFillRect, okStrokeRect, okClearRect:
      var p: PathB
      p.pRect(c.st.ctm, f[0], f[1], f[2], f[3])
      if o.kind == okFillRect: c.fillPolys(polys(p), frNonZero, c.st.fill)
      elif o.kind == okStrokeRect:
        let ps = c.strokeOutline(p)
        if ps.len > 0: c.fillPolys(ps, frNonZero, c.st.stroke)
      else:
        var cov: seq[uint8]
        let ps = polys(p)
        let ar = areaOf(ps, c.w, c.h)
        coverage(ps, ar, frNonZero, cov)
        if ar.w > 0 and ar.h > 0: c.dirty = true
        for y in 0 ..< ar.h:
          for x in 0 ..< ar.w:
            var k = uint32(cov[y * ar.w + x])
            if c.st.clip != nil: k = (k * uint32(c.st.clip.a[(ar.y + y) * c.w + ar.x + x]) + 127) div 255
            if k == 0: continue
            let i = (ar.y + y) * c.w + ar.x + x
            c.pm[i] = scaleA(c.pm[i], 255 - k)
    of okFillText, okStrokeText:
      var cov: seq[float32]
      let ar = c.textCoverage(o.s, f[0], f[1], f[2], cov)
      if ar.w <= 0 or ar.h <= 0: return
      if o.kind == okStrokeText:
        let m = c.st.ctm
        let r = max(1, toI(round(c.st.lineWidth / 2 * sqrt(abs(m.a * m.d - m.b * m.c)))))
        # room for the outline around the glyphs
        let gx = max(0, ar.x - r)
        let gy = max(0, ar.y - r)
        let grown: Area = (gx, gy, min(c.w, ar.x + ar.w + r) - gx, min(c.h, ar.y + ar.h + r) - gy)
        var g = newSeq[float32](grown.w * grown.h)
        for y in 0 ..< ar.h:
          for x in 0 ..< ar.w:
            g[(y + ar.y - grown.y) * grown.w + x + ar.x - grown.x] = cov[y * ar.w + x]
        outlineCov(g, grown, r)
        c.paintCov(toCov(g), grown, c.st.stroke)
      else:
        c.paintCov(toCov(cov), ar, c.st.fill)
    of okDrawImage: c.drawImageOp(o)
    of okPutImageData:
      let d = o.data
      if d == nil: return
      let dx = int(f[0])
      let dy = int(f[1])
      let x0 = max(0, int(f[2]))
      let y0 = max(0, int(f[3]))
      let x1 = min(d.width, x0 + int(f[4]))
      let y1 = min(d.height, y0 + int(f[5]))
      for y in y0 ..< y1:
        let ty = dy + y
        if ty < 0 or ty >= c.h: continue
        for x in x0 ..< x1:
          let tx = dx + x
          if tx < 0 or tx >= c.w: continue
          let s = (y * d.width + x) * 4
          if s + 3 >= d.data.len: continue
          let px = (uint32(d.data[s + 3]) shl 24) or (uint32(d.data[s]) shl 16) or
                   (uint32(d.data[s + 1]) shl 8) or uint32(d.data[s + 2])
          c.pm[ty * c.w + tx] = premul(px)
      c.dirty = true
    else: discard

proc run(c: Canvas2D; o: Op) =
  if c.deferred:
    hashOp(c.hash, o)
    c.ops.add o
  c.exec(o)

proc startPainting(c: Canvas2D) =
  ## In a window, mid-frame (image data asked for): the pixels are made now
  ## from what was drawn so far, and the rest of the frame paints directly.
  if c.painting: return
  for p in c.pm.mitems: p = 0
  # the frame's operations again, painting: the state and the path come
  # out as they were (now with the clip, which only painting makes)
  c.st = defaultState(c.ratio)
  c.stack.setLen(0)
  c.path = PathB()
  c.painting = true
  for i in 0 ..< c.ops.len: c.exec(c.ops[i])
  inc c.rasterized
  c.dirty = true

# ---- the context's API -----------------------------------------------------------------------------

proc op(k: OpKind; vals: varargs[float]): Op =
  result = Op(kind: k)
  for i, v in vals:
    if i < 8: result.f[i] = v

proc save*(c: Canvas2D) =
  ## Remembers the state (transform, styles, line, text, clip) to bring
  ## back with `restore`.
  c.run Op(kind: okSave)
proc restore*(c: Canvas2D) =
  ## Brings back the state last saved.
  c.run Op(kind: okRestore)

proc translate*(c: Canvas2D; x, y: float) =
  ## Moves what is drawn next by `x`, `y`.
  if finite(x, y): c.run op(okTransform, 1.0, 0.0, 0.0, 1.0, x, y)
proc scale*(c: Canvas2D; x, y: float) =
  ## Scales what is drawn next.
  if finite(x, y): c.run op(okTransform, x, 0.0, 0.0, y, 0.0, 0.0)
proc rotate*(c: Canvas2D; angle: float) =
  ## Turns what is drawn next by `angle` radians (clockwise on screen).
  if finite(angle): c.run op(okTransform, cos(angle), sin(angle), -sin(angle), cos(angle), 0.0, 0.0)
proc transform*(c: Canvas2D; a, b, cc, d, e, f: float) =
  ## Multiplies the transform by the matrix (a, b, c, d, e, f) as HTML's
  ## transform() does.
  if finite(a, b, cc, d, e, f): c.run op(okTransform, a, b, cc, d, e, f)
proc setTransform*(c: Canvas2D; a, b, cc, d, e, f: float) =
  ## Replaces the transform with (a, b, c, d, e, f).
  if finite(a, b, cc, d, e, f): c.run op(okSetTransform, a, b, cc, d, e, f)
proc setTransform*(c: Canvas2D; m: DOMMatrix) =
  ## Replaces the transform with `m`.
  c.setTransform(m.a, m.b, m.c, m.d, m.e, m.f)
proc resetTransform*(c: Canvas2D) =
  ## Back to no transform.
  c.run Op(kind: okResetTransform)
proc getTransform*(c: Canvas2D): DOMMatrix =
  ## The current transform (in logical pixels).
  let m = c.st.ctm
  let r = c.ratio
  DOMMatrix(a: m.a / r, b: m.b / r, c: m.c / r, d: m.d / r, e: m.e / r, f: m.f / r)

proc colorPaint(s: string; p: var Paint): bool =
  var col: uint32
  if not parseColor(s, col): return false
  p = Paint(kind: paColor, color: col)
  true

proc `fillStyle=`*(c: Canvas2D; s: string) =
  ## The color shapes are filled with: "#ff8800", "rgba(0, 0, 0, 0.5)",
  ## "hsl(120, 50%, 40%)", "gold"... (what is not a color is ignored).
  var p: Paint
  if colorPaint(s, p): c.run Op(kind: okFillStyle, paint: p)
proc `fillStyle=`*(c: Canvas2D; col: Color) =
  ## Fills with a kit `Color`.
  c.run Op(kind: okFillStyle, paint: Paint(kind: paColor, color:
    (uint32(col.a) shl 24) or (uint32(col.r) shl 16) or (uint32(col.g) shl 8) or uint32(col.b)))
proc `fillStyle=`*(c: Canvas2D; g: CanvasGradient) =
  ## Fills with a gradient.
  if g != nil: c.run Op(kind: okFillStyle, paint: Paint(kind: paGradient, grad: g))
proc `fillStyle=`*(c: Canvas2D; p: CanvasPattern) =
  ## Fills with a repeated picture.
  if p != nil: c.run Op(kind: okFillStyle, paint: Paint(kind: paPattern, pat: p))
proc fillStyle*(c: Canvas2D): string =
  ## The fill color as CSS text ("#rrggbb" or "rgba(...)"; "gradient" or
  ## "pattern" for those).
  case c.st.fill.kind
  of paColor: colorText(c.st.fill.color)
  of paGradient: "gradient"
  of paPattern: "pattern"

proc `strokeStyle=`*(c: Canvas2D; s: string) =
  ## The color lines are drawn with (as `fillStyle`).
  var p: Paint
  if colorPaint(s, p): c.run Op(kind: okStrokeStyle, paint: p)
proc `strokeStyle=`*(c: Canvas2D; col: Color) =
  ## Lines in a kit `Color`.
  c.run Op(kind: okStrokeStyle, paint: Paint(kind: paColor, color:
    (uint32(col.a) shl 24) or (uint32(col.r) shl 16) or (uint32(col.g) shl 8) or uint32(col.b)))
proc `strokeStyle=`*(c: Canvas2D; g: CanvasGradient) =
  ## Lines painted with a gradient.
  if g != nil: c.run Op(kind: okStrokeStyle, paint: Paint(kind: paGradient, grad: g))
proc `strokeStyle=`*(c: Canvas2D; p: CanvasPattern) =
  ## Lines painted with a repeated picture.
  if p != nil: c.run Op(kind: okStrokeStyle, paint: Paint(kind: paPattern, pat: p))
proc strokeStyle*(c: Canvas2D): string =
  ## The stroke color as CSS text.
  case c.st.stroke.kind
  of paColor: colorText(c.st.stroke.color)
  of paGradient: "gradient"
  of paPattern: "pattern"

proc sane(x: float): float {.inline.} =
  if fin(x): clamp(x, -1e9, 1e9) else: 0.0

proc createLinearGradient*(c: Canvas2D; x0, y0, x1, y1: float): CanvasGradient =
  ## A gradient along the line from (`x0`, `y0`) to (`x1`, `y1`), in the
  ## coordinates of the shape it fills (the transform when drawing applies).
  CanvasGradient(kind: gkLinear, x0: sane(x0), y0: sane(y0), x1: sane(x1), y1: sane(y1))
proc createRadialGradient*(c: Canvas2D; x0, y0, r0, x1, y1, r1: float): CanvasGradient =
  ## A gradient between two circles (the first at offset 0).
  CanvasGradient(kind: gkRadial, x0: sane(x0), y0: sane(y0), r0: max(0.0, sane(r0)),
                 x1: sane(x1), y1: sane(y1), r1: max(0.0, sane(r1)))
proc createConicGradient*(c: Canvas2D; startAngle, x, y: float): CanvasGradient =
  ## A gradient around the point `x`, `y`, starting at `startAngle`
  ## (radians, clockwise from the right).
  CanvasGradient(kind: gkConic, x0: sane(x), y0: sane(y), r0: sane(startAngle))
proc createPattern*(c: Canvas2D; img: Bitmap; repetition = "repeat"): CanvasPattern =
  ## The picture `img` repeated as a style.
  createPattern(img, repetition)

proc `lineWidth=`*(c: Canvas2D; w: float) =
  ## How wide lines are (0, negative and not-a-number are ignored).
  if fin(w) and w > 0: c.run op(okLineWidth, w)
proc lineWidth*(c: Canvas2D): float = c.st.lineWidth
  ## How wide lines are.
proc `lineCap=`*(c: Canvas2D; v: CanvasLineCap) =
  ## How open line ends look.
  c.run Op(kind: okCap, n: ord(v))
proc `lineCap=`*(c: Canvas2D; v: string) =
  ## "butt", "round" or "square".
  for k in CanvasLineCap:
    if $k == v: c.lineCap = k
proc lineCap*(c: Canvas2D): CanvasLineCap = c.st.cap
  ## How open line ends look.
proc `lineJoin=`*(c: Canvas2D; v: CanvasLineJoin) =
  ## How lines meet at corners.
  c.run Op(kind: okJoin, n: ord(v))
proc `lineJoin=`*(c: Canvas2D; v: string) =
  ## "miter", "round" or "bevel".
  for k in CanvasLineJoin:
    if $k == v: c.lineJoin = k
proc lineJoin*(c: Canvas2D): CanvasLineJoin = c.st.join
  ## How lines meet at corners.
proc `miterLimit=`*(c: Canvas2D; v: float) =
  ## How long a mitered corner may get (times half the line width) before
  ## it is beveled.
  if fin(v) and v > 0: c.run op(okMiter, v)
proc miterLimit*(c: Canvas2D): float = c.st.miterLimit
  ## The miter limit.
proc setLineDash*(c: Canvas2D; segments: openArray[float]) =
  ## Dashed lines: lengths of dash, gap, dash... (an odd list is repeated
  ## once); an empty list draws solid lines. Negative or not-a-number
  ## lengths make the call ignored.
  var s: seq[float]
  for v in segments:
    if not fin(v) or v < 0: return
    s.add v
  if s.len mod 2 == 1:
    let once = s                         # (adding a seq to itself would read freed memory)
    s.add once
  var total = 0.0
  for v in s: total += v
  if total <= 0: s.setLen(0)
  c.run Op(kind: okDash, fl: s)
proc setLineDash*(c: Canvas2D; segments: openArray[int]) =
  ## Dashes given in whole pixels: `ctx.setLineDash([5, 3])`.
  var f: seq[float]
  for v in segments: f.add float(v)
  c.setLineDash(f)
proc getLineDash*(c: Canvas2D): seq[float] = c.st.dash
  ## The dash pattern.
proc `lineDashOffset=`*(c: Canvas2D; v: float) =
  ## Where the dash pattern starts along the line.
  if fin(v): c.run op(okDashOffset, v)
proc lineDashOffset*(c: Canvas2D): float = c.st.dashOffset
  ## Where the dash pattern starts.
proc `globalAlpha=`*(c: Canvas2D; v: float) =
  ## How opaque everything drawn next is, 0..1.
  if fin(v) and v >= 0 and v <= 1: c.run op(okAlpha, v)
proc globalAlpha*(c: Canvas2D): float = c.st.alpha
  ## How opaque drawing is.
proc `globalCompositeOperation=`*(c: Canvas2D; v: CanvasCompositeOp) =
  ## How new drawing combines with what is there.
  c.run Op(kind: okComposite, n: ord(v))
proc `globalCompositeOperation=`*(c: Canvas2D; v: string) =
  ## "source-over", "destination-out", "multiply"... (see `CanvasCompositeOp`).
  for k in CanvasCompositeOp:
    if $k == v: c.globalCompositeOperation = k
proc globalCompositeOperation*(c: Canvas2D): CanvasCompositeOp = c.st.op
  ## How new drawing combines with what is there.
proc `font=`*(c: Canvas2D; v: string) =
  ## The text style as CSS: "16px sans-serif", "bold 20px sans",
  ## "italic 12pt monospace", "24px serif". Size in px, pt, em or rem;
  ## bold, italic (the fonts' own italics); a family with "mono" in it (or
  ## courier) is FreeMono, "serif" (or Times, Georgia) FreeSerif, FreeSans
  ## (or Helvetica, Arial) FreeSans, and "sans-serif", "system-ui" and the
  ## rest whichever font the UI uses (`uiFont`).
  c.run Op(kind: okFont, s: v)
proc font*(c: Canvas2D): string = c.st.font
  ## The text style.
proc `textAlign=`*(c: Canvas2D; v: CanvasTextAlign) =
  ## Where `fillText`'s x is on the text.
  c.run Op(kind: okAlign, n: ord(v))
proc `textAlign=`*(c: Canvas2D; v: string) =
  ## "start", "end", "left", "right" or "center".
  for k in CanvasTextAlign:
    if $k == v: c.textAlign = k
proc textAlign*(c: Canvas2D): CanvasTextAlign = c.st.align
  ## Where `fillText`'s x is on the text.
proc `textBaseline=`*(c: Canvas2D; v: CanvasTextBaseline) =
  ## Where `fillText`'s y is on the text.
  c.run Op(kind: okBaseline, n: ord(v))
proc `textBaseline=`*(c: Canvas2D; v: string) =
  ## "alphabetic", "top", "hanging", "middle", "ideographic" or "bottom".
  for k in CanvasTextBaseline:
    if $k == v: c.textBaseline = k
proc textBaseline*(c: Canvas2D): CanvasTextBaseline = c.st.baseline
  ## Where `fillText`'s y is on the text.
proc `direction=`*(c: Canvas2D; v: CanvasDirection) =
  ## Which way the text reads: "rtl" a right-to-left paragraph (its
  ## `start` at its right end), "ltr", "inherit" from each text's first
  ## letter (the default).
  c.run Op(kind: okDirection, n: ord(v))
proc `direction=`*(c: Canvas2D; v: string) =
  ## "ltr", "rtl" or "inherit".
  for k in CanvasDirection:
    if $k == v: c.direction = k
proc direction*(c: Canvas2D): CanvasDirection = c.st.dir
  ## Which way the text reads.
proc `shadowColor=`*(c: Canvas2D; v: string) =
  ## The shadow's color (transparent: no shadow, the default).
  var col: uint32
  if parseColor(v, col): c.run Op(kind: okShadowColor, u: col)
proc shadowColor*(c: Canvas2D): string = colorText(c.st.shadowColor)
  ## The shadow's color.
proc `shadowBlur=`*(c: Canvas2D; v: float) =
  ## How soft the shadow is (in pixels, not changed by the transform).
  if fin(v) and v >= 0: c.run op(okShadowBlur, min(v, 400))
proc shadowBlur*(c: Canvas2D): float = c.st.shadowBlur
  ## How soft the shadow is.
proc `shadowOffsetX=`*(c: Canvas2D; v: float) =
  ## How far right the shadow falls.
  if fin(v): c.run op(okShadowX, clamp(v, -4000, 4000))
proc shadowOffsetX*(c: Canvas2D): float = c.st.shadowX
  ## How far right the shadow falls.
proc `shadowOffsetY=`*(c: Canvas2D; v: float) =
  ## How far down the shadow falls.
  if fin(v): c.run op(okShadowY, clamp(v, -4000, 4000))
proc shadowOffsetY*(c: Canvas2D): float = c.st.shadowY
  ## How far down the shadow falls.
proc `imageSmoothingEnabled=`*(c: Canvas2D; v: bool) =
  ## Smooth (true, the default) or blocky (false, pixel art) scaled pictures.
  c.run Op(kind: okSmoothing, n: ord(v))
proc imageSmoothingEnabled*(c: Canvas2D): bool = c.st.smoothing
  ## Whether scaled pictures are smoothed.

proc beginPath*(c: Canvas2D) =
  ## Starts a new path (the old one is forgotten).
  c.run Op(kind: okBeginPath)

proc pathOp(c: Canvas2D; k: PathOpKind; vals: varargs[float]) =
  var po = PathOp(kind: k)
  for i, v in vals:
    if i < 8: po.f[i] = v
  c.run Op(kind: okPath, po: po)

proc moveTo*(c: Canvas2D; x, y: float) =
  ## Starts a new subpath at `x`, `y`.
  if finite(x, y): c.pathOp(poMove, x, y)
proc lineTo*(c: Canvas2D; x, y: float) =
  ## A straight line to `x`, `y`.
  if finite(x, y): c.pathOp(poLine, x, y)
proc quadraticCurveTo*(c: Canvas2D; cpx, cpy, x, y: float) =
  ## A curve to `x`, `y`, pulled toward the control point `cpx`, `cpy`.
  if finite(cpx, cpy, x, y): c.pathOp(poQuad, cpx, cpy, x, y)
proc bezierCurveTo*(c: Canvas2D; cp1x, cp1y, cp2x, cp2y, x, y: float) =
  ## A curve to `x`, `y`, pulled toward two control points.
  if finite(cp1x, cp1y, cp2x, cp2y, x, y): c.pathOp(poCubic, cp1x, cp1y, cp2x, cp2y, x, y)
proc arc*(c: Canvas2D; x, y, radius, startAngle, endAngle: float; anticlockwise = false) =
  ## An arc of the circle at `x`, `y` (radians: 0 points right, angles grow
  ## clockwise on screen; `arc(x, y, r, 0, 2 * PI)` is a whole circle).
  if finite(x, y, radius, startAngle, endAngle) and radius >= 0:
    c.pathOp(poArc, x, y, radius, startAngle, endAngle, float(ord(anticlockwise)))
proc arcTo*(c: Canvas2D; x1, y1, x2, y2, radius: float) =
  ## A rounded corner: a line toward `x1`, `y1` that turns, along a circle
  ## of `radius`, toward `x2`, `y2`.
  if finite(x1, y1, x2, y2, radius) and radius >= 0:
    c.pathOp(poArcTo, x1, y1, x2, y2, radius)
proc ellipse*(c: Canvas2D; x, y, radiusX, radiusY, rotation, startAngle, endAngle: float;
              anticlockwise = false) =
  ## An arc of the ellipse at `x`, `y`, turned by `rotation` radians.
  if finite(x, y, radiusX, radiusY, rotation, startAngle, endAngle) and
     radiusX >= 0 and radiusY >= 0:
    c.pathOp(poEllipse, x, y, radiusX, radiusY, rotation, startAngle, endAngle,
             float(ord(anticlockwise)))
proc rect*(c: Canvas2D; x, y, w, h: float) =
  ## A closed rectangle in the path.
  if finite(x, y, w, h): c.pathOp(poRect, x, y, w, h)
proc roundRect*(c: Canvas2D; x, y, w, h: float; radii: openArray[float] = [0.0]) =
  ## A closed rectangle with rounded corners: one radius, or 2, 3 or 4
  ## (top-left, top-right, bottom-right, bottom-left), as in CSS.
  if finite(x, y, w, h):
    c.run Op(kind: okPath, po: PathOp(kind: poRoundRect, f: [x, y, w, h, 0, 0, 0, 0],
                                      radii: @radii))
proc roundRect*(c: Canvas2D; x, y, w, h, radius: float) =
  ## A closed rectangle with all corners rounded by `radius`.
  c.roundRect(x, y, w, h, [radius])
proc closePath*(c: Canvas2D) =
  ## A line back to where the subpath started.
  c.pathOp(poClose)

proc fill*(c: Canvas2D; rule = frNonZero) =
  ## Fills the path with `fillStyle` (`frEvenOdd`: overlaps become holes).
  c.run Op(kind: okFill, n: ord(rule))
proc fill*(c: Canvas2D; path: Path2D; rule = frNonZero) =
  ## Fills a kept path.
  if path != nil: c.run Op(kind: okFill, n: ord(rule), path: path)
proc stroke*(c: Canvas2D) =
  ## Draws the path's lines with `strokeStyle`, `lineWidth` and the line
  ## style.
  c.run Op(kind: okStroke)
proc stroke*(c: Canvas2D; path: Path2D) =
  ## Draws a kept path's lines.
  if path != nil: c.run Op(kind: okStroke, path: path)
proc clip*(c: Canvas2D; rule = frNonZero) =
  ## From now on (until `restore`), draws only inside the path.
  c.run Op(kind: okClip, n: ord(rule))
proc clip*(c: Canvas2D; path: Path2D; rule = frNonZero) =
  ## Draws only inside a kept path.
  if path != nil: c.run Op(kind: okClip, n: ord(rule), path: path)
proc fillRect*(c: Canvas2D; x, y, w, h: float) =
  ## A filled rectangle (the path is left as it is).
  if finite(x, y, w, h): c.run op(okFillRect, x, y, w, h)
proc strokeRect*(c: Canvas2D; x, y, w, h: float) =
  ## A rectangle's lines (the path is left as it is).
  if finite(x, y, w, h): c.run op(okStrokeRect, x, y, w, h)
proc clearRect*(c: Canvas2D; x, y, w, h: float) =
  ## Makes a rectangle transparent again.
  if finite(x, y, w, h): c.run op(okClearRect, x, y, w, h)

proc fillText*(c: Canvas2D; text: string; x, y: float; maxWidth = 0.0) =
  ## Draws `text` with `font`, `fillStyle`, `textAlign` and `textBaseline`
  ## (Arabic joined and right to left, as everywhere in the kit);
  ## `maxWidth` > 0 squeezes it to fit.
  if finite(x, y, maxWidth) and text.len > 0:
    var o = op(okFillText, x, y, maxWidth)
    o.s = text
    c.run o
proc strokeText*(c: Canvas2D; text: string; x, y: float; maxWidth = 0.0) =
  ## Draws the outline of `text` with `strokeStyle` and `lineWidth`.
  if finite(x, y, maxWidth) and text.len > 0:
    var o = op(okStrokeText, x, y, maxWidth)
    o.s = text
    c.run o

proc measureText*(c: Canvas2D; text: string): TextMetrics =
  ## How wide `text` is in the current font, and how far it reaches above
  ## and below the baseline.
  let st = c.st
  let fid = faceFor(st)
  let px = st.fontSize
  let f = face(fid)
  let upem = float(f.unitsPerEm)
  result.fontBoundingBoxAscent = float(f.ascent) / upem * px
  result.fontBoundingBoxDescent = -float(f.descent) / upem * px
  if text.len == 0: return
  let run = shape(text, fid, dirOf(st))
  result.width = float(run.width) * px
  var x0, y0 = Inf
  var x1, y1 = NegInf
  for g in run.glyphs:
    let ff = face(g.face)
    let b = ff.bounds(int(g.gid))
    if b.x1 <= b.x0: continue
    let u = float(ff.unitsPerEm)
    x0 = min(x0, float(g.x) * px + float(b.x0) / u * px)
    x1 = max(x1, float(g.x) * px + float(b.x1) / u * px)
    y0 = min(y0, (float(g.y) + float(b.y0) / u) * px)
    y1 = max(y1, (float(g.y) + float(b.y1) / u) * px)
  if x0 <= x1:
    result.actualBoundingBoxLeft = -x0
    result.actualBoundingBoxRight = x1
    result.actualBoundingBoxAscent = y1
    result.actualBoundingBoxDescent = -y0

proc drawImage*(c: Canvas2D; img: Bitmap; dx, dy: float) =
  ## Draws a picture with its top-left at `dx`, `dy`, one logical pixel per
  ## picture pixel.
  if img != nil and finite(dx, dy):
    var o = op(okDrawImage, 0.0, 0.0, float(img.w), float(img.h), dx, dy, float(img.w), float(img.h))
    o.img = img
    c.run o
proc drawImage*(c: Canvas2D; img: Bitmap; dx, dy, dw, dh: float) =
  ## Draws a picture scaled into the rectangle `dx`, `dy`, `dw`, `dh`.
  if img != nil and finite(dx, dy, dw, dh):
    var o = op(okDrawImage, 0.0, 0.0, float(img.w), float(img.h), dx, dy, dw, dh)
    o.img = img
    c.run o
proc drawImage*(c: Canvas2D; img: Bitmap; sx, sy, sw, sh, dx, dy, dw, dh: float) =
  ## Draws the part `sx`, `sy`, `sw`, `sh` of a picture (in its pixels)
  ## into the rectangle `dx`, `dy`, `dw`, `dh`.
  if img != nil and finite(sx, sy, sw, sh, dx, dy, dw, dh):
    var o = op(okDrawImage, sx, sy, sw, sh, dx, dy, dw, dh)
    o.img = img
    c.run o

proc createImageData*(c: Canvas2D; w, h: int): ImageData =
  ## Transparent pixels, `w` x `h` (capped like a canvas).
  let (ww, hh) = fitSize(w, h, 1)
  ImageData(width: ww, height: hh, data: newSeq[uint8](ww * hh * 4))

proc getImageData*(c: Canvas2D; sx, sy, sw, sh: int): ImageData =
  ## A copy of the canvas's pixels in the rectangle (in the canvas's own
  ## pixels: `pixelWidth` x `pixelHeight`); outside the canvas they are
  ## transparent.
  if c.deferred: c.startPainting()
  result = c.createImageData(sw, sh)
  for y in 0 ..< result.height:
    let ty = sy + y
    if ty < 0 or ty >= c.h: continue
    for x in 0 ..< result.width:
      let tx = sx + x
      if tx < 0 or tx >= c.w: continue
      let p = unpremul(c.pm[ty * c.w + tx])
      let o = (y * result.width + x) * 4
      result.data[o] = uint8((p shr 16) and 255)
      result.data[o + 1] = uint8((p shr 8) and 255)
      result.data[o + 2] = uint8(p and 255)
      result.data[o + 3] = uint8(p shr 24)

proc putImageData*(c: Canvas2D; data: ImageData; dx, dy: int) =
  ## Puts pixels on the canvas at `dx`, `dy` as they are (no transform,
  ## alpha, compositing or clip, as in the browser).
  if data == nil: return
  let d = ImageData(width: data.width, height: data.height, data: data.data)
  var o = op(okPutImageData, float(dx), float(dy), 0.0, 0.0, float(data.width), float(data.height))
  o.data = d
  c.run o
proc putImageData*(c: Canvas2D; data: ImageData; dx, dy, dirtyX, dirtyY,
                   dirtyW, dirtyH: int) =
  ## Puts only the part `dirtyX`, `dirtyY`, `dirtyW`, `dirtyH` of the pixels.
  if data == nil: return
  let d = ImageData(width: data.width, height: data.height, data: data.data)
  var o = op(okPutImageData, float(dx), float(dy), float(dirtyX), float(dirtyY),
             float(dirtyW), float(dirtyH))
  o.data = d
  c.run o

proc isPointInPath*(c: Canvas2D; x, y: float; rule = frNonZero): bool =
  ## Whether the point `x`, `y` (the canvas's logical pixels, like
  ## `input.x`) is inside the current path.
  if not finite(x, y): return false
  let w = windingAt(polys(c.path), x * c.ratio, y * c.ratio)
  if rule == frEvenOdd: (w and 1) != 0 else: w != 0
proc isPointInPath*(c: Canvas2D; path: Path2D; x, y: float; rule = frNonZero): bool =
  ## Whether the point is inside a kept path (drawn with the current
  ## transform).
  if path == nil or not finite(x, y): return false
  var p: PathB
  for po in path.ops: p.applyOp(c.st.ctm, po)
  let w = windingAt(polys(p), x * c.ratio, y * c.ratio)
  if rule == frEvenOdd: (w and 1) != 0 else: w != 0
proc isPointInStroke*(c: Canvas2D; x, y: float): bool =
  ## Whether the point is on the line the current path would draw.
  if not finite(x, y): return false
  windingAt(c.strokeOutline(c.path), x * c.ratio, y * c.ratio) != 0
proc isPointInStroke*(c: Canvas2D; path: Path2D; x, y: float): bool =
  ## Whether the point is on a kept path's line.
  if path == nil or not finite(x, y): return false
  var p: PathB
  for po in path.ops: p.applyOp(c.st.ctm, po)
  windingAt(c.strokeOutline(p), x * c.ratio, y * c.ratio) != 0

proc reset*(c: Canvas2D) =
  ## Clears the pixels, the path and the state (as a new canvas).
  if c.deferred: c.startPainting()
  for p in c.pm.mitems: p = 0
  c.st = defaultState(c.ratio)
  c.stack.setLen(0)
  c.path = PathB()
  c.dirty = true

proc toBitmap*(c: Canvas2D): Bitmap =
  ## The picture as a kit `Bitmap` (straight alpha, the canvas's pixels).
  if c.deferred: c.startPainting()
  result = newBitmap(c.w, c.h)
  for i in 0 ..< c.pm.len: result.px[i] = unpremul(c.pm[i])

proc savePng*(c: Canvas2D; path: string): bool {.discardable.} =
  ## Saves the picture as a PNG file; false when it cannot be written.
  savePng(c.toBitmap, path)

proc encodePng*(c: Canvas2D): string =
  ## The picture as the bytes of a PNG file.
  encodePng(c.toBitmap)

# ---- in a window ---------------------------------------------------------------------------------

var canvases: Table[Id, Canvas2D]

proc beginCanvas2D*(w, h: int; key = ""; retained = false; focusable = false;
                    captureDrag = true; captureWheel = false): Canvas2D =
  ## A canvas `w` x `h` logical pixels in the layout (`w` <= 0: as wide as
  ## the room); draw on what it returns, then call `endCanvas2D` (the
  ## `canvas2d` template does both). Each frame starts with a fresh state;
  ## the pixels are made again only when the drawing changed. `retained`:
  ## the picture stays from frame to frame and only what you draw is added
  ## (`reset` clears it). `focusable`: it takes the keyboard (Tab, a click)
  ## and reports keys in `input`. `captureDrag`: a finger dragging on it
  ## draws (reported in `input`) instead of scrolling the page.
  ## `captureWheel`: the wheel over it is the canvas's, not the page's.
  let r = place(if w > 0: w else: 0, max(1, h), fill = w <= 0)
  let id = idOf("canvas2d:" & key)
  var c = canvases.getOrDefault(id, nil)
  let ratio = float(max(1, pxScale))
  let (bw, bh) = fitSize(r.w, r.h, ratio)
  if c == nil or c.w != bw or c.h != bh or c.ratio != ratio:
    let fresh = newCanvas2D(r.w, r.h, ratio)
    if c != nil:
      fresh.input = c.input
      fresh.rasterized = c.rasterized
    c = fresh
    canvases[id] = c
    c.lastHash = Hash(0)
  c.id = id
  c.retained = retained
  c.deferred = not retained
  c.painting = retained
  if not retained:
    c.ops.setLen(0)
    c.hash = Hash(0x51F15E)
    c.st = defaultState(ratio)
    c.stack.setLen(0)
    c.path = PathB()
  # the pointer, fingers and keys
  let hit = interact(id, r, focusable = focusable)
  var inp = CanvasInput()
  inp.x = float(ui.mx - r.x)
  inp.y = float(ui.my - r.y)
  inp.finger = finger()
  let mine = ui.active == id
  inp.over = mouseIn(r) and canInput() and (canHover() or mine)
  inp.pressed = hit.down and ui.pressed
  if inp.pressed:
    c.pressX = inp.x
    c.pressY = inp.y
    c.lastX = inp.x
    c.lastY = inp.y
    c.moved = false
    if captureDrag: ui.dragsActive = true
    if ui.clicks >= 2: inp.doubleClicked = true
  inp.down = mine and ui.mouseDown
  if inp.down and not inp.pressed:
    inp.dx = inp.x - c.lastX
    inp.dy = inp.y - c.lastY
    if abs(inp.x - c.pressX) + abs(inp.y - c.pressY) > 3: c.moved = true
  inp.dragging = inp.down and c.moved
  if inp.down:
    c.lastX = inp.x
    c.lastY = inp.y
  inp.released = hit.clicked or (c.input.down and not inp.down)
  inp.clicked = hit.clicked
  if ui.rpressed and mouseIn(r) and canInput(): inp.rightClicked = true
  if canInput() and mouseIn(r) and ui.wheel != 0 and not ui.wheelUsed:
    inp.wheel = ui.wheel
    if captureWheel: ui.wheelUsed = true
  inp.focused = hit.focused
  if hit.focused and canInput():
    inp.key = ui.key
    inp.mods = ui.mods
    inp.typed = ui.typed
  c.input = inp
  c.screen = r
  c

proc endCanvas2D*(c: Canvas2D) =
  ## Shows the canvas: made again from this frame's drawing only when it
  ## changed (or when it is `retained` and was drawn on).
  if c == nil: return
  if c.deferred:
    if not c.painting and (c.hash != c.lastHash or c.bmp == nil):
      c.startPainting()
    c.lastHash = c.hash
    c.painting = false
  if c.dirty or c.bmp == nil or c.bmp.w != c.w or c.bmp.h != c.h:
    if c.bmp == nil or c.bmp.w != c.w or c.bmp.h != c.h: c.bmp = newBitmap(c.w, c.h)
    for i in 0 ..< c.pm.len: c.bmp.px[i] = unpremul(c.pm[i])
    changed(c.bmp)
    c.dirty = false
  drawBitmap(c.screen, c.bmp)
  if c.input.focused: focusDots(inset(c.screen, 1))
  ui.lastId = c.id
  ui.lastRect = c.screen

type CanvasOptions* = object
  ## How a `canvas2dWith` canvas behaves (see `beginCanvas2D`).
  key*: string             ## tells canvases at the same place apart
  retained*: bool          ## the picture stays; draw only what changes
  focusable*: bool         ## takes the keyboard
  captureDrag* = true      ## a finger draws on it rather than scrolling
  captureWheel*: bool      ## the wheel is the canvas's

template canvas2d*(ctx: untyped; w, h: int; body: untyped) =
  ## A canvas `w` x `h` (logical pixels; `w` <= 0: the room's width) in the
  ## layout, its context named `ctx` in `body`:
  ##
  ## .. code-block:: nim
  ##   canvas2d(ctx, 300, 200):
  ##     ctx.fillStyle = "navy"
  ##     ctx.fillRect(10, 10, 100, 50)
  ##     if ctx.input.clicked: echo "clicked at ", ctx.input.x, ", ", ctx.input.y
  block:
    let ctx {.inject.} = beginCanvas2D(w, h)
    body
    endCanvas2D(ctx)

template canvas2dWith*(ctx: untyped; w, h: int; options: CanvasOptions; body: untyped) =
  ## `canvas2d` with options: `canvas2dWith(ctx, 400, 300,
  ## CanvasOptions(retained: true, key: "pad")): ...`.
  block:
    let o = options
    let ctx {.inject.} = beginCanvas2D(w, h, o.key, o.retained, o.focusable,
                                       o.captureDrag, o.captureWheel)
    body
    endCanvas2D(ctx)
