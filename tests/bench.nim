## How long a frame takes, with a fake driver (pure library cost: layout,
## widget logic, rasterizing). Run:  nimble bench

import std/[monotimes, times, strutils, os]
import retro/uirelays/[coords, screen, input]
import retro

const W = 800
const H = 600

var
  pixelsOut = 0
  ticks = 0

windowRelays.createWindow = proc (l: var ScreenLayout; icon: pointer; n: int) =
  l.width = W; l.height = H; l.scaleX = 1; l.scaleY = 1; l.uiScale = 100
windowRelays.refresh = proc () = discard
windowRelays.setWindowTitle = proc (t: string) = discard
windowRelays.setCursor = proc (c: CursorKind) = discard
drawRelays.blitRGBA = proc (p: ptr UncheckedArray[uint32]; w, h: int;
                            dst: Rect; f: RGBAFormat): bool =
  pixelsOut += w * h
  true
var pending: seq[Event]
inputRelays.pollEvent = proc (e: var Event; fl: set[InputFlag]): bool =
  if pending.len == 0: return false
  e = pending[0]
  pending.delete(0)
  true
inputRelays.waitEvent = proc (e: var Event; t: int; fl: set[InputFlag]): bool = false
inputRelays.getTicks = proc (): int = ticks

var
  name = "Untitled project"
  notes = "Line one\nLine two\nLine three\nLine four"
  a, b = true
  c = false
  r = 1
  v = 40
  sel = 2
  lang = 0
  items: seq[string]
for i in 0 ..< 200: items.add "Item number " & $i & "\t" & $(i * 3) & " KB"

proc gallery() =
  menubar:
    menu "&File": discard menuItem("E&xit")
    menu "&Edit": discard menuItem("&Copy")
    menu "&Help": discard menuItem("&About")
  toolbar:
    for ic in [icNew, icOpen, icSave, icCut, icCopy, icPaste, icPrint, icHelp]:
      toolButton(ic, "tip")
  statusbar("Ready", "NUM")
  row([-1, -1, -1]):
    group "Buttons":
      for i in 0 ..< 4:
        row:
          button("OK " & $i, isDefault = i == 0)
          button("Cancel " & $i)
    group "Choices":
      checkbox "Auto save", a
      checkbox "Backups", b
      checkbox "Grid", c
      radio "Small", r, 0
      radio "Medium", r, 1
      radio "Large", r, 2
    group "Text":
      edit name
      spin v, 0, 100
      combo ["English", "Deutsch", "Français"], lang
  row([-1, -1]):
    group "Values":
      slider v, 0, 100
      progress(v / 100)
      hscroll v, 0, 100, 10
    group "Lists":
      listbox items, sel, rows = 8, tabs = [120]
  editArea notes, lines = 6

var
  scene = 0
  cols = @[column("No.", 70, alRight), column("Customer", 200),
           column("Amount", 100, alRight), column("Status", 80)]
  gsel = 0
  tsel = "Sales/Invoices"
  o1, o2 = true
  navW = 180
  sales = [12.0, 19, 8, 15, 22, 17, 9, 14, 21, 18, 11, 16]

proc cell(r, c: int): string =
  case c
  of 0: $(100000 + r)
  of 1: "Customer number " & $(r mod 977)
  of 2: formatNumber(float(r mod 5000) * 1.25)
  else: (if r mod 3 == 0: "Open" else: "Paid")

proc business() =
  menubar:
    menu "&File": discard menuItem("E&xit")
  statusbar("100,000 invoices")
  split(navW, -1):
    tree(tsel, -1):
      branch "Sales", o1:
        leaf "Invoices"
        leaf "Customers"
      branch "Reports", o2:
        leaf "Monthly"
  do:
    grid(cols, 100_000, cell, gsel, height = 18)
    barChart(sales, [], "Sales", h = 150)

var folder = newFolderModel()
for i in 0 ..< 50_000:
  folder.all.add FileItem(name: "IMG_" & $(20240000 + i * 7 mod 99991) & ".jpg",
                          path: "/x/IMG_" & $i & ".jpg", size: int64(i) * 1733,
                          modified: fromUnix(1_700_000_000 + i * 60))
folder.applyView()
var fileView = fvDetails

proc files() =
  menubar:
    menu "&File": discard menuItem("E&xit")
  statusbar("50,000 files")
  discard fileList(folder, fileView, thumbnails = false)

proc frame() =
  discard beginFrame()
  case scene
  of 0: gallery()
  of 1: business()
  else: files()
  endFrame()
  ticks += 16

proc measure(label: string; n: int; prep: proc ()) =
  for _ in 0 ..< 5: (prep(); frame())
  pixelsOut = 0
  let t0 = getMonoTime()
  for _ in 0 ..< n:
    prep()
    frame()
  let us = (getMonoTime() - t0).inMicroseconds.float / n.float
  echo label.alignLeft(34), formatFloat(us, ffDecimal, 1).align(9), " us/frame",
       ($(pixelsOut div n)).align(10), " px blitted"

startApp("bench", W, H)
for _ in 0 ..< 5: frame()
measure("full redraw (800x600, invalidated)", 300, proc () = invalidate())
measure("nothing changed", 3000, proc () = discard)
var k = 0
measure("one value changed (slider)", 1000, proc () =
  inc k
  v = k mod 100)

scene = 1
for _ in 0 ..< 5: frame()
measure("business: 100,000-row grid + chart", 300, proc () = invalidate())
measure("business: wheel-scroll the grid", 300, proc () =
  pending.add Event(kind: MouseMoveEvent, x: 500, y: 200)
  pending.add Event(kind: MouseWheelEvent, y: -1))

scene = 2
for _ in 0 ..< 5: frame()
measure("files: 50,000 files, details", 300, proc () = invalidate())
measure("files: wheel-scroll them", 300, proc () =
  pending.add Event(kind: MouseMoveEvent, x: 400, y: 300)
  pending.add Event(kind: MouseWheelEvent, y: -1))
fileView = fvIcons
for _ in 0 ..< 5: frame()
measure("files: 50,000 files, icons", 300, proc () = invalidate())
measure("files: wheel-scroll the icons", 300, proc () =
  pending.add Event(kind: MouseMoveEvent, x: 400, y: 300)
  pending.add Event(kind: MouseWheelEvent, y: -1))

# ---- work that is not drawing --------------------------------------------------------------

proc timeIt(label: string; n: int; body: proc ()) =
  body()
  let t0 = getMonoTime()
  for _ in 0 ..< n: body()
  let ms = (getMonoTime() - t0).inMicroseconds.float / 1000 / n.float
  echo label.alignLeft(34), formatFloat(ms, ffDecimal, 1).align(9), " ms"

var many = folder.all
timeIt("sort 50,000 names naturally", 5, proc () =
  var x = many
  sortFiles(x, byName))
let data = getEnv("RETRO_BENCH_DATA")
if data.len > 0:
  let png = readFile(data / "big.png")
  timeIt("decode a 2000x1500 PNG", 3, proc () = discard decodePng(png))
  let jpg = readFile(data / "photo12mp.jpg")
  timeIt("decode a 12 MP JPEG", 2, proc () = discard decodeJpeg(jpg))
  timeIt("... its 1/8 thumbnail", 5, proc () = discard decodeJpeg(jpg, 8))
  let prog = readFile(data / "photo12mp-prog.jpg")
  timeIt("decode a 12 MP progressive JPEG", 2, proc () = discard decodeJpeg(prog))
