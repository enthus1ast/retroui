## How fast the file widgets are with a very large folder: listing 20,000
## files, frames of the details, icons and columns views while scrolling,
## filtering as the user types, sorting -- and the memory they keep.

import std/[os, strutils, times, monotimes]
import retroui
import retroui/uirelays/input
import harness

fakeDriver()
startApp("filespeed", W, H)

proc waitFor(cond: proc (): bool; what: string; seconds = 30.0) =
  let until = epochTime() + seconds
  while not cond():
    doAssert epochTime() < until, "timed out: " & what
    run()
    os.sleep(1)

let root = getTempDir() / "retro-filespeed"
removeDir(root)
createDir(root)
const N = 20_000
for i in 0 ..< N:
  let name = (case i mod 5
              of 0: "report " & $i & ".pdf"
              of 1: "IMG_" & align($i, 5, '0') & ".txt"
              of 2: "notes-" & $i & ".md"
              of 3: "data_" & $i & ".csv"
              else: "Song " & $i & ".mp3")
  writeFile(root / name, "x")
for i in 0 ..< 200: createDir(root / ("folder " & $i))

proc ms(t0: MonoTime): float = (getMonoTime() - t0).inMicroseconds.float / 1000

let m = newFolderModel(root)
var t0 = getMonoTime()
view = proc () = discard fileList(m, fvDetails)
waitFor(proc (): bool = m.dir == root and not m.loading and m.items.len == N + 200, "listing")
echo "listing ", N + 200, " items: ", int(ms(t0)), " ms"

proc frames(name: string; n = 60): float =
  ## ms a frame while the list scrolls (the wheel, down then up).
  let t = getMonoTime()
  for i in 0 ..< n:
    queue.add Event(kind: MouseMoveEvent, x: W div 2, y: H div 2)
    queue.add Event(kind: MouseWheelEvent, y: (if i < n div 2: -3 else: 3))
    run()
  result = ms(t) / n.float
  echo name, ": ", formatFloat(result, ffDecimal, 2), " ms a frame"

let details = frames("details")
view = proc () = discard fileList(m, fvIcons, iconSize = 48, thumbnails = false)
run(3)
let icons = frames("icons")
view = proc () = discard fileList(m, fvSmallIcons, thumbnails = false)
run(3)
let small = frames("small icons")
view = proc () = discard fileColumns(m, root = root.parentDir)
run(3)
let cols = frames("columns")
# filtering as the user types
view = proc () = discard fileList(m, fvDetails)
t0 = getMonoTime()
for q in ["r", "re", "rep", "repo", "report 1", "report 19"]:
  m.setFilter(q)
  run()
let filt = ms(t0) / 6
echo "filter as typed: ", formatFloat(filt, ffDecimal, 2), " ms a key"
m.setFilter("")
run()
# sorting by each column
t0 = getMonoTime()
for k in [bySize, byKind, byDate, byName]:
  m.sortBy = k
  m.applyView()
  run()
let sorts = ms(t0) / 4
echo "sort: ", formatFloat(sorts, ffDecimal, 1), " ms"
# (release builds: a frame well within 16 ms; debug builds are slower)
when defined(release):
  doAssert details < 8 and icons < 8 and small < 8 and cols < 10, "frames too slow"
  doAssert filt < 30 and sorts < 120
echo "memory: ", memoryReport()
removeDir(root)
echo "file speed tests passed"
