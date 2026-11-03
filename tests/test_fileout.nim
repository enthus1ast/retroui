## Files dragged out of the window to other programs, headless: what the
## drivers hand over (`text/uri-list` for X11 and Wayland, CF_HDROP for
## Windows), and, with a fake driver, when the system's drag begins
## (`fileDragSource`, `dragFilesOut`, a drag of the toolkit's with files that
## leaves the window), that the press clicks nothing then, and a drag that
## comes back into the window going on as the toolkit's.

import std/[unicode, strutils]
import retro
import retro/uirelays/[input, services]
import harness

fakeDriver()
startApp("fileout", W, H)

# ---- what the drivers hand over ----

proc utf16Paths(b: string): seq[string] =
  ## (CF_HDROP back to paths, as DragQueryFileW reads it)
  doAssert b.len >= 22
  proc u32(at: int): int =
    for i in 0 .. 3: result = result or (ord(b[at + i]) shl (8 * i))
  doAssert u32(0) == 20, "the names start after the header"
  doAssert u32(16) == 1, "the names are UTF-16"
  var i = u32(0)
  var cur: seq[uint32]
  while i + 1 < b.len:
    let u = uint32(ord(b[i])) or (uint32(ord(b[i + 1])) shl 8)
    i += 2
    if u == 0:
      if cur.len == 0: break                  # (the list's closing 0)
      var s = ""
      var k = 0
      while k < cur.len:
        var c = cur[k]
        if c >= 0xD800 and c < 0xDC00 and k + 1 < cur.len:
          c = 0x10000 + ((c - 0xD800) shl 10) + (cur[k + 1] - 0xDC00)
          inc k
        s.add $Rune(c)
        inc k
      result.add s
      cur.setLen(0)
    else:
      cur.add u
  doAssert i == b.len, "nothing after the list's closing 0"

block uriList:
  when not defined(windows):
    let paths = @["/home/sultan/My Invoices/march.pdf", "/tmp/سلطان.txt",
                  "/tmp/100% #1?.txt", "/tmp/a:b~c_d-e.f"]
    let l = uriListOfFiles(paths)
    doAssert l == "file:///home/sultan/My%20Invoices/march.pdf\r\n" &
                  "file:///tmp/%D8%B3%D9%84%D8%B7%D8%A7%D9%86.txt\r\n" &
                  "file:///tmp/100%25%20%231%3F.txt\r\n" &
                  "file:///tmp/a%3Ab~c_d-e.f\r\n", l
    doAssert filesOfUriList(l) == paths, "the other way: the same paths"
    doAssert uriListOfFiles(newSeq[string]()) == ""

block hdrop:
  let paths = @["C:\\Users\\sultan\\Invoice March.pdf", "D:\\صور\\شاطئ.jpg",
                "C:\\tmp\\smile 😀.txt"]
  let b = hdropOfFiles(paths)
  doAssert utf16Paths(b) == paths, $utf16Paths(b)
  # (the emoji is a surrogate pair: D83D DE00)
  doAssert "\x3D\xD8\x00\xDE" in b
  # header, then just the closing 0 for no files
  doAssert hdropOfFiles(newSeq[string]()) ==
    "\x14\0\0\0" & "\0\0\0\0" & "\0\0\0\0" & "\0\0\0\0" & "\x01\0\0\0" & "\0\0"

# ---- a fake driver's drag ----

var
  calls: seq[tuple[paths: seq[string]; move, back: bool]]
  answers: seq[DragOutResult]   # what the next drags end with (then drCopied)

proc fakeDragOut(paths: seq[string]; move, backInside: bool): DragOutResult =
  ## As the drivers do: the drag runs until the button is let go -- its
  ## release reported after -- or (drBack) the pointer is over the window.
  calls.add (paths, move, backInside)
  result = if answers.len > 0: answers[0] else: drCopied
  if answers.len > 0: answers.delete(0)
  case result
  of drBack: queue.add Event(kind: MouseMoveEvent, x: 100, y: 100)
  of drNone: discard
  else: queue.add Event(kind: MouseUpEvent, x: 900, y: 300, button: LeftButton)

var
  mode = "source"
  clicked, taken, made = 0
  give = @["/tmp/Invoice March.pdf", "/tmp/photo.png"]
  wantMove = false
  btn, src: Rect
  withFiles = true
  dropped: seq[string]
  appTakes = false              # the app drags the files out itself
  appResult = false
const target = rect(300, 200, 100, 60)

view = proc () =
  case mode
  of "source":
    if button("Invoice March.pdf"): inc clicked
    btn = ui.lastRect
    if fileDragSource(btn, proc (): seq[string] = (inc made; give), move = wantMove):
      inc taken
  of "toolkit":
    src = place(120, 40)
    let h = interact(idOf("message"), src)
    if h.clicked: inc clicked
    if h.down and ui.mouseMoved and not dragging() and abs(ui.mx - src.x - 10) > 5:
      startDrag("mail", ["7"], label = "A message",
                files = if withFiles: (proc (): seq[string] = (inc made; give)) else: nil)
    if appTakes and dragging() and ui.mx >= W - 10:
      appResult = dragFilesOut(give)
    if dropTarget(target, "mail") == dsDropped: dropped = ui.drag.items
  else: discard

proc reset(m: string) =
  mode = m
  calls.setLen(0)
  answers.setLen(0)
  clicked = 0
  taken = 0
  made = 0
  dropped.setLen(0)
  run(2)

block unavailable:
  # no driver for it: the press is an ordinary press, nothing is made
  doAssert canDragFilesOut()
  fileDragRelays.dragOut = nil
  doAssert not canDragFilesOut()
  reset "source"
  let (x, y) = (btn.x + 10, btn.y + btn.h div 2)
  down(x, y)
  run()
  move(x + 30, y)
  run()
  move(x, y)
  run()
  up(x, y)
  run(2)
  doAssert made == 0 and clicked == 1
  doAssert startFileDragOut(["/tmp/a"]) == drNone
  doAssert not dragFilesOut(@["/tmp/a"])
  doAssert lastDragOut() == drNone
  fileDragRelays.dragOut = fakeDragOut

block fromAButton:
  reset "source"
  let (x, y) = (btn.x + 10, btn.y + btn.h div 2)
  down(x, y)
  run()
  move(x + 2, y + 1)                   # (a few pixels: not yet)
  run()
  doAssert calls.len == 0 and made == 0
  move(x + 12, y)
  run(3)
  doAssert made == 1, "the files are made when the drag begins, once"
  doAssert calls.len == 1 and calls[0].paths == give
  doAssert not calls[0].move and not calls[0].back
  doAssert taken == 1 and lastDragOut() == drCopied
  doAssert clicked == 0, "the press that began a drag clicks nothing"
  doAssert not ui.mouseDown, "the driver's release came"
  # an ordinary click afterwards
  click(btn)
  doAssert clicked == 1 and calls.len == 1

block cancelledAndMoved:
  reset "source"
  answers = @[drCancelled]
  let (x, y) = (btn.x + 10, btn.y + btn.h div 2)
  down(x, y)
  run()
  move(x + 20, y)
  run(3)
  doAssert calls.len == 1 and taken == 0 and lastDragOut() == drCancelled
  doAssert clicked == 0
  wantMove = true
  answers = @[drMoved]
  down(x, y)
  run()
  move(x + 20, y)
  run(3)
  doAssert calls.len == 2 and calls[1].move and taken == 1 and lastDragOut() == drMoved
  wantMove = false

block nothingToGive:
  # no files after all: no drag, the press goes on as a press
  reset "source"
  give = @[]
  let (x, y) = (btn.x + 10, btn.y + btn.h div 2)
  down(x, y)
  run()
  move(x + 8, y)
  run()
  move(x + 9, y)
  run()
  up(x + 9, y)
  run(2)
  doAssert made == 1 and calls.len == 0 and clicked == 1
  give = @["/tmp/Invoice March.pdf", "/tmp/photo.png"]

block pressedElsewhere:
  # a press outside that moves over the button begins nothing
  reset "source"
  down(btn.x + btn.w + 40, btn.y + 2)
  run()
  move(btn.x + 10, btn.y + 5)
  run()
  move(btn.x + 30, btn.y + 5)
  run()
  up(btn.x + 30, btn.y + 5)
  run(2)
  doAssert calls.len == 0 and made == 0

block toolkitDragBack:
  # the toolkit's drag leaves the window: the system's drag of its files;
  # back over the window it is the toolkit's again, dropped on a target
  reset "toolkit"
  answers = @[drBack]
  down(src.x + 10, src.y + 10)
  run()
  move(src.x + 30, src.y + 10)
  run()
  doAssert dragging("mail") and calls.len == 0
  move(W div 2, H div 2)                # (inside: still the toolkit's)
  run()
  doAssert calls.len == 0 and made == 0
  move(-20, 100)                        # out of the window
  run(2)
  doAssert calls.len == 1 and calls[0].back and calls[0].paths == give and made == 1
  doAssert lastDragOut() == drBack
  doAssert dragging("mail"), "back over the window: the toolkit's drag goes on"
  move(target.x + 10, target.y + 10)
  run()
  up(target.x + 10, target.y + 10)
  run(2)
  doAssert dropped == @["7"], $dropped
  doAssert clicked == 0 and not dragging()

block toolkitDragOutBackOut:
  # out, back, out again and taken there: the files made once
  reset "toolkit"
  answers = @[drBack, drCopied]
  down(src.x + 10, src.y + 10)
  run()
  move(src.x + 30, src.y + 10)
  run()
  move(W + 15, 100)
  run(2)
  doAssert calls.len == 1 and dragging("mail")
  move(200, 120)                        # (over the window: the toolkit's)
  run()
  doAssert calls.len == 1 and dragging("mail")
  move(W + 40, 120)
  run(3)
  doAssert calls.len == 2 and made == 1
  doAssert lastDragOut() == drCopied and not dragging()
  doAssert dropped.len == 0 and clicked == 0

block toolkitDragCancelledOutside:
  reset "toolkit"
  answers = @[drCancelled]
  down(src.x + 10, src.y + 10)
  run()
  move(src.x + 30, src.y + 10)
  run()
  move(100, H + 20)
  run(3)
  doAssert calls.len == 1 and lastDragOut() == drCancelled
  doAssert not dragging() and dropped.len == 0

block toolkitDragWithoutFiles:
  # no files given: the drag stays in the window, outside or not
  reset "toolkit"
  withFiles = false
  down(src.x + 10, src.y + 10)
  run()
  move(src.x + 30, src.y + 10)
  run()
  move(-30, -30)
  run()
  doAssert calls.len == 0 and dragging("mail")
  up(-30, -30)
  run(2)
  doAssert not dragging() and dropped.len == 0
  withFiles = true

block toolkitDragDriverCannot:
  # the driver could not (drNone): not asked again in that drag
  reset "toolkit"
  answers = @[drNone]
  down(src.x + 10, src.y + 10)
  run()
  move(src.x + 30, src.y + 10)
  run()
  move(-20, 50)
  run()
  move(-40, 60)
  run()
  doAssert calls.len == 1 and dragging("mail")
  up(-40, 60)
  run(2)
  doAssert not dragging()

block appDragsFilesOut:
  # the app hands files to the system's drag itself (its drag reached the
  # window's edge): the toolkit's drag is over
  reset "toolkit"
  withFiles = false
  appTakes = true
  down(src.x + 10, src.y + 10)
  run()
  move(src.x + 30, src.y + 10)
  run()
  move(W - 5, 100)
  run(3)
  doAssert calls.len == 1 and not calls[0].back and appResult
  doAssert not dragging() and lastDragOut() == drCopied
  appTakes = false
  withFiles = true
  # the button up: nothing to drag
  doAssert not ui.mouseDown and not dragFilesOut(give) and calls.len == 1

echo "test_fileout: ok"
