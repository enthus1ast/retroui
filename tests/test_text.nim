## Tests of the text engine (fonts, Arabic, bidi), shapes, the layout
## helpers, the new widgets and Markdown -- headless, on the fake driver.

import std/[strutils, tables, times, unicode, math, os]
import retro
import retro/[typeset, ttf, raster]
import retro/uirelays/input
import harness

fakeDriver()
startApp("text", W, H)

# ---- fonts -----------------------------------------------------------------------------

block faces:
  let f = face(fSans)
  doAssert f.unitsPerEm == 2048
  doAssert f.glyphOf(ord('A')) != 0 and f.glyphOf(0x0628) != 0, "Latin and Arabic"
  doAssert face(fIcons).glyphOf(0xF07B) != 0, "the folder icon"
  doAssert f.kerning(f.glyphOf(ord('A')), f.glyphOf(ord('V'))) < 0, "A V kerns"
  let m = f.render(f.glyphOf(ord('H')), 20)
  doAssert m.w > 5 and m.h > 10
  var full = 0
  for a in m.a:
    if a == 255: inc full
  doAssert full > 20, "the stems are solid"

block widths:
  doAssert textWidth("") == 0
  let a = textWidth("Hello")
  doAssert a > 20 and a < 60, $a
  let b = textWidth("Hello", style(size = 2.0))
  # (big, MS W98 UI is drawn from its smooth outlines as big as the other
  # fonts -- 12 to the em, not the pixel font's 11)
  doAssert b >= 2 * a - 2 and b <= 2 * a * 12 div 11 + 3, $(a, b)
  doAssert textWidth("Hello", bold = true) >= a
  doAssert textWidth("WWW", style(mono = true)) == textWidth("iii", style(mono = true))
  doAssert lineHeight(style(size = 2.0)) > FontH * 3 div 2
  doAssert textWidth(nfFolder) > 0, "icons have width"

block arabic:
  let r = shape("بب")                  # beh beh: initial + final
  doAssert r.glyphs.len == 2 and r.rtl
  let f = face(fSans)
  var gids: seq[int]
  for g in r.glyphs: gids.add int(g.gid)
  doAssert f.glyphOf(0xFE91) in gids and f.glyphOf(0xFE90) in gids, $gids
  # visual order: the first letter (initial form) is on the right
  doAssert r.glyphs[0].gid == uint16(f.glyphOf(0xFE90))
  let la = shape("لا")                 # lam alef: one ligature
  doAssert la.glyphs.len == 1 and int(la.glyphs[0].gid) == f.glyphOf(0xFEFB)
  doAssert textIsRtl("مرحبا hello")
  doAssert not textIsRtl("hello مرحبا")
  doAssert not textIsRtl("123")

block bidi:
  # "ab ARABIC" in a left-to-right line: Latin first, the Arabic after it
  let f = face(fSans)
  let r = shape("ab بت")
  doAssert not r.rtl
  doAssert r.glyphs[0].gid == uint16(f.glyphOf(ord('a')))
  doAssert r.glyphs[0].x < r.glyphs[^1].x
  # numbers in Arabic text stay left to right
  let n = shape("ب 12")
  var order: seq[int]
  for g in n.glyphs:
    if g.gid == uint16(f.glyphOf(ord('1'))): order.add 1
    if g.gid == uint16(f.glyphOf(ord('2'))): order.add 2
  doAssert order == @[1, 2], $order
  # brackets around a number in Arabic text pair up
  let p = shape("ب (1)")
  doAssert p.glyphs.len == 5
  # an Arabic interface: a line that mixes Arabic with Latin and numbers
  # reads right to left ("1.0 GB" at the right, "252 GB" at the left); a
  # line without Arabic (a file's name) keeps left to right
  let mixed = "1.0 GB متاحة من 252 GB"
  doAssert not shape(mixed).rtl
  setRtlInterface(true)
  let m = shape(mixed)
  doAssert m.rtl
  var one, two = -1.0'f32
  for g in m.glyphs:
    if g.gid == uint16(f.glyphOf(ord('1'))) and one < 0: one = g.x
    if g.gid == uint16(f.glyphOf(ord('5'))): two = g.x
  doAssert one > two, "1.0 at the right of 252: " & $(one, two)
  doAssert not shape("notes (draft)!").rtl
  let v = visualCodepoints(mixed)
  doAssert v[^1].cp == ord('0') and v[^3].cp == ord('1'), "the line ends (at the right) with 1.0"
  setRtlInterface(false)
  doAssert not shape(mixed).rtl

block rasterizer:
  var r = newRaster(10, 10)
  r.line(2, 2, 2, 8)
  r.line(2, 8, 8, 8)
  r.line(8, 8, 8, 2)
  r.line(8, 2, 2, 2)
  let c = r.coverage()
  doAssert c[5 * 10 + 5] == 255 and c[0] == 0 and c[5 * 10 + 9] == 0

block textSize:
  let h = FontH
  setTextScale(150)
  doAssert FontH > h and textSize() > 12
  setTextScale(100)
  doAssert FontH == h

# ---- layout ------------------------------------------------------------------------------

var
  rects: seq[Rect]
  springR: Rect
  formR: Rect

block sizeClasses:
  doAssert sizeClass() == scMedium, "640 pixels wide"
  doAssert responsive(1, 2, 3) == 2
  doAssert columnsFor(200) == 3

block rows:
  view = proc () =
    rects.setLen(0)
    row([-1, -2]):
      discard button("A")
      rects.add ui.lastRect
      discard button("B")
      rects.add ui.lastRect
    row:
      label "left"
      spring()
      discard button("Right")
      springR = ui.lastRect
  run(3)
  doAssert abs(rects[1].w - 2 * rects[0].w) <= 2, $rects
  doAssert springR.x + springR.w >= W - 2 * Pad - 2, $springR

block adaptiveCols:
  view = proc () =
    rects.setLen(0)
    adaptive(180):
      for i in 0 ..< 5:
        card("Card " & $i):
          label "x"
        rects.add ui.lastRect
  run(3)
  doAssert rects[0].y == rects[1].y and rects[1].y == rects[2].y, "three in a row"
  doAssert rects[3].y > rects[0].y, "then the next row"

block smartForm:
  var s = ""
  view = proc () =
    form(0):
      field "Name:": edit s
      formR = ui.lastRect
  run(3)
  doAssert formR.x > Pad + textWidth("Name:"), "the label column fits the label"

block pageScroll:
  view = proc () =
    for i in 0 ..< 40:
      discard button("Button " & $i)
  run(3)
  doAssert ui.pageOn and ui.pageMax > 0
  queue.add Event(kind: MouseMoveEvent, x: 100, y: 100)
  queue.add Event(kind: MouseWheelEvent, y: -3)
  run(2)
  doAssert ui.pageY > 0, "the wheel scrolls the window's content"

block pageScrollBars:
  # fingers get the standard scroll bar too (not a thin indicator)
  ui.touch = true
  view = proc () =
    for i in 0 ..< 40:
      discard button("Button " & $i)
  ui.pageY = 0
  run(3)
  doAssert ui.pageOn
  let bx = W - SbW div 2
  # (the track is a white and gray checkerboard: two pixels side by side)
  doAssert px(bx, H div 2) != 0xFFFFFF or px(bx + 1, H div 2) != 0xFFFFFF,
    "a scroll bar at the right edge on touch screens"
  # its down arrow scrolls
  let y0 = ui.pageY
  down(bx, H - SbW div 2 - 1)
  run()
  up(bx, H - SbW div 2 - 1)
  run()
  doAssert ui.pageY > y0, "the arrow scrolls the page"
  ui.touch = false
  # a row of fixed widths wider than the window: a bar along the bottom
  var far: Rect
  view = proc () =
    row([400, 400]):
      discard button("Left")
      discard button("Far right")
      far = ui.lastRect
  ui.pageY = 0
  run(3)
  doAssert ui.pageMaxX > 0 and not ui.pageOn, "wider: scrolls sideways"
  doAssert px(W div 2, H - SbW div 2) != 0xFFFFFF or
           px(W div 2 + 1, H - SbW div 2) != 0xFFFFFF, "the bottom bar is drawn"
  let x0 = far.x
  queue.add Event(kind: MouseMoveEvent, x: 100, y: 50)
  queue.add Event(kind: MouseWheelEvent, y: -3)
  run(2)
  doAssert ui.pageX > 0 and far.x < x0, "the wheel scrolls sideways"
  # Tab to the far button brings it into view
  ui.pageX = 0
  run(2)                                   # ("Left" has the focus)
  key(KeyTab)
  run(2)
  doAssert far.x + far.w <= W, "the focused button is scrolled into view: " & $far
  # ... and down: Tab to a button below the window scrolls the page
  view = proc () =
    for i in 0 ..< 40:
      discard button("Button " & $i)
      if i == 30: far = ui.lastRect
  ui.pageX = 0
  ui.pageY = 0
  ui.focus = 0
  run(3)
  for i in 0 .. 30:
    key(KeyTab)
    run()
  run()
  doAssert far.y >= 0 and far.y + far.h <= H, "Tab scrolls down to the focus: " & $far
  view = proc () = discard button("small")
  run(3)
  doAssert ui.pageMaxX == 0 and ui.pageX == 0, "back to fitting"

block barsDoNotScroll:
  # a tool bar too narrow for its buttons (a "more" button at its right
  # end), a status bar drawn first and content down to it: no page bars
  ui.pageX = 0
  ui.pageY = 0
  var s = "text"
  view = proc () =
    toolbar:
      for i in 0 ..< 20:
        discard toolButton(pxCopy, "Copy " & $i)
    statusbar("Ready")
    scrollPanel -1:
      edit s
  run(4)
  doAssert ui.pageMaxX == 0 and not ui.pageOn,
    "bars and content that fills down to the status bar fit the window"

block uiScale:
  let c = CtrlH
  setUiScale(150)
  doAssert CtrlH > c and dp(10) == 15
  setUiScale(100)
  doAssert CtrlH == c

# ---- new widgets --------------------------------------------------------------------------

block switches:
  var on = false
  var seg = 0
  var q = "abc"
  var stars = 0
  view = proc () =
    toggle("Wi-Fi", on)
    rects.setLen(0)
    rects.add ui.lastRect
    segmented(["One", "Two", "Three"], seg)
    rects.add ui.lastRect
    searchBox(q)
    rects.add ui.lastRect
    rating(stars)
    rects.add ui.lastRect
  run(2)
  click(rects[0], 8)
  run()
  doAssert on
  click(rects[1], rects[1].w - 10)
  run()
  doAssert seg == 2
  click(rects[2], rects[2].w - 6)                  # the clear button
  run()
  doAssert q == ""
  click(rects[3], rects[3].w - 4)
  run()
  doAssert stars == 5

block expanderCard:
  var open = false
  var shown = false
  view = proc () =
    shown = false
    expander("More", open):
      shown = true
      label "inside"
    rects.setLen(0)
    rects.add ui.lastRect
  run(2)
  doAssert not shown
  key(KeyTab)
  key(KeyRight)
  run()
  doAssert open and shown

block chipsBadges:
  var ev: ChipEvent
  view = proc () =
    ev = chips(["a", "b"], [true, false], closable = true)
    badge("3")
    spinner()
  run(2)
  doAssert ev.clicked == -1

block lineViewer:
  var sel = 0
  var ev: LineViewEvent
  view = proc () =
    ev = lineView(1000, proc (i: int): string = "line " & $i, sel, height = 200,
                  numbers = true)
  run(2)
  key(KeyTab)
  key(KeyDown)
  key(KeyDown)
  run()
  doAssert sel == 2, $sel
  key(KeyC, {CtrlPressed})
  run()
  doAssert getClipboardText() == "line 2\n"

block colors:
  var c = color(0, 0, 0)
  doAssert hexOf(color(255, 128, 0)) == "#FF8000"
  doAssert parseHexColor("#0f0", c) and c == color(0, 255, 0)
  doAssert not parseHexColor("nope", c)

# ---- Markdown -----------------------------------------------------------------------------

const md = """
# Title

Some *text* with **bold** and a [link](http://x.org).

1. one
2. two
   - nested

- [ ] open
- [x] done

> quoted

```nim
echo 1
```

| A | B |
|:--|--:|
| 1 | 2 |

---
"""

block parse:
  let d = parseMarkdown(md)
  var kinds: seq[BlockKind]
  for b in d.blocks: kinds.add b.kind
  doAssert kinds == @[bkHeading, bkPara, bkList, bkList, bkQuote, bkCode, bkTable,
                      bkRule], $kinds
  doAssert d.blocks[0].level == 1 and d.blocks[0].text == "Title"
  doAssert d.blocks[2].ordered and d.blocks[2].kids.len == 2
  doAssert d.blocks[2].kids[1].kids[^1].kind == bkList, "nested list"
  doAssert d.blocks[3].kids[0].task == 0 and d.blocks[3].kids[1].task == 1
  doAssert d.tasks == 2
  doAssert d.blocks[5].lang == "nim" and d.blocks[5].text == "echo 1"
  doAssert d.blocks[6].rows.len == 2 and d.blocks[6].aligns == @['l', 'r']

block setextAndRefs:
  let d = parseMarkdown("Heading\n=======\n\nSee [the site][s].\n\n[s]: http://s.org\n")
  doAssert d.blocks[0].kind == bkHeading and d.blocks[0].level == 1
  doAssert d.refs["s"] == "http://s.org"

block tasks:
  var s = "- [ ] a\n- [ ] b\n"
  toggleTask(s, 1)
  doAssert s == "- [ ] a\n- [x] b\n", s
  toggleTask(s, 1)
  doAssert s == "- [ ] a\n- [ ] b\n"

block mdView:
  var ev: MdEvent
  var r: Rect
  view = proc () =
    ev = markdownView(md, height = 400)
    r = ui.lastRect
  run(2)
  doAssert ev.link == "" and ev.task == -1
  # find the link's pixels: blue-ish text in the first lines
  var found = false
  for y in r.y .. r.y + 120:
    for x in r.x .. r.x + r.w - 20:
      let p = px(x, y)
      if (p and 0xFF) >= 128 and ((p shr 16) and 0xFF) < 80 and
         ((p shr 8) and 0xFF) < 80: found = true      # (navy in the 3.1 colors)
  doAssert found, "the link is drawn in the link color"

block wrapping:
  let words = wrapLines("one two three four five six", textWidth("one two three"))
  doAssert words[0] == "one two three", $words
  # a long path breaks after a "/" rather than inside a name
  let path = "/storage/emulated/0/Pictures/Holidays/IMG_20240101.jpg"
  let lines = wrapLines(path, textWidth("/storage/emulated/0/Pict"))
  doAssert lines.join("") == path, $lines
  doAssert lines[0].endsWith("/"), $lines
  for l in lines: doAssert textWidth(l) <= textWidth("/storage/emulated/0/Pict")
  # nothing to break at: cut where it must
  let solid = wrapLines(repeat('x', 200), 50)
  doAssert solid.join("") == repeat('x', 200) and solid.len > 2

block arabicEdgeCases:
  # tatweel and the zero width joiner join letters but have no forms
  for s in ["ـ", "بـب", "\u200Dب", "ب\u200D", "لا", "ل\u0651ا", "\u064Bب", "ﻻ"]:
    doAssert textWidth(s) >= 0
    doAssert wrapLines(s & " " & s, 20).len >= 1

block hostileMarkdown:
  # deep nesting and long runs of markup: shown (as text), quickly, no crash
  var hostile = @["> ".repeat(20000) & "x", "- ".repeat(20000) & "x",
                  "*".repeat(30000) & "x" & "*".repeat(30000),
                  "[".repeat(20000) & "x" & "](u)".repeat(2000), "![".repeat(20000),
                  "`".repeat(20000), "|".repeat(5000) & "\n|-|\n" & "|".repeat(5000)]
  var nested = ""
  for i in 0 ..< 400: nested.add " ".repeat(i * 2) & "- item\n"
  hostile.add nested
  for md in hostile:
    let t0 = epochTime()
    view = proc () = discard markdownView(md, height = 300)
    run(2)
    doAssert epochTime() - t0 < 5.0, "too slow: " & md[0 .. 20]

# ---- Retro Sans, the Windows 3.1 font -----------------------------------------------------------

block retroSans:
  doAssert uiFont() == ufW98, "the default font"
  view = proc () = discard
  setUiFont(ufRetro)
  run(2)
  doAssert textSize() == 12 and FontH == 16 and FontAscent == 12, $(textSize(), FontH, FontAscent)
  # every Latin-1 and Latin Extended-A letter, in both weights, bitmaps and outlines
  for cp in 0xA1 .. 0x17F:
    if cp == 0xAD: continue
    let s = $Rune(cp)
    doAssert textWidth(s) > 0 and textWidth(s, bold = true) > 0, "U+" & toHex(cp, 4)
    doAssert face(fRetro).glyphOf(cp) != 0 and face(fRetroBold).glyphOf(cp) != 0, "U+" & toHex(cp, 4)
  for s in ["€", "…", "•", "‹", "›", "„", "‚", "™", "✓", "→", "≤"]:
    doAssert face(fRetro).hasGlyph(s.runeAt(0).int), s
  # the outlines advance as the bitmaps do: the same widths either way
  for s in ["Hello", "Grüße", "Łódź", "x"]:
    doAssert textWidth(s) == int(round(widthEm(s, fRetro) * 12)), s
  # sizes are whole bricks: twice the size, twice the width
  doAssert textWidth("Hello", style(size = 2.0)) == 2 * textWidth("Hello")
  doAssert lineHeight(style(size = 2.0)) == 2 * FontH

block retroPixels:
  # at 100 % the text is the bitmaps: black and white only, no grays
  view = proc () =
    label "Program Manager"
    label "مرحبا بالعالم Hello"
  run(3)
  var black, gray = 0
  for y in 0 ..< 60:
    for x in 0 ..< 200:
      let p = px(x, y)
      if p == 0: inc black
      elif p != 0xFFFFFF and (p and 0xFF) == ((p shr 8) and 0xFF) and
           (p and 0xFF) == ((p shr 16) and 0xFF): inc gray
  doAssert black > 100 and gray == 0, $(black, gray)
  # Latin with a character only DejaVu has (Greek): the Latin letters are
  # still the bitmaps, in the same places
  var a, b: Rect
  view = proc () =
    text(10, 100, "Abc", color(0, 0, 0))
    text(10, 130, "AbcΩ", color(0, 0, 0))
  run(3)
  for y in 0 ..< 16:
    for x in 0 ..< textWidth("Abc"):
      doAssert px(10 + x, 100 + y) == px(10 + x, 130 + y), "the same pixels at " & $(x, y)

block retroArabicMix:
  # Arabic comes from Unifont on the same baseline, Latin after it in a
  # right-to-left line
  let w1 = textWidth("مرحبا")
  let w2 = textWidth("Hello")
  doAssert w1 > 0 and textWidth("مرحبا Hello") == w1 + w2 + textWidth(" "), $(w1, w2)
  doAssert textWidth("بب", bold = true) == textWidth("بب"), "bold Arabic: the same advance"
  view = proc () = label "ملف جديد (12)", bold = true
  run(3)
  var ink = 0
  for y in 0 ..< 30:
    for x in 0 ..< 200:
      if px(x, y) == 0: inc ink
  doAssert ink > 30

block retroHD:
  # at 2x the smooth outlines: the edges are anti-aliased, the stems solid
  setZoom(2)
  view = proc () = label "Program Manager VAWX"
  run(3)
  var black, gray = 0
  for y in 0 ..< 60:
    for x in 0 ..< 400:
      let p = px(x, y)
      if p == 0: inc black
      elif p != 0xFFFFFF: inc gray
  doAssert black > 200 and gray > 20, $(black, gray)
  setZoom(0)
  run(2)
  doAssert FontH == 16

block switchFonts:
  let h = FontH
  let c = CtrlH
  setUiFont(ufSmooth)
  view = proc () = discard button("OK")
  run(2)
  doAssert uiFont() == ufSmooth and FontH != h and CtrlH != c, $(FontH, CtrlH)
  var s: Settings
  storeAppearance(s)
  doAssert s.getOrDefault("look.font") == "smooth"
  setUiFont(ufRetro)
  run(2)
  doAssert FontH == h and CtrlH == c
  restoreAppearance(s)
  run(2)
  doAssert uiFont() == ufSmooth
  # an old "look.pixelfont = false" (everyone's, before) does not turn it off
  var old: Settings
  old.put("look.pixelfont", false)
  setUiFont(ufRetro)
  restoreAppearance(old)
  doAssert uiFont() == ufRetro
  setPixelFont(false)
  doAssert uiFont() == ufSmooth and not usesPixelFont()
  setUiFont(ufRetro)
  run(2)

block wrappedLinesKeepTheParagraphDirection:
  # an English paragraph wrapped so that a line starts with Arabic: that
  # line is still laid out from the left (and the other way round)
  let p = "Their Arabic is what letters say: a tag as #[الجنسية]# gives عماني for Omani people here."
  var lines: seq[string]
  view = proc () =
    lines = wrapLines(p, 120)
  run(1)
  doAssert lines.len > 2
  for l in lines: doAssert not textIsRtl(l), "line read from the right: " & l
  let q = "تشهد إدارة الفندق بأن السيد أحمد يعمل لدينا بوظيفة Receptionist منذ عام 2018 وما زال"
  view = proc () =
    lines = wrapLines(q, 90)
  run(1)
  for l in lines: doAssert textIsRtl(l), "line read from the left: " & l

# ---- Kawkab Mono, the default UI font ------------------------------------------------------------

block kawkabMono:
  view = proc () = discard   # (the last block's view has its variables gone)
  setZoom(0)
  setTextScale(100)
  setUiFont(ufKawkab)
  run(2)
  doAssert uiFont() == ufKawkab
  var s: Settings
  storeAppearance(s)
  doAssert s.getOrDefault("look.font") == "kawkab"
  # monospaced, a whole number of pixels a letter: every string is a multiple
  let one = textWidth("x")
  doAssert one >= 6 and one <= 10, $one
  for t in ["iii", "WWW", "Hello", "a.b,c", "مرحبا", "Grüße"]:
    doAssert textWidth(t) mod one == 0, t & " " & $textWidth(t)
  doAssert textWidth("iii") == textWidth("WWW")
  doAssert textWidth("Hello", bold = true) == textWidth("Hello"), "bold: the same advance"
  # Arabic joins (presentation forms in the font) and lam-alef is one letter
  let f = face(fKawkab)
  doAssert f.glyphOf(0xFE91) != 0 and f.glyphOf(0xFEFB) != 0
  doAssert textWidth("لا") == one
  # crisp: at 100 % the stems of H and l are solid columns
  view = proc () = text(10, 10, "HlHl", color(0, 0, 0))
  run(3)
  var solid = 0
  for x in 10 ..< 10 + 4 * one:
    var col = 0
    for y in 10 ..< 10 + FontH:
      if px(x, y) == 0: inc col
    if col >= FontH div 2: inc solid
  doAssert solid >= 4, $solid
  # at 2x and 150 % too: the letters stay whole pixels apart
  for z in [2, 0]:
    setZoom(z)
    for sc in [100, 125, 150]:
      setTextScale(sc)
      run(1)
      let w = textWidth("x")
      doAssert textWidth("Hello world") == 11 * w, $(z, sc, w)
  setTextScale(100)
  setZoom(0)
  run(2)

# ---- a font from a file ------------------------------------------------------------------------------------

block fontFile:
  view = proc () = discard
  let dir = currentSourcePath().parentDir.parentDir / "src" / "retro" / "fonts"
  # a pixel font (Retro Sans's bitmaps as squares): on its grid
  setUiFontFile(readFile(dir / "RetroSans.ttf"), readFile(dir / "RetroSansBold.ttf"))
  run(2)
  doAssert uiFont() == ufFile and hasUserFont()
  let g = pixelGrid(fUser)
  doAssert g > 0, "a pixel font"
  # the size: a whole number of its pixels a pixel of the screen
  doAssert abs(textSize() - 12) < 0.01
  view = proc () = text(10, 10, "HHHH llll", color(0, 0, 0))
  run(3)
  var gray = 0
  for y in 8 ..< 30:
    for x in 8 ..< 120:
      let p = px(x, y)
      if p != 0 and p != 0xFFFFFF and (p and 0xFF) == ((p shr 8) and 0xFF): inc gray
  doAssert gray == 0, "crisp: " & $gray
  doAssert textWidth("Hello", bold = true) > 0
  # an outline font: drawn smooth, no grid
  setUiFontFile(readFile(dir / "Sans.ttf"))
  doAssert pixelGrid(fUser) == 0
  # not a font
  var failed = false
  try: setUiFontFile("not a font at all, really not")
  except FontError: failed = true
  doAssert failed and uiFont() == ufFile
  # kept, and found again (its bold beside it)
  let tmp = getTempDir() / "retro-fonts"
  createDir(tmp)
  writeFile(tmp / "Pixel-Regular.ttf", readFile(dir / "RetroSans.ttf"))
  writeFile(tmp / "Pixel-Bold.ttf", readFile(dir / "RetroSansBold.ttf"))
  doAssert boldBeside(tmp / "Pixel-Regular.ttf") == tmp / "Pixel-Bold.ttf"
  loadUiFontFile(tmp / "Pixel-Regular.ttf")
  var st: Settings
  storeAppearance(st)
  doAssert st.getOrDefault("look.font") == "file" and st.getOrDefault("look.fontfile") == tmp / "Pixel-Regular.ttf"
  setUiFont(ufKawkab)
  restoreAppearance(st)
  doAssert uiFont() == ufFile and pixelGrid(fUser) > 0
  removeDir(tmp)
  setUiFont(ufKawkab)
  run(2)

# ---- MS W98 UI, the default UI font ---------------------------------------------------------------

block msW98:
  view = proc () = discard
  setZoom(0)
  setTextScale(100)
  setUiFont(ufW98)
  run(2)
  doAssert hasW98() and pixelGrid(fW98) == 11 and pixelGrid(fW98Bold) == 11
  # MS Sans Serif's size: 11 pixels per em (8 points), a 13-pixel line
  doAssert FontH == 13, $FontH
  # every edge on a pixel: widths are whole pixels of the 11 grid
  for t in ["Hello", "File  Edit  Image", "0123456789", "WWW iii"]:
    let w = widthEm(t, fW98) * 11
    doAssert abs(w - round(w)) < 0.1, t
    doAssert textWidth(t) == int(round(w)), t & " " & $textWidth(t)
  doAssert textWidth("Hello", bold = true) >= textWidth("Hello")
  # Arabic from the font itself (joined forms); bold Arabic falls back to the regular
  doAssert face(fW98).glyphOf(0x627) != 0 and face(fW98).glyphOf(0xFE8E) != 0
  doAssert textWidth("مرحبا") > 0 and textWidth("مرحبا", bold = true) > 0
  # monospaced text is DejaVu Sans Mono
  doAssert textWidth("iii", style(mono = true)) == textWidth("WWW", style(mono = true))
  # kept and brought back; the old default (Kawkab, stored before W98) becomes W98
  var st: Settings
  storeAppearance(st)
  doAssert st.getOrDefault("look.font") == "w98"
  setUiFont(ufSmooth)
  restoreAppearance(st)
  doAssert uiFont() == ufW98
  var old: Settings
  old["look.font"] = "kawkab"
  setUiFont(ufSmooth)
  restoreAppearance(old)
  doAssert uiFont() == ufSmooth, "an old stored default changes nothing"
  var chosen: Settings
  chosen["look.font"] = "kawkab"
  chosen["look.fontv"] = "2"
  restoreAppearance(chosen)
  doAssert uiFont() == ufKawkab, "a choice of Kawkab is kept"
  # at 200 %, twice the pixels: still on the grid
  setZoom(2)
  run(2)
  setUiFont(ufW98)
  run(2)
  let w2 = textWidth("Hello")
  setZoom(0)
  run(2)
  doAssert w2 == textWidth("Hello"), "logical widths stay: " & $(w2, textWidth("Hello"))
  run(2)

echo "text tests passed"

block rasterOddNumbers:
  # NaN, infinite and absurdly large coordinates (a chart of NaN, a path
  # scaled by nothing): no area, and nothing written outside the raster
  var r = newRaster(64, 48)
  let nan = NaN.float32
  let inf = Inf.float32
  for (a, b, c, d) in [(nan, 0'f32, 10'f32, 40'f32), (0'f32, nan, 10'f32, 40'f32),
                       (inf, 0'f32, 10'f32, 40'f32), (-inf, 5'f32, 30'f32, 20'f32),
                       (1e35'f32, 0'f32, -1e35'f32, 40'f32), (5'f32, -1e35'f32, 6'f32, 1e35'f32),
                       (10'f32, 1e-7'f32, 1e37'f32, 1e-5'f32), (-1e30'f32, -1e30'f32, 1e30'f32, 1e30'f32)]:
    r.line(a, b, c, d)
    r.edge(a, b, c, d)
  # a real square still fills as it should next to them
  r.edge(8, 8, 24, 8); r.edge(24, 8, 24, 24); r.edge(24, 24, 8, 24); r.edge(8, 24, 8, 8)
  r.accumulate()
  doAssert r[16 * 64 + 16] > 0.99
  for i in 0 ..< 64 * 48:
    let v = r[i]
    doAssert v == v and v >= 0 and v <= 1, $i
