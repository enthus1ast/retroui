## Bugs found by hard-testing the toolkit (sanitizers, random input, odd
## looks), kept fixed, headless.

import std/[os, strutils]
import retro
import retro/zip
import retro/uirelays/[input, screen]
import harness

fakeDriver()
startApp("hardening", 640, 480)

# The bytes the C heap has given out (glibc, with -d:useMalloc as the tests
# are built): what a leak makes grow. 0 where it cannot be told (another C
# library, or a sanitizer's malloc -- LeakSanitizer tells it there).
when defined(linux) and defined(useMalloc) and not defined(android):
  type MallInfo2 {.importc: "struct mallinfo2", header: "<malloc.h>".} = object
    uordblks: csize_t
  proc mallinfo2(): MallInfo2 {.importc, header: "<malloc.h>".}
  proc heapInUse(): int = int(mallinfo2().uordblks)
else:
  proc heapInUse(): int = 0

template leaksNot(what: string; rounds: int; body: untyped) =
  ## `body` run `rounds` times keeps the heap where it was (give or take).
  for _ in 0 ..< 3: body                       # (caches and first growth)
  let before = heapInUse()
  for _ in 0 ..< rounds: body
  let grew = heapInUse() - before
  doAssert before == 0 or grew < 64 * 1024, what & ": the heap grew " & $grew & " bytes"

block paletteTabLabelsShow:
  # the tabs behind a palette's front tab: their label stands out from
  # their face in every built-in theme (in Gray it was gray on dark gray)
  for b in builtinThemes:
    ui.theme = b.theme
    var ink: Color
    var face: uint32
    view = proc () =
      ink = paletteTabFace(rect(10, 10, 60, 20), front = false, hover = false)
    run(2)
    face = px(30, 20)
    let back = color(uint8(face shr 16 and 255), uint8(face shr 8 and 255), uint8(face and 255))
    doAssert abs(lumaOfColor(ink) - lumaOfColor(back)) >= 70,
      b.name & ": a tab behind, label " & $lumaOfColor(ink) & " on " & $lumaOfColor(back)
  ui.theme = Classic

block pngReadFreesItsData:
  # every PNG read left its compressed data behind: `idat = @[]` after a
  # loop that filled it was taken by Nim 2.2 for a first value (no destroy)
  let b = newBitmap(120, 90)
  for i in 0 ..< b.px.len: b.px[i] = 0xFF000000'u32 or uint32(i * 2654435761'u32.int)
  let png = encodePng(b)
  leaksNot("decodePng", 200):
    doAssert decodePng(png).w == 120

block funnelChartFreesItsTexts:
  # a funnel too narrow for its texts with shares: `texts = shorter` leaked
  # the texts each frame (the same Nim 2.2 trouble)
  view = proc () =
    pushFrame(rect(0, 0, 300, 0))
    chart("", chFunnel, ["Leads from the web site", "Qualified by the sales team",
                         "Proposals sent", "Won"],
          [series("", [1200.0, 640, 310, 75])], height = 190)
    discard popFrame()
  run(2)
  leaksNot("funnelChart", 400):
    run(1)

block damagedZipEntriesFreed:
  # an entry whose checksum does not match: its content was put in
  # `result` before the check raised, and Nim 2.2 never freed it
  var z = newZipWriter()
  z.addFile("a.txt", "x".repeat(20_000))
  var zipData = z.finish()
  let dir = getTempDir() / "retro-hardening"
  createDir(dir)
  let path = dir / "damaged.zip"
  writeFile(path, zipData)
  var e = zipEntries(path)[0]
  e.crc = e.crc xor 1
  leaksNot("readEntry", 100):
    doAssertRaises(ZipError): discard readEntry(path, e)
  removeDir(dir)

block listColumnsKeepApart:
  # a list's tab stops grow with the UI's size and a column's text stops
  # short of the next (at 150% the columns ran into each other)
  setUiScale(150)
  var sel = -1
  let items = ["WWWWWWWWWWWWWWWWWWWWWWWW\tWWW", "AB\tCD"]
  view = proc () =
    pushFrame(rect(0, 0, 600, 0))
    listbox(items, sel, rows = 3, tabs = [110, 160])
    discard popFrame()
  run(3)
  proc ink(x, y: int): bool = (px(x, y) and 0xFF) < 100     # (black text on white)
  # the first row's band: where the text is (rows of the frame's lines,
  # dark across the whole list, left out)
  var top = -1
  var left = W
  for y in 2 ..< 80:
    var n = 0
    for x in 4 ..< 590:
      if ink(x, y): inc n
    if n == 0 or n > 300: continue
    if top < 0: top = y
    if y < top + FontH div 2:
      for x in 4 ..< 590:
        if ink(x, y):
          left = min(left, x)
          break
  doAssert top > 0 and left < W, "the list's text is drawn"
  let stop = left + dp(110)                    # (where the second column starts)
  for x in stop - dp(3) .. stop - 2:
    for y in top ..< top + FontH div 2:
      doAssert not ink(x, y), "the first column's text runs into the second at x " & $x
  setUiScale(100)

echo "hardening tests passed"
