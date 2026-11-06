## How long the image engine takes on a big photo (24 megapixels by
## default): opening, the filters, the adjustments, transforms, the view.
##
##   nim c -r -d:release tests/bench_photo.nim [picture.jpg]

import std/[os, times, strutils, monotimes]
import retroui/[gfx, imaging, photo, photopaint, photofx, photodevelop]

proc ms(t: MonoTime): string = formatFloat((getMonoTime() - t).inMicroseconds.float / 1000, ffDecimal, 1) & " ms"

let path = if paramCount() >= 1: paramStr(1) else: ""
var t = getMonoTime()
var d: Doc
if path.len > 0:
  d = openImage(path)
  echo "open ", path.extractFilename, " (", d.w, " x ", d.h, "): ", ms(t)
else:
  d = newDoc(6000, 4000)
  for y in 0 ..< d.h:
    for x in 0 ..< d.w: d.layer.px[y * d.w + x] = argb(255, x mod 256, y mod 256, (x * y) mod 256)
  d.markAll()
  echo "made 6000 x 4000"

template step(name: string; body: untyped) =
  t = getMonoTime()
  body
  echo alignLeft(name, 28), ms(t)

step "composite (all)":
  d.markAll()
  d.updateComposite()
step "levels":
  d.applyFilter(0, applyLuts(levelsLut(Levels(inLo: 20, inHi: 230, gamma: 1.2, outLo: 0, outHi: 255)),
                             identityLut(), identityLut(), identityLut()))
step "hue/saturation":
  d.applyFilter(0, hueSaturation(20, 10, 0))
step "gaussian blur 2":
  d.applyFilter(8, gaussianBlur(2))
step "gaussian blur 20":
  d.applyFilter(44, gaussianBlur(20))
step "unsharp mask":
  d.applyFilter(8, unsharpMask(80, 1.5, 2))
step "median 3":
  d.applyFilter(4, median(3))
step "develop (tone, color)":
  d.applyFilter(0, develop(Develop(exposure: 30, contrast: 20, vibrance: 20, temperature: 10)))
step "develop (local: shadows...)":
  d.applyFilter(0, develop(Develop(shadows: 30, highlights: -30, clarity: 20, dehaze: 10)))
step "develop (detail)":
  d.applyFilter(12, develop(Develop(noise: 30, colorNoise: 30, sharpen: 40)))
step "auto develop":
  discard autoDevelop(Img(w: d.w, h: d.h, px: d.layer.px))
step "twirl":
  d.applyFilter(0, twirl(90))
step "image size to 4000 x 2667":
  d.imageSize(4000, 2667, rsBicubic)
step "rotate 15 degrees":
  d.rotateArbitrary(15, 0xFFFFFFFF'u32)
step "histogram":
  discard d.histogram()
step "composite (all) again":
  d.markAll()
  d.updateComposite()
