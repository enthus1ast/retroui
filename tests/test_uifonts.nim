## Tests of the built-in UI fonts Fixedsys Excelsior and Open Sans: their
## lines, Fixedsys's pixel grid at 100 % and 200 %, Arabic from the other
## faces, bold, the canvas's font names, and keeping the choice --
## headless, on the fake driver. Also built with -d:retroNoFixedsys
## -d:retroNoOpenSans (the stand-ins).

import std/[unicode, math]
import retro
import retro/[typeset, ttf, canvas2d]
import harness

fakeDriver()
startApp("uifonts", W, H)

proc ink(x0, y0, w, h: int): tuple[dark, between: int] =
  ## In the rectangle (device pixels): pixels of black text, and pixels
  ## between black and the background (anti-aliased edges).
  let bg = px(x0, y0)
  for y in y0 ..< y0 + h:
    for x in x0 ..< x0 + w:
      let p = px(x, y)
      if p == 0: inc result.dark
      elif p != bg: inc result.between

proc show(s: string; st = TextStyle()) =
  view = proc () = text(10, 10, s, color(0, 0, 0), st)
  run(3)

block names:
  # the words settings keep, both ways, for every font
  for f in UiFont:
    var g = ufW98
    doAssert uiFontOfKey(uiFontKey(f), g) == (f != ufFile), $f
    if f != ufFile: doAssert g == f, $f
  var g = ufW98
  doAssert not uiFontOfKey("nonsense", g) and g == ufW98
  doAssert uiFontKey(ufFixedsys) == "fixedsys" and uiFontKey(ufOpenSans) == "opensans"
  doAssert ufFixedsys in builtinUiFonts and ufOpenSans in builtinUiFonts and ufFile notin builtinUiFonts
  # added at the end: the old fonts keep their numbers
  doAssert ord(ufFile) == 4 and ord(ufFixedsys) == 5 and ord(ufOpenSans) == 6
  doAssert $ufFixedsys == "Fixedsys Excelsior" and $ufOpenSans == "Open Sans"

# ---- Fixedsys Excelsior ----------------------------------------------------------------------------

block fixedsysLine:
  view = proc () = discard
  setZoom(0)
  setTextScale(100)
  setUiFont(ufFixedsys)
  run(2)
  doAssert uiFont() == ufFixedsys
  if hasFixedsys():
    doAssert pixelGrid(fFixedsys) == 12 and pixelGrid(fFixedsysBold) == 12
    doAssert pixelGrid(fFixedsysHD) == 0, "the HD outlines are not snapped"
    # its 16-pixel line: 13 above the baseline, 3 below
    doAssert textSize() == 12 and FontH == 16 and FontAscent == 13, $(textSize(), FontH, FontAscent)
    let f = face(fFixedsys)
    doAssert f.unitsPerEm == 1200 and f.ascent == 1300 and f.descent == -300
    doAssert fontName(f, 1) == "Fixedsys Excelsior"
    # 8 pixels a letter, monospaced text included
    doAssert textWidth("x") == 8
    for t in ["iii", "WWW", "Hello", "a.b,c", "Grüße", "Ωμέγα", "Привет", "╔══╗"]:
      doAssert textWidth(t) == 8 * t.runeLen, t & " " & $textWidth(t)
      doAssert textWidth(t, style(mono = true)) == textWidth(t), t
    for cp in [0xC5, 0x152, 0x3A9, 0x416, 0x2554, 0x2588, 0x20AC, 0x2192]:
      doAssert f.glyphOf(cp) != 0, "U+" & $cp
    # letters drawn as others are (Cyrillic р as p, Greek μ as µ) have their ink
    for cp in [0x440, 0x435, 0x43E, 0x3BC, 0x3BF, 0x7C, 0x6C, 0x2500]:
      for hf in [fFixedsys, fFixedsysHD]:
        let b = face(hf).bounds(face(hf).glyphOf(cp))
        doAssert b.x1 > b.x0 and b.y1 > b.y0, "U+" & $cp & " has no ink"
    # left out: the controls, the private use area (the icons'), its own Arabic
    doAssert f.glyphOf(1) == 0 and f.glyphOf(0xE000) == 0 and f.glyphOf(0x627) == 0
    doAssert face(fFixedsysHD).glyphOf(ord('A')) != 0
  else:
    # (left out: DejaVu Sans Mono stands in, smooth)
    doAssert pixelGrid(fFixedsys) == 0 and face(fFixedsys).glyphOf(ord('A')) != 0
    doAssert textWidth("iii") == textWidth("WWW")

block fixedsysCrisp:
  if hasFixedsys():
    # at 100 % every pixel of the letters is a screen pixel: black or not
    show("Hello AVWXZ 0123 Ж ╬")
    var k = ink(8, 8, 8 * 20 + 8, 20)
    doAssert k.dark > 150 and k.between == 0, $k
    # bold: the same advance, a pixel more ink to the right, still crisp
    show("Hello AVWXZ 0123", style(bold = true))
    let b = ink(8, 8, 8 * 16 + 8, 20)
    doAssert textWidth("Hello", bold = true) == textWidth("Hello")
    show("Hello AVWXZ 0123")
    let r = ink(8, 8, 8 * 16 + 8, 20)
    doAssert b.dark > r.dark + 40 and b.between == 0, $(b, r)
    # 200 %, pixels: every pixel two by two, crisp; the same logical widths
    setHdText(false)
    setZoom(2)
    run(2)
    doAssert FontH == 16 and textWidth("Hello") == 40
    show("Hello AVWXZ 0123")
    k = ink(16, 16, 2 * (8 * 16 + 8), 40)
    doAssert k.dark > 4 * r.dark - 10 and k.between == 0, $(k, r)
    # 200 %, HD (the default): smooth diagonals, straight edges still on pixels
    setHdText(true)
    run(2)
    doAssert FontH == 16 and textWidth("Hello") == 40
    show("AVWXZ")
    k = ink(16, 16, 2 * (8 * 5 + 8), 40)
    doAssert k.dark > 100 and k.between > 20, "smooth: " & $k
    # (corners cut and joins filled by the smoothing; the stems' edges on
    # the pixels: H's rows between its corners and its bar are crisp)
    let hd = face(fFixedsysHD)
    let m = hd.render(hd.glyphOf(ord('H')), 24, hint = true)
    doAssert m.h == 18 and m.w >= 12, $(m.w, m.h)
    for y in [2, 3, 4, 5, 12, 13, 14, 15]:
      var solid = 0
      for x in 0 ..< m.w:
        let a = m.a[y * m.w + x]
        doAssert a == 0 or a == 255, "H, row " & $y & ": " & $a
        if a == 255: inc solid
      doAssert solid == 8, "two stems two pixels wide: " & $solid
    show("HHLLTT")
    k = ink(16, 16, 2 * (8 * 6 + 8), 40)
    doAssert k.dark > 300 and k.between < k.dark div 3, $k
    show("HHLLTT", style(bold = true))
    let hb = ink(16, 16, 2 * (8 * 6 + 8), 40)
    doAssert hb.dark > k.dark + 40, "bold at 2x: " & $(hb, k)
    setZoom(0)
    run(2)
    # large text at 100 %: the HD outlines at exactly the size asked for
    doAssert lineHeight(style(size = 1.5)) == 24
    show("AVWXZ", style(size = 1.5))
    k = ink(8, 8, 12 * 5 + 8, 30)
    doAssert k.dark > 60 and k.between > 10, $k
    doAssert textWidth("Hello", style(size = 2.0)) == 80

block fixedsysArabic:
  # Arabic from Unifont's 8 x 16 glyphs (Retro Sans Arabic), joined
  let run = shape("مرحبا", fFixedsys)
  doAssert not run.missing and run.glyphs.len == 5
  for g in run.glyphs: doAssert g.face == fRetroAr, $g.face
  doAssert textWidth("مرحبا") > 0 and textWidth("لا") > 0
  doAssert textWidth("مرحبا Hello") == textWidth("مرحبا") + textWidth(" Hello")
  doAssert textWidth("بب", bold = true) == textWidth("بب")
  if hasFixedsys():
    # at 100 %: Unifont's own pixels, crisp, beside the Latin
    show("مرحبا بالعالم Hello")
    let k = ink(8, 4, 200, 24)
    doAssert k.dark > 60 and k.between == 0, $k
    show("مرحبا", style(bold = true))
    let b = ink(8, 4, 60, 24)
    show("مرحبا")
    let r = ink(8, 4, 60, 24)
    doAssert b.dark > r.dark, $(b, r)

block fixedsysCanvas:
  let c = newCanvas2D(200, 60)
  c.font = "12px Fixedsys"
  let w = c.measureText("Hello").width
  if hasFixedsys(): doAssert abs(w - 40) < 0.01, $w
  c.font = "12px monospace"           # (the UI's font is Fixedsys: monospace is it)
  doAssert abs(c.measureText("Hello").width - w) < 0.01
  c.fillText("Hello", 2, 20)

block fixedsysKept:
  var s: Settings
  storeAppearance(s)
  doAssert s.getOrDefault("look.font") == "fixedsys"
  setUiFont(ufSmooth)
  run(1)
  doAssert FontH != 16 or not hasFixedsys()
  restoreAppearance(s)
  run(1)
  doAssert uiFont() == ufFixedsys
  if hasFixedsys(): doAssert FontH == 16

# ---- Open Sans --------------------------------------------------------------------------------------

block openSansLine:
  view = proc () = discard
  setZoom(0)
  setTextScale(100)
  setUiFont(ufOpenSans)
  run(2)
  doAssert uiFont() == ufOpenSans and pixelGrid(fOpenSans) == 0
  let f = face(fOpenSans)
  if hasOpenSans():
    doAssert fontName(f, 1) == "Open Sans" and f.unitsPerEm == 2048
    doAssert face(fOpenSansBold).weight == 700
    for cp in [0xC5, 0x1EA0, 0x3A9, 0x416, 0x20AC, 0x2026, 0x2122]:
      doAssert f.glyphOf(cp) != 0, "U+" & $cp
  # the font's own line, at the UI's 12 pixels to the em
  doAssert textSize() == 12
  doAssert FontH == int(round(12 * (lineFactor(fOpenSans) + 0.02))), $FontH
  doAssert FontAscent > FontH div 2 and FontAscent < FontH, $(FontH, FontAscent)
  if hasOpenSans(): doAssert FontH == 17, $FontH
  # proportional; bold is wider; monospaced text is DejaVu Sans Mono
  doAssert textWidth("iii") < textWidth("WWW")
  doAssert textWidth("Hello world", bold = true) > textWidth("Hello world")
  doAssert textWidth("iii", style(mono = true)) == textWidth("WWW", style(mono = true))

block openSansSmooth:
  show("Hello AVWXZ")
  let k = ink(8, 8, 120, 22)
  doAssert k.dark > 20 and k.between > 40, "anti-aliased: " & $k
  let w1 = textWidth("Hello AVWXZ")
  setZoom(2)
  run(2)
  doAssert abs(textWidth("Hello AVWXZ") - w1) <= 1, $(w1, textWidth("Hello AVWXZ"))
  show("Hello AVWXZ")
  let k2 = ink(16, 16, 240, 44)
  doAssert k2.dark > 3 * k.dark, $(k, k2)
  setZoom(0)
  run(2)

block openSansFallback:
  # Arabic (which Open Sans lacks) from DejaVu Sans; Greek and Cyrillic its own
  # (left out, DejaVu Sans stands in: its own Arabic)
  let run = shape("مرحبا", fOpenSans)
  doAssert not run.missing
  for g in run.glyphs: doAssert g.face == (if hasOpenSans(): fSans else: fOpenSans), $g.face
  if hasOpenSans():
    for g in shape("Ωμέγα Привет", fOpenSans).glyphs: doAssert g.face == fOpenSans
  for g in shape("مرحبا", fOpenSansBold).glyphs:
    doAssert g.face == (if hasOpenSans(): fBold else: fOpenSansBold), $g.face
  doAssert textWidth("مرحبا") > 0 and textWidth("مرحبا", bold = true) > 0
  show("مرحبا Hello")
  doAssert ink(8, 4, 120, 24).dark > 10

block openSansCanvas:
  let c = newCanvas2D(200, 60)
  c.font = "20px Open Sans"
  let a = c.measureText("Hello").width
  c.font = "20px sans-serif"          # (the UI's font is Open Sans: sans-serif is it)
  doAssert abs(c.measureText("Hello").width - a) < 0.01
  setUiFont(ufSmooth)
  c.font = "20px sans-serif"
  if hasOpenSans(): doAssert abs(c.measureText("Hello").width - a) > 0.5, "DejaVu is wider"
  c.font = "bold 20px 'Open Sans'"
  doAssert c.measureText("Hello").width > a
  setUiFont(ufOpenSans)

block openSansKept:
  var s: Settings
  storeAppearance(s)
  doAssert s.getOrDefault("look.font") == "opensans"
  setUiFont(ufFixedsys)
  restoreAppearance(s)
  doAssert uiFont() == ufOpenSans

block backToDefault:
  setUiFont(ufW98)
  run(2)
  doAssert FontH == 13

echo "ui font tests passed"
