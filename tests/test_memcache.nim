## Memory and caches: the device's numbers, the picture cache letting go
## when memory runs short or the program goes to the background, the
## thumbnails kept on disk (found again, told apart by the file's time,
## trimmed to their limit), a long session staying inside its budget.

import std/[os, strutils, times, random]
import retro, retro/[memwatch, thumbcache]
import harness

fakeDriver()
startApp("memcache", W, H)

proc waitFor(cond: proc (): bool; what: string; seconds = 15.0) =
  let until = epochTime() + seconds
  while not cond():
    doAssert epochTime() < until, "timed out: " & what
    run()
    os.sleep(2)

let root = getTempDir() / "retro-memcache-test"
removeDir(root)
createDir(root)

proc noisePng(path: string; w, h, seed: int) =
  ## A picture that does not compress (so it is big: worth a disk thumbnail).
  var r = initRand(seed)
  let b = newBitmap(w, h)
  for p in b.px.mitems: p = 0xFF000000'u32 or uint32(r.rand(0xFFFFFF))
  writeFile(path, encodePng(b, level = 1))

block numbers:
  let n = memoryNumbers()
  when defined(linux):
    doAssert n.device > 0 and n.free > 0 and n.program > 0, $n
    doAssert n.free <= n.device and n.program < n.device
  let b = cacheBudget()
  doAssert b >= 16 * 1024 * 1024 and b <= 192 * 1024 * 1024
  doAssert memoryReport().startsWith("Memory: ") or n.device == 0
  pretendMemoryPressure(mpLow)
  doAssert memoryPressure() == mpLow
  pretendMemoryPressure(mpNone, on = false)
  echo "numbers: ", memoryReport()

block pressure:
  # pictures kept; the device runs short: all but those on screen go
  for i in 0 ..< 6: noisePng(root / ("p" & $i & ".png"), 120, 90, i)
  let c = pictures()
  view = proc () =
    for i in 0 ..< 6: discard c.get(root / ("p" & $i & ".png"), 64, 64)
  waitFor(proc (): bool =
    for i in 0 ..< 6:
      if c.get(root / ("p" & $i & ".png"), 64, 64) == nil: return false
    true, "decoding")
  let all = c.pixelsKept
  doAssert all > 0
  # still shown: kept
  pretendMemoryPressure(mpCritical)
  run(2)
  doAssert c.pixelsKept == all, $c.pixelsKept
  # no longer shown: let go (the next time the caches are told: when the
  # level rises again, or ten seconds on)
  pretendMemoryPressure(mpNone, on = false)
  view = proc () = discard c.get(root / "p0.png", 64, 64)
  run(2)
  pretendMemoryPressure(mpCritical)
  run(2)
  pretendMemoryPressure(mpNone, on = false)
  doAssert c.pixelsKept < all and c.pixelsKept > 0, $c.pixelsKept & " of " & $all
  # sent to the background: nothing kept
  view = proc () = discard
  ui.paused = true
  run()
  doAssert c.pixelsKept == 0, $c.pixelsKept
  ui.paused = false
  run()
  echo "pressure: ok"

block diskCache:
  let tc = root / "thumbs"
  useThumbCache(tc, 2 * 1024 * 1024)
  doAssert thumbCacheOn()
  let big = root / "big.png"
  noisePng(big, 600, 400, 99)
  doAssert worthKeeping(big) and not worthKeeping(root / "p0.png")
  doAssert worthKeeping("x.CR3", 10) and worthKeeping("clip.mp4", 10)
  # made once on a worker thread, then kept
  let c = newPictureCache()
  view = proc () = discard c.get(big, 100, 100)
  waitFor(proc (): bool = c.get(big, 100, 100) != nil, "the thumbnail")
  var kept = 0
  for f in walkDirRec(tc):
    doAssert f.endsWith(".jpg"), f
    inc kept
  doAssert kept == 1
  let side = 144                         # (the size `get` asks for 100)
  let t = cachedThumb(big, side)
  doAssert t != nil and t.w == 144 and t.h == 96, $t.w & "x" & $t.h
  # a changed file: not the old one
  setLastModificationTime(big, getTime() + initDuration(seconds = 5))
  doAssert cachedThumb(big, side) == nil
  # transparent pictures keep their transparency (a PNG)
  let clear = newBitmap(40, 30)
  keepThumb(big, 64, clear)
  let back = cachedThumb(big, 64)
  doAssert back != nil and (back.px[0] shr 24) == 0
  # many: the folder stays under its limit
  var r = initRand(7)
  for i in 0 ..< 160:
    let f = root / ("n" & $i & ".bin")
    writeFile(f, "x")
    let b = newBitmap(200, 150)
    for p in b.px.mitems: p = 0xFF000000'u32 or uint32(r.rand(0xFFFFFF))
    keepThumb(f, 216, b)
  let size = thumbCacheBytes()
  doAssert size <= 2 * 1024 * 1024, $size
  doAssert size > 256 * 1024, $size
  clearThumbCache()
  doAssert thumbCacheBytes() == 0
  useThumbCache("")
  doAssert not thumbCacheOn() and cachedThumb(big, side) == nil
  echo "disk cache: ok (", size div 1024, " KB after trimming)"

block longSession:
  # a long scroll through a big folder: the cache never holds more than
  # its budget (plus what one frame shows)
  for i in 0 ..< 120: noisePng(root / ("s" & $i & ".png"), 160, 120, 1000 + i)
  let c = newPictureCache(budget = 30 * 160 * 120)
  var at = 0
  var most = 0
  view = proc () =
    for k in 0 ..< 8: discard c.get(root / ("s" & $((at + k) mod 120) & ".png"), 160, 160)
  for step in 0 ..< 90:
    at = (step * 4) mod 120
    for _ in 0 ..< 6:
      run()
      os.sleep(1)
    most = max(most, c.pixelsKept)
  doAssert most <= 30 * 160 * 120 + 8 * 160 * 120, $most
  echo "long session: ok (most ", most div 1000, "k pixels)"

removeDir(root)
echo "memory and cache tests passed"
