## Adjustment Presets, as Photoshop's Adjustments panel has them: a look
## made of adjustment layers (Curves, Hue/Saturation, a Photo Filter...),
## put on an image as a group of those layers -- each of them changed or
## taken off later. 36 come with it, in six kinds; presets of your own are
## made from adjustment layers (`presetFromLayers`), kept in a file
## (`savePresetFile`, `loadPresetFile`: JSON, ".radj"), and put on many
## files at once (`applyPresetToFile`).
##
## ```nim
## let ps = builtinPresets()
## d.beginStep("Adjustment Preset")
## discard d.applyPreset(ps[0])
## d.endStep()
## ```

import std/[json, os, strutils]
import photo, photofx, photodevelop, gfx, imaging, jpeg

type
  PresetStep* = object
    ## One adjustment layer of a preset.
    adjust*: Adjustment  ## what the layer does
    name*: string        ## the layer's name ("": the adjustment's)
    opacity*: int        ## 0..100
    mode*: BlendMode     ## the layer's blend mode

  AdjPreset* = object
    ## A look: its adjustment layers, the bottom one first.
    name*, category*: string  ## its name, and its kind (one of `PresetCategories`)
    steps*: seq[PresetStep]   ## its adjustment layers, the bottom one first

const PresetCategories* = ["Portraits", "Landscapes", "Photography", "Creative", "Black & White", "Cinematic"]
  ## The kinds the built-in presets come in (yours: "My Presets").

# ---- making the settings --------------------------------------------------------------------------------------

proc step(a: Adjustment; opacity = 100; mode = bmNormal; name = ""): PresetStep =
  PresetStep(adjust: a, opacity: opacity, mode: mode, name: name)

proc pts(ps: openArray[(int, int)]): seq[float] =
  result.add ps.len.float
  for (x, y) in ps:
    result.add x.float
    result.add y.float

proc adjCurves*(master: openArray[(int, int)]; red: openArray[(int, int)] = []; green: openArray[(int, int)] = [];
             blue: openArray[(int, int)] = []): Adjustment =
  ## A Curves adjustment from its points (0..255), the master's and each
  ## channel's (none: straight).
  var args: seq[float]
  for c in [@master, @red, @green, @blue]:
    args.add pts(if c.len >= 2: c else: @[(0, 0), (255, 255)])
  Adjustment(kind: "Curves", args: args)

proc adjLevels*(inLo, inHi: int; gamma: float; outLo = 0; outHi = 255): Adjustment =
  ## A Levels adjustment of all the channels together.
  var args = @[inLo.float, inHi.float, gamma, outLo.float, outHi.float]
  for c in 1 .. 3: args.add [0.0, 255, 1, 0, 255]
  Adjustment(kind: "Levels", args: args)

proc adjHueSat*(master: (int, int, int); reds = (0, 0, 0); yellows = (0, 0, 0); greens = (0, 0, 0);
             cyans = (0, 0, 0); blues = (0, 0, 0); magentas = (0, 0, 0)): Adjustment =
  ## A Hue/Saturation adjustment: hue, saturation, lightness for all, then
  ## for each range of colors.
  var args = @[0.0]
  for r in [master, reds, yellows, greens, cyans, blues, magentas]:
    args.add [r[0].float, r[1].float, r[2].float]
  Adjustment(kind: "Hue/Saturation", args: args)

proc adjColorize*(hue, sat, light: int): Adjustment =
  ## Hue/Saturation with Colorize: all one hue.
  Adjustment(kind: "Hue/Saturation", args: @[1.0, hue.float, sat.float, light.float])

proc adjBalance*(shadows, mids, highs: (int, int, int); keepLight = true): Adjustment =
  ## A Color Balance: cyan-red, magenta-green, yellow-blue for each range.
  Adjustment(kind: "Color Balance", args: @[shadows[0].float, shadows[1].float, shadows[2].float,
                                            mids[0].float, mids[1].float, mids[2].float,
                                            highs[0].float, highs[1].float, highs[2].float,
                                            (if keepLight: 1.0 else: 0.0)])

proc adjVibrance*(vib, sat: int): Adjustment = Adjustment(kind: "Vibrance", args: @[vib.float, sat.float])
  ## A Vibrance adjustment.
proc adjExposure*(stops: float; offset = 0.0; gamma = 1.0): Adjustment =
  ## An Exposure adjustment.
  Adjustment(kind: "Exposure", args: @[stops, offset, gamma])
proc adjPhotoFilter*(c: uint32; density: int; keepLight = true): Adjustment =
  ## A Photo Filter of the color `c`, `density` percent.
  Adjustment(kind: "Photo Filter", args: @[rOf(c).float, gOf(c).float, bOf(c).float, density.float,
                                           (if keepLight: 1.0 else: 0.0)])
proc adjBrightness*(b, c: int): Adjustment = Adjustment(kind: "Brightness/Contrast", args: @[b.float, c.float])
  ## A Brightness/Contrast adjustment.
proc adjBlackWhite*(w: array[6, int] = defaultBlackAndWhite(); tint = false; hue = 0; sat = 0): Adjustment =
  ## Black & White: the weights of reds, yellows, greens, cyans, blues,
  ## magentas; a tint.
  var args: seq[float]
  for v in w: args.add v.float
  args.add [(if tint: 1.0 else: 0.0), hue.float, sat.float]
  Adjustment(kind: "Black & White", args: args)
proc adjMixer*(r, g, b: array[4, int]; mono = false): Adjustment =
  ## A Channel Mixer: each output from red, green, blue and a constant.
  var args: seq[float]
  for o in [r, g, b]:
    for v in o: args.add v.float
  args.add(if mono: 1.0 else: 0.0)
  Adjustment(kind: "Channel Mixer", args: args)
proc adjGradMap*(colors: openArray[uint32]): Adjustment =
  ## A Gradient Map through `colors`, evenly spaced (dark to light).
  var stops: seq[GradientStop]
  for i, c in colors:
    stops.add GradientStop(at: (if colors.len > 1: i / (colors.len - 1) else: 0.0), color: c or 0xFF000000'u32,
                           mid: 0.5)
  Adjustment(kind: "Gradient Map", args: gradientMapArgs(stops))
proc adjPosterize*(n: int): Adjustment = Adjustment(kind: "Posterize", args: @[n.float])
  ## A Posterize adjustment.

proc preset(name, cat: string; steps: varargs[PresetStep]): AdjPreset =
  AdjPreset(name: name, category: cat, steps: @steps)

proc builtinPresets*(): seq[AdjPreset] =
  ## The presets that come with it: six of each kind.
  const matte = [(0, 30), (64, 72), (192, 190), (255, 238)]
  const sCurve = [(0, 0), (64, 52), (192, 206), (255, 255)]
  const strongS = [(0, 0), (60, 40), (196, 220), (255, 255)]
  @[
    # Portraits
    preset("Warm Skin", "Portraits", step(adjBalance((4, 0, -6), (10, 0, -8), (4, 0, -4))), step(adjVibrance(10, 0))),
    preset("Soft Glow", "Portraits", step(adjCurves([(0, 12), (128, 140), (255, 255)])), step(adjBrightness(6, -12))),
    preset("Porcelain", "Portraits", step(adjVibrance(-25, 0)), step(adjCurves([(0, 8), (128, 146), (255, 255)]))),
    preset("Golden Portrait", "Portraits", step(adjPhotoFilter(0xFFEC8A00'u32, 25)), step(adjCurves(sCurve))),
    preset("Cool Portrait", "Portraits", step(adjPhotoFilter(0xFF0B6BD4'u32, 18)), step(adjVibrance(8, -6))),
    preset("Matte Portrait", "Portraits", step(adjCurves(matte)), step(adjVibrance(-10, 0))),
    # Landscapes
    preset("Vivid Landscape", "Landscapes", step(adjVibrance(40, 10)), step(adjCurves(sCurve))),
    preset("Blue Sky", "Landscapes", step(adjHueSat((0, 0, 0), cyans = (0, 20, -6), blues = (0, 32, -10)))),
    preset("Lush Greens", "Landscapes", step(adjHueSat((0, 0, 0), yellows = (8, 18, 0), greens = (0, 28, -4)))),
    preset("Autumn", "Landscapes", step(adjHueSat((0, 0, 0), yellows = (-12, 30, 0), greens = (-30, 10, 0))),
           step(adjBalance((0, 0, 0), (14, 0, -10), (0, 0, 0)))),
    preset("Misty Morning", "Landscapes", step(adjCurves([(0, 40), (128, 140), (255, 240)])),
           step(adjPhotoFilter(0xFF5A9BD5'u32, 15))),
    preset("Sunset Glow", "Landscapes", step(adjPhotoFilter(0xFFF07A20'u32, 35)), step(adjVibrance(20, 0))),
    # Photography
    preset("Punch", "Photography", step(adjCurves(strongS)), step(adjVibrance(15, 0))),
    preset("Bright & Airy", "Photography", step(adjExposure(0.4, 0.0, 1.05)), step(adjCurves([(0, 18), (255, 255)])),
           step(adjVibrance(-8, 0))),
    preset("Moody", "Photography", step(adjExposure(-0.3)), step(adjCurves([(0, 0), (70, 50), (255, 235)])),
           step(adjVibrance(-15, 0))),
    preset("Faded Film", "Photography", step(adjCurves(matte)), step(adjHueSat((0, -20, 0)))),
    preset("High Key", "Photography", step(adjLevels(0, 230, 1.4))),
    preset("Low Key", "Photography", step(adjLevels(25, 255, 0.75)), step(adjVibrance(-10, 0))),
    # Creative
    preset("Cross Process", "Creative", step(adjCurves([(0, 0), (255, 255)], red = [(0, 0), (64, 48), (192, 220), (255, 255)],
                                                   green = [(0, 0), (64, 56), (192, 210), (255, 255)],
                                                   blue = [(0, 40), (255, 210)]))),
    preset("Teal & Orange", "Creative", step(adjBalance((-18, 0, 16), (6, 0, -4), (14, 0, -18)))),
    preset("Duotone Blue", "Creative", step(adjGradMap([0xFF0E1A40'u32, 0xFF5A7FB0'u32, 0xFFF4EAD2'u32]))),
    preset("Neon Pop", "Creative", step(adjVibrance(60, 25)), step(adjCurves(strongS))),
    preset("Infrared", "Creative", step(adjMixer([-60, 160, 0, 0], [0, 100, 0, 0], [0, 0, 100, 0]))),
    preset("Poster", "Creative", step(adjPosterize(6)), step(adjVibrance(30, 0))),
    # Black & White
    preset("Classic B&W", "Black & White", step(adjBlackWhite())),
    preset("High Contrast B&W", "Black & White", step(adjBlackWhite()), step(adjCurves(strongS))),
    preset("Red Filter B&W", "Black & White", step(adjBlackWhite([120, 110, 40, 60, 10, 80]))),
    preset("Selenium", "Black & White", step(adjBlackWhite(tint = true, hue = 225, sat = 8))),
    preset("Sepia", "Black & White", step(adjBlackWhite(tint = true, hue = 35, sat = 28))),
    preset("Soft Matte B&W", "Black & White", step(adjBlackWhite()), step(adjCurves(matte))),
    # Cinematic
    preset("Teal Shadows", "Cinematic", step(adjBalance((-15, 0, 12), (0, 0, 0), (0, 0, 0)))),
    preset("Blockbuster", "Cinematic", step(adjBalance((-20, 0, 18), (4, 0, -6), (16, 0, -20))),
           step(adjCurves(sCurve))),
    preset("Bleach Bypass", "Cinematic", step(adjHueSat((0, -45, 0))), step(adjCurves(strongS))),
    preset("Vintage Film", "Cinematic", step(adjPhotoFilter(0xFFEC8A00'u32, 20)), step(adjCurves(matte)),
           step(adjHueSat((0, -15, 0)))),
    preset("Noir", "Cinematic", step(adjBlackWhite([60, 50, 40, 60, 30, 70])), step(adjCurves([(0, 0), (80, 50), (255, 245)])),
           step(adjExposure(-0.2))),
    preset("Day for Night", "Cinematic", step(adjPhotoFilter(0xFF102C8C'u32, 60, false)), step(adjExposure(-1.0)),
           step(adjHueSat((0, -40, 0))))]

# ---- on an image -----------------------------------------------------------------------------------------------

proc applyPreset*(d: Doc; p: AdjPreset): Layer =
  ## The preset's adjustment layers over the current layer, in a group
  ## named after it (returned; nil when it has none). Undoable in a step
  ## (`beginStep` before).
  var idxs: seq[int]
  for s in p.steps:
    let L = d.newAdjustmentLayer(s.adjust, if s.name.len > 0: s.name else: s.adjust.kind)
    L.opacity = clamp(s.opacity, 0, 100)
    L.mode = s.mode
    idxs.add d.layers.find(L)
  if idxs.len == 0: return nil
  result = d.groupLayers(idxs, p.name)
  if result != nil: result.collapsed = true
  d.markAll()

proc presetLook*(px: seq[uint32]; w, h: int; p: AdjPreset): seq[uint32] =
  ## `px` (`w` x `h`) as the preset makes it look (its previews in the
  ## panel; the files of a batch).
  var im = Img(w: w, h: h, px: px)
  for s in p.steps:
    let f = adjustmentFn(s.adjust)
    if f == nil: continue
    let o = f(im, rect(0, 0, w, h))
    if o.px.len != im.px.len: continue
    let a = clamp(s.opacity, 0, 100) * 255 div 100
    if a >= 255 and s.mode == bmNormal:
      for i in 0 ..< im.px.len: im.px[i] = (im.px[i] and 0xFF000000'u32) or (o.px[i] and 0xFFFFFF'u32)
    else:
      for i in 0 ..< im.px.len:
        let under = im.px[i]
        let r = blendPx(under or 0xFF000000'u32, o.px[i] or 0xFF000000'u32, a, s.mode)
        im.px[i] = (under and 0xFF000000'u32) or (r and 0xFFFFFF'u32)
  im.px

proc presetFromLayers*(d: Doc; name, category: string; idxs: seq[int]): AdjPreset =
  ## A preset of your own from adjustment layers (the bottom one first;
  ## other layers among them left out).
  result = AdjPreset(name: name, category: category)
  for i in countup(0, d.layers.high):
    if i in idxs:
      let L = d.layers[i]
      if L.adjust.kind.len > 0:
        result.steps.add PresetStep(adjust: L.adjust, name: L.name, opacity: L.opacity, mode: L.mode)

# ---- in files -----------------------------------------------------------------------------------------------------

proc toJson*(p: AdjPreset): JsonNode =
  ## A preset as JSON.
  var ss = newJArray()
  for s in p.steps:
    var sj = %*{"kind": s.adjust.kind, "args": s.adjust.args, "name": s.name, "opacity": s.opacity,
                "mode": $s.mode}
    if s.adjust.data.len > 0: sj["data"] = %s.adjust.data
    ss.add sj
  %*{"name": p.name, "category": p.category, "steps": ss}

proc presetOf*(j: JsonNode): AdjPreset =
  ## A preset back from `toJson` (no steps: not one).
  result = AdjPreset(name: j{"name"}.getStr("Preset"), category: j{"category"}.getStr("My Presets"))
  for sj in j{"steps"}.getElems:
    var s = PresetStep(adjust: Adjustment(kind: sj{"kind"}.getStr, data: sj{"data"}.getStr),
                       name: sj{"name"}.getStr, opacity: clamp(sj{"opacity"}.getInt(100), 0, 100))
    for v in sj{"args"}.getElems: s.adjust.args.add v.getFloat
    for m in BlendMode:
      if $m == sj{"mode"}.getStr("Normal"): s.mode = m
    if s.adjust.kind.len > 0 and adjustmentFn(s.adjust) != nil: result.steps.add s

proc savePresetFile*(path: string; ps: openArray[AdjPreset]) =
  ## Presets written to a file (".radj": JSON).
  var arr = newJArray()
  for p in ps: arr.add p.toJson
  writeFile(path, pretty(%*{"format": "Retro Photo Adjustment Presets", "version": 1, "presets": arr}))

proc loadPresetFile*(path: string): seq[AdjPreset] =
  ## The presets in a file (`savePresetFile`); raises `IOError` when it is
  ## not one.
  let j = try: parseJson(readFile(path))
          except CatchableError: raise newException(IOError, "not a presets file")
  for pj in j{"presets"}.getElems:
    let p = presetOf(pj)
    if p.steps.len > 0: result.add p
  if result.len == 0: raise newException(IOError, "no presets in " & path.extractFilename)

proc applyPresetToFile*(path, outPath: string; p: AdjPreset; quality = 92) =
  ## Batch: a picture (PNG, JPEG, BMP, GIF, ...) with the preset on it,
  ## written to `outPath` (its extension says how: .jpg, .png, .bmp).
  ## Raises `IOError` when it cannot be read or written.
  let b = loadPicture(path, 30000, 30000)
  if b == nil or b.w <= 0: raise newException(IOError, "cannot read " & path.extractFilename)
  let o = Bitmap(w: b.w, h: b.h, px: presetLook(b.px, b.w, b.h, p))
  let ext = outPath.splitFile.ext.toLowerAscii
  let data = case ext
             of ".jpg", ".jpeg": encodeJpeg(o, quality)
             of ".bmp": encodeBmp(o.px, o.w, o.h)
             else: encodePng(o)
  if data.len == 0: raise newException(IOError, "cannot write " & outPath.extractFilename)
  writeFile(outPath, data)
