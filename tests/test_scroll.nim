## Smooth scrolling: the wheel's and the keys' glides, a finger that drags
## and flicks, the scroll bar's thumb and arrows, rows scrolled part way,
## and all of it switched off.

import harness, retroui
import retroui/uirelays/[coords, input]

fakeDriver()
startApp("scroll", W, H)

const sid = Id(0x5c0011'u32)
const barId = Id(0x5c0200'u32)
let area = rect(0, 0, 300, 300)
var v = 0                    # a scroller's position, pixels
var hi = 1000
var useBar = false

view = proc () =
  if useBar:
    scrollBarFor(barId, sid, rect(300, 0, 17, 300), true, v, hi, 250, 20)
  scrollWheel(sid, v, hi, area, 45)
  scrollPan(sid, v, hi, area)
  if ui.key == KeyPageDown and not ui.keyUsed:
    ui.keyUsed = true
    scrollBy(sid, v, 250, hi)
  scrollTick(sid, v, hi)

proc wheel(notches: int; x = 100; y = 100) =
  move(x, y)
  queue.add Event(kind: MouseWheelEvent, y: notches)

proc settle() =
  ## Frames until nothing moves (at most two seconds' worth).
  run(1)
  for i in 0 .. 120:
    if not scrolling(sid): break
    run(1)

proc touchScreen(on: bool) =
  ui.touch = on
  run(1)

run(2)

block wheelGlides:
  wheel(-1)
  run(1)
  let first = v
  doAssert first > 0 and first < 45, "a notch glides: it is on its way " & $first
  run(1)
  doAssert v > first and v < 45, "a little further each frame: " & $v
  settle()
  doAssert v == 45, "and stops where the notch goes: " & $v
  doAssert not scrolling(sid), "then nothing moves (no more frames asked for)"
  doAssert ui.wakeAt == 0 or ui.wakeAt > ui.now + 400, "no frames asked for when idle"

block notchesAddUp:
  wheel(-1)
  run(1)
  wheel(-1)
  run(1)
  wheel(-1)
  settle()
  doAssert v == 45 + 3 * 45, "notches that keep coming add up: " & $v
  wheel(30)                         # far back up: it stops at the top
  settle()
  doAssert v == 0, "never past the top: " & $v
  wheel(-100)
  settle()
  doAssert v == hi, "nor past the end: " & $v
  v = 0
  run(1)

block notchEveryFrame:
  # a fast wheel (a notch every frame) moves at once, every frame -- it
  # does not wait for the notches to stop
  var seen: seq[int]
  for i in 0 ..< 6:
    wheel(-1)
    run(1)
    seen.add v
  doAssert seen[0] > 0 and seen[^1] > seen[2] and seen[2] > seen[0],
    "it moves while the notches come: " & $seen
  settle()
  doAssert v == 6 * 45, $v
  v = 0
  run(1)

block keysGlide:
  key(KeyPageDown)
  run(1)
  doAssert v > 0 and v < 250, "Page Down glides too: " & $v
  settle()
  doAssert v == 250, $v
  v = 0
  run(1)

block thumbAndArrows:
  useBar = true
  run(2)
  # the arrow at the bottom: a step, gliding
  down(308, 291)
  run(1)
  up(308, 291)
  run(1)
  doAssert v > 0 and v < 20, "an arrow's step glides: " & $v
  settle()
  doAssert v == 20, $v
  # the thumb follows the mouse at once, pixel by pixel
  let thumbY = 17 + (20 * (300 - 34 - 17)) div hi + 8
  down(308, thumbY)
  run(1)
  move(308, thumbY + 50)
  run(1)
  let dragged = v
  doAssert dragged > 150, "the thumb drags the content along: " & $dragged
  doAssert not scrolling(sid), "with no glide behind it"
  move(308, thumbY + 51)
  run(1)
  doAssert v > dragged and v - dragged < 10, "a pixel of thumb: a few of content " &
    $dragged & " " & $v
  up(308, thumbY + 51)
  run(1)
  useBar = false
  v = 0
  run(1)

block fingerFlicks:
  touchScreen(true)
  # a finger that drags moves the content exactly with it
  down(100, 250)
  run(1)
  move(100, 240)                    # (past the slop: it pans from here)
  run(1)
  let before = v
  move(100, 200)
  run(1)
  doAssert v - before == 40, "the content follows the finger: " & $(v - before)
  # ... and a flick keeps it going, slower and slower
  for y in countdown(180, 60, 20):
    move(100, y)
    run(1)
  up(100, 60)
  run(1)
  let lifted = v
  doAssert scrolling(sid), "a flick flies on"
  run(2)
  let later = v
  doAssert later > lifted, "after the finger is gone: " & $lifted & " -> " & $later
  run(2)
  doAssert v - later < later - lifted + 1, "slowing down"
  settle()
  doAssert v <= hi and v > later, "it stops by itself, in the content: " & $v
  # a finger that lands on it while it flies stops it
  v = 0
  run(1)
  down(100, 280)
  run(1)
  for y in countdown(260, 100, 40):
    move(100, y)
    run(1)
  up(100, 100)
  run(2)
  doAssert scrolling(sid)
  down(150, 150)
  run(1)
  let caught = v
  doAssert not scrolling(sid), "a finger stops it"
  doAssert scrollCaught(), "... and that tap only stops it"
  up(150, 150)
  run(2)
  doAssert v == caught
  # dragged, then held still before lifting: no flick
  v = 0
  run(1)
  down(100, 250)
  run(1)
  for y in countdown(230, 150, 20):
    move(100, y)
    run(1)
  run(6)                            # (resting ~200 ms)
  let held = v
  up(100, 150)
  run(3)
  doAssert v == held and not scrolling(sid), "held still, then lifted: it stays"
  touchScreen(false)
  v = 0
  run(1)

block switchedOff:
  setSmoothScrolling(false)
  wheel(-1)
  run(1)
  doAssert v == 45 and not scrolling(sid), "without smooth scrolling the wheel jumps"
  key(KeyPageDown)
  run(1)
  doAssert v == 295, $v
  setSmoothScrolling(true)
  v = 0
  run(1)

# ---- in the widgets ------------------------------------------------------------------

var items: seq[string]
for i in 0 ..< 100: items.add "Item " & $i
var sel = 0
var lr: Rect
var cols = @[column("Name", 200), column("Size", 80)]
var gsel = 1
var gr: Rect

block listboxGlides:
  view = proc () =
    discard listbox(items, sel, rows = 10, w = 200)
    lr = ui.lastRect
  run(2)
  wheel(-1, lr.x + 50, lr.y + 20)
  for i in 0 .. 30: run(1)
  click(lr, 20, 1 + ItemH div 2)    # the first row in view
  doAssert sel == 3, "a notch: three rows, then the click picks the first shown " & $sel
  # keys: Page Down moves the selection and the rows glide after it
  key(KeyPageDown)
  run(1)
  for i in 0 .. 30: run(1)
  doAssert sel == 12, $sel
  click(lr, 20, lr.h - 2 - ItemH div 2)
  doAssert sel == 12, "the selected row is the last in view: " & $sel

block gridRowsPartWay:
  touchScreen(true)
  view = proc () =
    discard grid(cols, 60, proc (r, c: int): string = $r & "," & $c, gsel,
                 height = 8, w = 300)
    gr = ui.lastRect
  run(2)
  # the selected row's middle, found by its color down an empty stretch of
  # the first column (the middle: a focus rectangle may dot its edges)
  let rowH = ItemH + 2
  let bodyY = gr.y + 1 + ItemH + 4
  let x = gr.x + 150
  let selC = px(x, bodyY + rowH + rowH div 2)
  proc selMid(): int =
    var a, b = -1
    for y in bodyY ..< gr.y + gr.h:
      if px(x, y) == selC:
        if a < 0: a = y
        b = y
    (a + b) div 2
  let t0 = selMid()
  doAssert abs(t0 - (bodyY + rowH + rowH div 2)) <= 1, "row 1 is selected " & $t0
  # a finger drags the rows by all but 3 pixels of a row (10 to get going,
  # then the rest) and rests before it lifts: the rows move by exactly
  # that, not by whole rows
  let drag = rowH - 3
  down(gr.x + 100, gr.y + 100)
  run(1)
  move(gr.x + 100, gr.y + 90)
  run(1)
  move(gr.x + 100, gr.y + 100 - drag)
  run(6)
  up(gr.x + 100, gr.y + 100 - drag)
  run(3)
  let t1 = selMid()
  doAssert t0 - t1 == drag, "the rows moved by the finger's pixels: " & $(t0 - t1) & " of " & $drag
  doAssert gsel == 1, "a drag is not a tap"
  # the row at the top is cut by the edge, not snapped: what is left of row
  # 0 (3 pixels) and its grid line show above row 1
  doAssert px(x, bodyY) != selC and px(x, bodyY + rowH - drag - 1) != selC
  touchScreen(false)

echo "scroll tests passed"
