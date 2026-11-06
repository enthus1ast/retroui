## Widgets for styled text (`retroui/textengine`): a font list that shows
## each family in its own letters, its styles, a sample of a style.
##
## ```nim
## var family = "FreeSans"
## var style = "Regular"
## if fontCombo(family, w = dp(160)): style = fontStyles(family)[0]
## fontStyleCombo(family, style, w = dp(100))
## ```

import std/[tables, math]
import core, gfx, widgets, textengine

var samples: Table[string, Bitmap]

proc fontSample*(family, style, text: string; h: int; color = 0xFF000000'u32): Bitmap =
  ## `text` in a font, `h` screen pixels tall (kept: drawn once).
  let key = family & "/" & style & "/" & text & "/" & $h & "/" & $color
  if samples.hasKey(key): return samples[key]
  if samples.len > 600: samples.clear()
  var st = defaultStyle()
  st.family = family
  st.style = style
  st.size = float32(h) * 0.74
  st.color = color
  var t = newText(text, st)
  let l0 = layoutText(t)
  let asc = if l0.lines.len > 0: l0.lines[0].ascent else: st.size
  let desc = if l0.lines.len > 0: l0.lines[0].descent else: 0'f32
  # (the line's middle in the picture's middle)
  t.y = float32(h) / 2 + (asc - desc) / 2
  t.x = 1
  let l = layoutText(t)
  let w = clamp(int(ceil(l.x1 - l.x0)) + 3, 1, 2000)
  result = newBitmap(w, h)
  result.px = t.renderText(w, h, l)
  result.changed()
  samples[key] = result

proc drawSample(r: Rect; family, style, text: string; color: uint32) =
  ## A sample drawn at the left of `r`, its middle on `r`'s.
  let hp = max(4, r.h * pxScale)
  let b = fontSample(family, style, text, hp, color)
  let bw = (b.w + pxScale - 1) div pxScale
  drawBitmap(rect(r.x, r.y, bw, r.h), b)

proc fontCombo*(family: var string; w = 0; enabled = true): bool {.discardable.} =
  ## A drop-down list of the font families (the system's and the built-in
  ## ones), each shown in its own letters.
  let fams = fontFamilies()
  var sel = max(0, fams.find(family))
  let preview: ItemPreview = proc (i: int; r: Rect; selected: bool) =
    let c = if selected: 0xFFFFFFFF'u32 else: 0xFF000000'u32
    drawSample(rect(r.x + 3, r.y, r.w - 3, r.h), fams[i], "Regular", fams[i], c)
  pushId("fontcombo" & $cast[uint](addr family))     # (one of its own for each variable)
  if combo(fams, sel, w = w, enabled = enabled, preview = preview) and sel in 0 .. fams.high:
    family = fams[sel]
    result = true
  popId()

proc fontStyleCombo*(family: string; style: var string; w = 0; enabled = true): bool {.discardable.} =
  ## The styles of `family` ("Regular", "Bold"...), each in its letters.
  let sts = fontStyles(family)
  var sel = max(0, sts.find(style))
  let preview: ItemPreview = proc (i: int; r: Rect; selected: bool) =
    let c = if selected: 0xFFFFFFFF'u32 else: 0xFF000000'u32
    drawSample(rect(r.x + 3, r.y, r.w - 3, r.h), family, sts[i], sts[i], c)
  if sts.find(style) < 0 and sts.len > 0 and style.len == 0: style = sts[0]
  pushId("stylecombo" & $cast[uint](addr style))
  if combo(sts, sel, w = w, enabled = enabled, preview = preview) and sel in 0 .. sts.high:
    style = sts[sel]
    result = true
  popId()
