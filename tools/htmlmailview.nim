## A mail's HTML in `htmlView`, as Retro Mail shows it: to try pages, time
## them and take screenshots.
##
##   nim c -d:release tools/htmlmailview.nim
##   tools/htmlmailview tests/data/mail/newsletter.html
##   tools/htmlmailview --pictures mail.html     # stand-ins for the pictures it wants
##   tools/htmlmailview --dark mail.html         # in the Dark theme
##   tools/htmlmailview --text mail.html         # its plain text (htmlToText), then quit
##   tools/htmlmailview --time mail.html         # how long it takes to lay out, then quit
##   tools/htmlmailview --scroll:600 mail.html   # scrolled down 600 pixels at the start
##
## The status bar shows the link under the pointer and what the page wants.

import std/[os, strutils, monotimes, times, hashes, tables]
import retro

var
  path = ""
  pictures, darkTheme, textOnly, timeOnly = false
  scroll = 0

for a in commandLineParams():
  case a
  of "--pictures": pictures = true
  of "--dark": darkTheme = true
  of "--text": textOnly = true
  of "--time": timeOnly = true
  else:
    if a.startsWith("--scroll:"): scroll = parseInt(a[9 .. ^1])
    else: path = a

if path.len == 0 or not fileExists(path):
  quit "usage: htmlmailview [--pictures] [--dark] [--text] [--time] [--scroll:N] page.html"

let html = readFile(path)
let baseDir = path.parentDir

if textOnly:
  echo htmlToText(html)
  quit 0

if timeOnly:
  for w in [880, 600, 380]:
    let t0 = getMonoTime()
    let info = htmlPageInfo(html, w, baseDir)
    let ms = float((getMonoTime() - t0).inMicroseconds) / 1000
    echo w, " px: ", formatFloat(ms, ffDecimal, 2), " ms, ", info.height, " px high, ",
         info.words.len, " pieces of text, ", info.links.len, " link areas"
  quit 0

var stand: Table[string, Bitmap]

proc standIn(src: string): Bitmap =
  ## A made-up picture for `src` (a stripe pattern in a color of its own),
  ## shaped as its name suggests.
  let l = src.toLowerAscii
  let (w, h) = if "hero" in l: (1200, 600)
               elif "logo" in l: (360, 96)
               elif "bag" in l: (500, 500)
               else: (96, 96)
  let hv = uint32(hash(src)) and 0xFFFFFF'u32
  let base = hv or 0xFF404040'u32
  result = newBitmap(w, h)
  for y in 0 ..< h:
    for x in 0 ..< w:
      let band = ((x + y) div max(4, w div 12)) mod 2 == 0
      result.px[y * w + x] = if band: base else: (base and 0xFFE0E0E0'u32) or 0xFF1F1F1F'u32
  result.changed()

let images: HtmlImageSource = proc (src: string): Bitmap = stand.getOrDefault(src)

var
  hoverText = ""
  clicked = ""
  wanted = 0

app "HTML Mail View", 900, 700, (if darkTheme: Dark else: Classic):
  if scroll > 0 and ui.frameNo > 2:
    state(idOf("htmlviewmail")).scrollY = scroll
    scroll = 0
  let ev = htmlView(html, baseDir = baseDir, key = "mail", images = images,
                    height = remainingH() - CtrlH - Gap)
  if ev.link.len > 0: clicked = ev.link
  hoverText = ev.hover
  wanted = ev.wantedImages.len
  if pictures and ev.wantedImages.len > 0:
    var added = false
    for src in ev.wantedImages:
      if src notin stand:
        stand[src] = standIn(src)
        added = true
    if added: htmlImagesChanged()
  statusbar(if hoverText.len > 0: hoverText
            elif clicked.len > 0: "Clicked: " & clicked
            else: path.extractFilename,
            $wanted & " pictures wanted")
