## New Document presets and templates; Quick Actions and the automations
## of photoquick.

import std/[math, strutils, sequtils, os, json]
import retro/[gfx, photo, photofx, phototemplates, photoquick, textengine, assetstore, photobrushes, adobefiles,
              imaging, photofiles]

block presets:
  for c in PresetCategory:
    let ps = docPresets(c)
    doAssert ps.len >= 8, $c
    for p in ps:
      doAssert p.w > 0 and p.h > 0 and p.dpi > 0, p.name
      doAssert p.sizeLabel.len > 0
  # A4 at 300 ppi, shown in millimeters
  let a4 = docPresets(pcPrint)[0]
  doAssert a4.w == 2480 and a4.h == 3508, $a4.w & "x" & $a4.h
  doAssert a4.sizeLabel == "210 x 297 mm @ 300 ppi", a4.sizeLabel
  doAssert docPresets(pcSocial)[0].sizeLabel == "1080 x 1080 px"
  doAssert docPresets(pcPhoto)[1].sizeLabel == "6 x 4 in @ 300 ppi"
  echo "presets: ok"

block templates:
  let all = docTemplates()
  doAssert all.len >= 12
  for c in [pcPhoto, pcPrint, pcSocial]: doAssert templatesOf(c).len >= 2, $c
  for t in all:
    # built small (as the dialog's pictures are) and at full size for two
    let d = buildTemplate(t, 0.1)
    doAssert d.w == int(round(t.w.float * 0.1)) and d.h == int(round(t.h.float * 0.1)), t.name
    doAssert d.layers.len >= 2, t.name
    doAssert not d.modified
    var texts, frames = 0
    for L in d.layers:
      if L.isText: inc texts
      if L.name.startsWith("Frame "): inc frames
    doAssert texts + frames > 0, t.name
    let th = templateThumb(t, 120)
    doAssert max(th.w, th.h) == 120, t.name & " " & $th.w & "x" & $th.h
    var opaque = 0
    for p in th.px:
      if (p shr 24) == 255: inc opaque
    doAssert opaque == th.px.len
  # the words translated as it is built
  let cert = templatesOf(pcPrint).filterIt(it.name == "Certificate")
  doAssert cert.len == 1
  let d = buildTemplate(cert[0], 0.25, say = proc (s: string): string =
    if s == "CERTIFICATE": "شهادة" else: s)
  var found = false
  for L in d.layers:
    if L.isText and L.text.plainText == "شهادة": found = true
  doAssert found
  # full size: the type stays type, the size is the template's
  let f = buildTemplate(templatesOf(pcSocial)[0])
  doAssert f.w == 1080 and f.h == 1080
  echo "templates: ok (", all.len, ")"

proc portrait(w, h: int): Doc =
  ## A plain background with a round subject in the middle.
  result = newDoc(w, h, 0xFFB4C8DC'u32)
  let L = result.layers[0]
  for y in 0 ..< h:
    for x in 0 ..< w:
      let dx = x.float - w / 2
      let dy = y.float - h / 2
      let v = 40 + (x * 7 + y * 3) mod 30
      if dx * dx + dy * dy < (min(w, h).float * 0.28) ^ 2:
        L.px[y * w + x] = argb(255, 200, v, 40)
      else:
        L.px[y * w + x] = argb(255, 150 + (x div 8) mod 2 * 40, 180, 210)
  inc L.ver
  result.markAll()

block quickActions:
  let d = portrait(320, 240)
  d.beginStep("Blur Background")
  let L = d.blurBackground(60)
  d.endStep()
  doAssert L != nil and L.mask != nil
  doAssert d.layers.len == 2 and L.name == "Blurred Background"
  # the mask hides the blur over the subject, shows it on the background
  doAssert (L.mask.px[120 * 320 + 160] and 255) < 60
  doAssert (L.mask.px[10 * 320 + 10] and 255) > 200
  d.undo()
  doAssert d.layers.len == 1
  d.beginStep("B&W")
  let B = d.bwBackground()
  d.endStep()
  doAssert B != nil
  let p = B.px[10 * 320 + 10]
  doAssert ((p shr 16) and 255) == (p and 255)        # gray
  echo "quick actions: ok"

block frequencySeparation:
  let d = portrait(200, 160)
  let orig = d.layers[0].px
  d.beginStep("FS")
  let g = d.frequencySeparation(d.layers[0], 4)
  d.endStep()
  doAssert g != nil and g.group
  d.updateComposite()
  let now = d.compCopy
  var mx = 0
  for i in 0 ..< orig.len:
    for s in [0, 8, 16]: mx = max(mx, abs(int((orig[i] shr s) and 255) - int((now[i] shr s) and 255)))
  doAssert mx <= 2, $mx
  echo "frequency separation: ok (max ", mx, ")"

block cropAndStraighten:
  var scan = newImg(900, 700)
  for p in scan.px.mitems: p = 0xFFF2F2F0'u32
  proc put(cx, cy, w, h, ang: float; c: uint32) =
    let a = ang * PI / 180
    for y in 0 ..< scan.h:
      for x in 0 ..< scan.w:
        let dx = x.float - cx
        let dy = y.float - cy
        let u = dx * cos(a) + dy * sin(a)
        let v = -dx * sin(a) + dy * cos(a)
        if abs(u) < w / 2 and abs(v) < h / 2: scan.px[y * scan.w + x] = c
  put(250, 220, 300, 200, 8, 0xFF3366AA'u32)
  put(640, 480, 260, 180, -5, 0xFFAA5533'u32)
  let found = findPhotos(scan)
  doAssert found.len == 2, $found.len
  doAssert abs(found[0].angle - 8) < 1 and abs(found[1].angle + 5) < 1, $found[0].angle & " " & $found[1].angle
  doAssert abs(found[0].w - 300) < 8 and abs(found[0].h - 200) < 8
  let c = cutPhoto(scan, found[0])
  var bg = 0
  for p in c.px:
    if p == 0xFFF2F2F0'u32: inc bg
  doAssert bg < c.px.len div 100, $bg
  echo "crop and straighten: ok"

block colorThemes:
  for r in ColorHarmony:
    let five = colorTheme(0xFF2A9D8F'u32, r)
    doAssert five[2] == 0xFF2A9D8F'u32
    for c in five: doAssert (c shr 24) == 255
  let comp = colorTheme(0xFFFF0000'u32, chComplementary)
  doAssert ((comp[3] shr 16) and 255) < 40 and (comp[3] and 255) > 200     # cyan-ish
  echo "color themes: ok"

block focusArea:
  # sharp detail on the left half, smooth on the right
  let d = newDoc(200, 120, 0xFF808080'u32)
  for y in 0 ..< 120:
    for x in 0 ..< 100:
      d.layers[0].px[y * 200 + x] = if (x + y) mod 2 == 0: 0xFF000000'u32 else: 0xFFFFFFFF'u32
  inc d.layers[0].ver
  let m = d.focusArea(d.layers[0], soften = false)
  var l, r = 0
  for y in 20 ..< 100:
    for x in 10 ..< 90: l += int(m[y * 200 + x])
    for x in 110 ..< 190: r += int(m[y * 200 + x])
  doAssert l > r * 4, $l & " " & $r
  echo "focus area: ok"

block library:
  # the Retro Photo Library the app carries: every item's files there and readable
  let base = currentSourcePath().parentDir.parentDir / "library"
  let items = parseLibrary(readFile(base / "catalog.json"), "")
  doAssert items.len >= 70, $items.len
  var kinds: seq[AssetKind]
  for it in items:
    if it.kind notin kinds: kinds.add it.kind
    doAssert fileExists(base / it.thumbUrl), it.thumbUrl
    doAssert decodePng(readFile(base / it.thumbUrl)).w > 0
    if it.fullUrl.startsWith("template:"):
      var found = false
      for t in docTemplates():
        if "template:" & t.name == it.fullUrl: found = true
      doAssert found, it.fullUrl
      continue
    let data = readFile(base / it.fullUrl)
    case it.kind
    of akBrush: doAssert presetsFromJson(data).len == 1, it.id
    of akPattern: doAssert decodePng(data).w > 0
    of akSwatches: doAssert readAse(data).len >= 3
    of akStyle:
      let fx = layerFxFrom(parseJson(data)["fx"])
      var on = false
      for e in fx.fx:
        if e.on: on = true
      doAssert on, it.id
    of akGradient: doAssert parseJson(data)["stops"].len >= 2
    else: discard
  for k in [akBrush, akPattern, akGradient, akSwatches, akStyle, akDesign]: doAssert k in kinds, $k
  doAssert libraryCategories(items, akPattern).len >= 3
  echo "library: ok (", items.len, " items)"

block formats45:
  # JPEG XL written and read back exactly; an SVG opened as shape layers
  let d = newDoc(64, 48, 0xFF336699'u32)
  for i in 0 ..< d.w * d.h: d.layers[0].px[i] = argb(255, i mod 256, (i * 7) mod 256, (i * 13) mod 256)
  inc d.layers[0].ver
  let p = getTempDir() / "retro-test45.jxl"
  d.exportPicture(p, defaultExport(efJxl))
  let e = openPicture(p)
  doAssert e.w == 64 and e.h == 48
  doAssert e.flattened() == d.flattened()
  let svg = getTempDir() / "retro-test45.svg"
  writeFile(svg, """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>""")
  let s = openPicture(svg)
  doAssert s.w == 1024 and s.h == 1024
  var shapes = 0
  for L in s.layers:
    if L.isShape: inc shapes
  doAssert shapes >= 1
  echo "formats: ok"
