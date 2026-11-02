## Tests of the PDF reader (retro/pdfread): the kit's own PDFs read back --
## their pages drawn, their text, their outlines -- the same file with
## compressed object streams (when qpdf is there), damaged files.

import std/[os, osproc, strutils, math]
import retro/[gfx, pdf, pdfread]

let dir = getTempDir() / "retro-pdfread-test"
removeDir(dir)
createDir(dir)

# a page with text, shapes, a picture and CMYK
var doc = newPdf("Reader test", author = "Retro")
let p = doc.addPage(A5)
p.text(mm(15), mm(20), "Hello PDF reader", size = 20, bold = true)
p.text(mm(15), mm(32), "مرحبا بالعالم", size = 14)
p.box(mm(15), mm(45), mm(60), mm(30), fill = color(200, 30, 30))
p.fillCmyk(1, 0, 0, 0)
p.ellipse(mm(110), mm(60), mm(15), mm(15))
p.fill()
let pic = newBitmap(4, 4)
for i in 0 ..< 16: pic.px[i] = if i mod 2 == 0: 0xFF00FF00'u32 else: 0xFF0000FF'u32
p.image(pic, mm(15), mm(90), mm(40), mm(40))
discard doc.addPage(A5)
let path = dir / "t.pdf"
doc.save(path)

let f = openPdf(readFile(path))
doAssert f.pageCount == 2
let (w, h) = f.pageSize(0)
doAssert abs(w - A5.w) < 0.5 and abs(h - A5.h) < 0.5
let b = f.renderPage(0, dpi = 72)
doAssert b.w == int(ceil(A5.w)) and b.h == int(ceil(A5.h))
proc at(x, y: float): uint32 = b.px[int(y) * b.w + int(x)]
# (the red box, the cyan disc, the picture's green and blue)
let red = at(mm(45), mm(60))
doAssert ((red shr 16) and 255) > 180 and ((red shr 8) and 255) < 60, "red: " & toHex(red)
let cyan = at(mm(110), mm(60))
doAssert ((cyan shr 16) and 255) < 80 and (cyan and 255) > 150, "cyan: " & toHex(cyan)
let px = at(mm(35), mm(110))
doAssert (px and 0xFFFFFF'u32) in [0x00FF00'u32, 0x0000FF'u32] or ((px shr 8) and 255) > 100 or (px and 255) > 100
let white = at(mm(140), mm(190))
doAssert (white and 0xFFFFFF'u32) == 0xFFFFFF'u32
# (the text: its glyphs drawn dark somewhere on its line)
var dark = 0
for x in int(mm(15)) ..< int(mm(80)):
  for y in int(mm(18)) ..< int(mm(30)):
    if (b.px[y * b.w + x] and 255) < 100: inc dark
doAssert dark > 50, "the text is drawn: " & $dark
let t = f.pageText(0)
doAssert "Hello PDF reader" in t, t
doAssert "مرحبا" in t or "بالعالم" in t, t
let vs = f.pageVectors(0)
doAssert vs.len >= 2, "the box and the disc as outlines: " & $vs.len

# the same with object streams and a cross-reference stream
if findExe("qpdf").len > 0:
  let p2 = dir / "objstm.pdf"
  discard execCmdEx("qpdf --object-streams=generate " & quoteShell(path) & " " & quoteShell(p2))
  if fileExists(p2):
    let f2 = openPdf(readFile(p2))
    doAssert f2.pageCount == 2
    doAssert "Hello PDF reader" in f2.pageText(0)

# damaged: the cross-reference table cut off (the objects are found anyway)
var bad = readFile(path)
bad = bad[0 ..< bad.rfind("xref")]
let f3 = openPdf(bad)
doAssert f3.pageCount == 2
# not a PDF; encrypted
var raised = false
try: discard openPdf("hello world, not a pdf at all")
except PdfError: raised = true
doAssert raised
# junk never crashes it
for n in 0 ..< 60:
  var s = readFile(path)
  for k in 0 ..< 40:
    let i = (n * 7919 + k * 104729) mod s.len
    s[i] = char((n * 31 + k * 17) and 255)
  try:
    let g = openPdf(s)
    for i in 0 ..< g.pageCount: discard g.renderPage(i, 20)
  except PdfError: discard
echo "pdf reader tests passed"
