## Keys typed while a frame works (a picture decoded, a page read: the work
## calls `busyTick`) arrive in the frames after it, until the busy box is
## up -- the text comes out as if no work had been done; Esc still asks the
## work to stop. Headless.

import retroui/uirelays/input
import retroui
import retroui/busy
import harness

var
  name = ""
  working = false
  box: Rect

view = proc () =
  edit name
  box = ui.lastRect
  if working:
    # (work of a few ticks, well under the box's quarter of a second)
    working = false
    for i in 0 ..< 4:
      ticks += 30
      busyTick()

fakeDriver()
startApp("busy keys", W, H)
run(2)
click(box)
doAssert ui.focus != 0, "the text box has the keyboard"

proc typed(work: bool): string =
  ## What the text box holds after some typing, with or without work in the
  ## frame where it is typed.
  name = ""
  run(1)
  typeText("abc")
  key(KeyLeft)
  typeText("X")
  key(KeyEnd)
  typeText("yz")
  working = work
  run(10)
  name

let plain = typed(false)
doAssert plain.len == 6, "typed without work: " & plain
let duringWork = typed(true)
doAssert duringWork == plain, "typed during the work: " & duringWork & " (without it: " & plain & ")"

# Esc during the work: the work is asked to stop, the key is not typed
busyCancelAsked = false
queue.add Event(kind: KeyDownEvent, key: KeyNone)   # (the frame's own input: the work reads the rest)
key(KeyEsc)
working = true
run(1)
doAssert busyCancelAsked, "Esc asks the work to stop"
busyCancelAsked = false
run(4)
doAssert name == plain

echo "busy keys tests passed"
