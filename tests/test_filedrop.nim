## Files dropped on the window from the system's file manager, headless:
## the driver's event, this frame's files and where they fell, a drop
## target (`fileDropTarget`) and what covers it, and the `text/uri-list`
## an X11 or Wayland file manager hands over.

import retro
import retro/uirelays/[input, services]
import harness

fakeDriver()
startApp("drop", W, H)

block uriList:
  # one URI a line, comments and other URIs left out, %XX decoded
  let l = "file:///home/sultan/My%20Invoices/march.pdf\r\n" &
          "# a comment\r\n" &
          "file://localhost/tmp/photo.png\r\n" &
          "https://www.foxoman.net/\r\n" &
          "file:///tmp/%D8%B3%D9%84%D8%B7%D8%A7%D9%86.txt\r\n" &
          "file:///tmp/100%25\n"
  when defined(windows):
    discard l
  else:
    doAssert filesOfUriList(l) == @["/home/sultan/My Invoices/march.pdf",
                                    "/tmp/photo.png", "/tmp/سلطان.txt", "/tmp/100%"],
      $filesOfUriList(l)
    doAssert filesOfUriList("").len == 0
    doAssert filesOfUriList("file:").len == 0

proc dropAt(x, y: int; files: seq[string]) =
  queue.add Event(kind: FileDropEvent, x: x, y: y, files: files)

var
  target = rect(40, 60, 200, 120)
  got, all, gotWindow, inDialog: seq[string]   # what each saw (the last drop)
  at: Point
  framesWithDrop = 0
  dialogOpen = false
view = proc () =
  label "Drop files here"
  let t = fileDropTarget(target)
  let w = fileDropTarget(rect(0, 0, W, H))
  if droppedFiles().len > 0:
    inc framesWithDrop
    all = droppedFiles()
    at = dropPoint()
    got = t
    gotWindow = w
  if beginDialog(dialogOpen, "Compose", 300):
    label "Attachments"
    let d = fileDropTarget(rect(0, 0, W, H))
    if droppedFiles().len > 0: inDialog = d
    endDialog()
run(2)

block dropped:
  dropAt(100, 120, @["/tmp/a.pdf", "/tmp/b.png"])
  run(3)
  doAssert all == @["/tmp/a.pdf", "/tmp/b.png"], $all
  doAssert at == point(100, 120)
  doAssert got == all, "inside the target"
  doAssert framesWithDrop == 1, "only the frame it was dropped in"

block outside:
  dropAt(400, 400, @["/tmp/c.txt"])
  run()
  doAssert all == @["/tmp/c.txt"] and got.len == 0, "outside the target"
  doAssert gotWindow == all

block underADialog:
  # a dialog over the target takes the drop; what it covers does not
  dialogOpen = true
  run(2)
  dropAt(W div 2, H div 2, @["/tmp/d.docx"])
  run()
  doAssert inDialog == @["/tmp/d.docx"], $inDialog
  doAssert all == @["/tmp/d.docx"] and gotWindow.len == 0,
    "the window under the dialog does not take it"
  dialogOpen = false
  run(2)

echo "test_filedrop: ok"
