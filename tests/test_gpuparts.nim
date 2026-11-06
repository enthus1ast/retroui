## The GPU's partial frames: where little changed (a lit button, a caret, a
## letter typed, a list scrolled, a check box), only that is drawn again --
## straight onto the screen's buffer when it keeps the last frame (buffer
## age 1), through the kept frame when it holds an older one (2, 3) or when
## that is not known (0). Each such frame must be the very pixels a whole
## redraw makes. Off screen (EGL, a pbuffer); skipped where there is no
## OpenGL.

import std/os
import retroui/uirelays/[coords, input, eglload, screen]
import retroui
import harness

putEnv("RETRO_GPU", "1")                 # (llvmpipe counts: it is what there is here)

var egl: Egl
if not egl.openOffscreen(W, H):
  echo "gpu parts tests skipped: no OpenGL here"
  quit 0
eglload.current = egl

var age = 1
var swapsWithDamage = 0
gpuRelays = GpuRelays(
  startGpu: proc (): bool = true,
  stopGpu: proc () = discard,
  swapGpu: proc (): bool = true,
  gpuProc: proc (name: cstring): pointer = eglload.current.glProc(name),
  gpuIsEs: proc (): bool = true,
  gpuGeneration: proc (): int = 0,
  gpuReady: proc (): bool = true,
  gpuBufferAge: proc (): int = age,
  swapGpuDamage: proc (rects: openArray[Rect]): bool =
    doAssert rects.len > 0
    for r in rects: doAssert r.w > 0 and r.h > 0 and r.x >= 0 and r.y >= 0 and
                             r.x + r.w <= W and r.y + r.h <= H, "a part inside the window: " & $r
    inc swapsWithDamage
    true)

fakeDriver()

var
  name = "Untitled"
  on1 = true
  on2 = false
  sel = 3
  v = 30
  items: seq[string]
  boxes: array[4, Rect]
for i in 0 ..< 60: items.add "Row number " & $i

view = proc () =
  menubar:
    menu "&File": discard menuItem("E&xit")
  toolbar:
    for i, g in ["A", "B", "C", "D"]:
      discard toolButton(g, "Tool " & g)
      if i == 0: boxes[0] = ui.lastRect
      elif i == 3: boxes[1] = ui.lastRect
  statusbar("Ready")
  row([-1, -1]):
    group "Text":
      edit name
      boxes[2] = ui.lastRect
      checkbox "First", on1
      checkbox "Second", on2
      slider v, 0, 100
    group "List":
      listbox items, sel, rows = 10
      boxes[3] = ui.lastRect

proc mid(r: Rect): (int, int) = (r.x + r.w div 2, r.y + r.h div 2)

startApp("gpu parts", W, H)
setGpuMode(gmGpu)
run(3)
doAssert drawnWithGpu(), "the GPU draws"

var checks = 0
proc same(what: string) =
  ## The frame on the screen now, and the same frame drawn whole.
  var n = 0
  while ui.redraw and n < 6:            # (the frames still due shown first)
    run(1)
    inc n
  let t0 = ticks
  let part = gpuSnapshot()
  invalidate()
  run(1)
  ticks = t0
  let whole = gpuSnapshot()
  doAssert part.len == whole.len and part.len == W * H
  # (the same pixels; where the age is not known, a whole frame goes straight
  # onto the screen and a part through the kept texture, whose blending may
  # round a level apart)
  let slack = if age == 0: 1 else: 0
  var off = 0
  var first = -1
  for i in 0 ..< part.len:
    let a = part[i]
    let b = whole[i]
    if abs(int(a shr 16 and 255) - int(b shr 16 and 255)) > slack or
       abs(int(a shr 8 and 255) - int(b shr 8 and 255)) > slack or
       abs(int(a and 255) - int(b and 255)) > slack:
      inc off
      if first < 0: first = i
  doAssert off == 0, "age " & $age & ", " & what & ": " & $off & " pixels differ from a whole redraw" &
    (if first >= 0: " (first at " & $(first mod W) & "," & $(first div W) & ")" else: "")
  inc checks

for a in [1, 2, 3, 0]:
  age = a
  invalidate()
  run(2)
  # the pointer from one tool button to another, far apart (two parts)
  for k in 0 ..< 4:
    let (x, y) = mid(boxes[k mod 2])
    move(x, y)
    run(1)
    same("hover " & $k)
  # a letter typed and taken back (the caret, the text)
  let (ex, ey) = mid(boxes[2])
  down(ex, ey)
  run()
  up(ex, ey)
  run()
  typeText("x")
  run()
  same("typed")
  key(KeyBackspace)
  run()
  same("backspace")
  # a check box, the slider by the keyboard-free way (its value)
  on2 = not on2
  run()
  same("check box")
  v = (v + 17) mod 100
  run()
  same("slider")
  # the list scrolled by the wheel, then a row chosen
  let (lx, ly) = mid(boxes[3])
  move(lx, ly)
  queue.add Event(kind: MouseWheelEvent, y: -1)
  run(40)                               # (it glides: until it stops)
  same("scrolled")
  sel = (sel + 5) mod items.len
  run()
  same("row chosen")
  # the caret blinking, frames apart
  for k in 0 ..< 3:
    ticks += 600
    run(1)
    same("caret " & $k)

doAssert swapsWithDamage > 0, "the system is told what changed"
echo "gpu parts tests passed (", checks, " frames compared)"
