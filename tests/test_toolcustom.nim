## Tests of Customize Toolbar (`retro/toolcustom`) and of a panel brought to
## a part of its content (`revealInPanel`) -- headless, on the fake driver.
##
##   nim c -r tests/test_toolcustom.nim

import retro
import retro/uirelays/input
import harness

fakeDriver()
startApp("toolcustom", W, H)
smoothScrolling = false

let choices = [ToolChoice(key: "new", label: "New", glyph: pxNew),
               ToolChoice(key: "open", label: "Open", glyph: pxOpen),
               ToolChoice(key: "save", label: "Save", glyph: pxSave),
               ToolChoice(key: "print", label: "Print", glyph: pxPrint)]
let defaults = ["new", "open", "-", "save"]

block keys:
  doAssert toolKeys("", defaults, choices) == @defaults, "no setting: the defaults"
  doAssert toolKeys("save, gone ,-,new,save", defaults, choices) == @["save", "-", "new"],
    "a setting: keys the app no longer has, and twice the same, left out"
  doAssert toolKeysText(["new", "-", "print"]) == "new,-,print"

block dialog:
  var open = true
  var keys = @defaults
  var look = blTextBelow
  var changed = false
  view = proc () =
    if customizeToolbar(open, keys, choices, defaults, look): changed = true
  run(3)
  doAssert open and not changed and keys == @defaults, "drawn, nothing changed by itself"
  key(KeyEsc)
  run(2)
  doAssert toolKeys("new,-,-,open", defaults, choices) == @["new", "-", "-", "open"], "separators repeat"

block reveal:
  # a panel of 40 rows, 20 px each; row 30 brought to the top
  var want = -1
  var rowY: array[40, int]
  view = proc () =
    panel(200):
      for i in 0 ..< 40:
        let r = place(available(), 20, fill = true)
        rowY[i] = r.y
        if i == want: revealInPanel(r, glide = false)
  run(2)
  let top0 = rowY[0]
  want = 30
  run(3)
  want = -1
  run(2)
  doAssert abs(rowY[30] - top0) <= 2, "row 30 at the panel's top: " & $rowY[30] & " vs " & $top0
  # the last rows cannot come to the top: as near as it can (the bottom)
  want = 39
  run(3)
  want = -1
  run(2)
  doAssert rowY[39] + 20 <= top0 + 200 and rowY[39] > top0 + 100, "the last row: as far as it goes"

echo "toolcustom: all passed"
