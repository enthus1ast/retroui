## Fractional scaling, headless: at 125 %, 150 %, 175 %, 250 %... a
## control and its text come out the size the scale asks for (within a
## pixel of the screen), lines stay on whole pixels, and a change of the
## screen's scale (a window moved to another monitor) is followed at once.

import retroui
import retroui/uirelays/[input, screen]
import harness

fakeDriver()

var scaleNow = 100
windowRelays.getWindowLayout = proc (): ScreenLayout =
  ScreenLayout(width: W, height: H, scaleX: 1, scaleY: 1, uiScale: scaleNow)

var
  btn: Rect
  lbl: Rect
  textW = 0

view = proc () =
  if button("Scaled"): discard
  btn = ui.lastRect
  label "The quick brown fox"
  lbl = ui.lastRect
  textW = textWidth("The quick brown fox")

startApp("scale", 600, 400)

proc measure(s: int): tuple[h, w, tw, zoom: int] =
  scaleNow = s
  var e = Event(kind: WindowMetricsEvent, x: W, y: H, scaleX: 1, scaleY: 1, uiScale: s)
  queue.add e
  run(3)
  let z = zoomLevel()
  (btn.h * z, btn.w * z, textW * z, z)

let base = measure(100)
doAssert base.zoom == 1
for s in [125, 150, 175, 200, 250, 300]:
  let m = measure(s)
  let want = base.h * s div 100
  doAssert abs(m.h - want) <= m.zoom + 1,
    "at " & $s & "%: a button " & $m.h & " pixels high, " & $want & " wanted"
  let wantText = base.tw * s div 100
  doAssert abs(m.tw - wantText) <= max(3, wantText div 20),
    "at " & $s & "%: text " & $m.tw & " pixels wide, " & $wantText & " wanted"
  # lines on whole pixels: the screen's pixels per logical pixel are whole
  doAssert m.zoom == max(1, (s + 49) div 100)
  echo "  ", s, "%: button ", m.h, " px high (", want, "), text ", m.tw, " px (", wantText,
       "), lines ", m.zoom, " px"
echo "test_scale: ok"
