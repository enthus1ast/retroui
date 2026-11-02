## Tests of the whiteboard example (examples/retroboard) as a program, run
## headless: its docked panels (as Retro Photo's), Zen and View mode and
## the button that leaves them.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, json]
import retro/uirelays/input
import harness

const boardUnderTest = true
include ../examples/retroboard

# a home of its own: the settings and the autosave go there
let home = getTempDir() / "retro-board-apptest"
removeDir(home)
createDir(home)
putEnv("HOME", home)
putEnv("XDG_CONFIG_HOME", home / ".config")
putEnv("XDG_DATA_HOME", home / ".local/share")
setCurrentDir(home)

fakeDriver()
startApp(AppName, W, H)
loadStart()
restoreDock()
applyDark()
harness.view = boardFrame
run(2)

proc tap(r: Rect) =
  let x = r.x + r.w div 2
  let y = r.y + r.h div 2
  down(x, y)
  up(x, y)
  run(2)

proc dragThrough(pts: openArray[P]) =
  ## (a press, moves and a let-go, a frame each)
  ui.mods = {}                          # (no Alt left down from the keys before)
  down(int(pts[0].x), int(pts[0].y))
  run(1)
  for i in 1 .. pts.high:
    move(int(pts[i].x), int(pts[i].y))
    run(1)
  up(int(pts[^1].x), int(pts[^1].y))
  run(2)

proc leaveRect(): Rect =
  rect(view.x + view.w - dp(96) - dp(8), view.y + dp(8), dp(96), (if fingers(): dp(40) else: dp(28)))

block panelsDocked:
  # the panels down the right of the area, in three groups of tabs
  let a = mdiAreaRect("board")
  doAssert a.w == W and a.h > H div 2
  doAssert dock.columns.len == 1 and dock.columns[0].groups.len == 3
  doAssert dock.width > 0 and view.w == a.w - dock.width
  for k in ["color", "text", "arrange"]: doAssert dock.panelShown(k), k
  for k in ["stroke", "fill", "arrow", "shape", "board", "info"]: doAssert dock.hasPanel(k) and not dock.panelShown(k), k
  # Tab hides them: the canvas takes the room
  key(KeyTab)
  run(2)
  doAssert panelsHidden and view.w == a.w
  key(KeyTab)
  run(2)
  doAssert not panelsHidden and view.w == a.w - dock.width

block panelsTakeTheirClicks:
  # a stroke drawn over the panels does not reach the canvas
  setTool(tDraw)
  let n = bd.page.shapes.len
  let x = W - dock.width div 2
  down(x, H div 2)
  move(x + 5, H div 2 + 20)
  move(x + 10, H div 2 + 40)
  up(x + 10, H div 2 + 40)
  run(3)
  doAssert bd.page.shapes.len == n
  # ... over the canvas it does
  down(60, 150)
  move(80, 170)
  move(100, 190)
  up(100, 190)
  run(3)
  doAssert bd.page.shapes.len == n + 1
  setTool(tSelect)

block panelsKept:
  # closed, saved, read back: as left
  dock.closePanel("info")
  saveSettingsNow()
  defaultDock(false)
  doAssert dock.hasPanel("info")
  restoreDock()
  doAssert not dock.hasPanel("info") and dock.hasPanel("board")
  # Reset Panels: as they come
  defaultDock(isCompact())
  doAssert dock.hasPanel("info")
  saveSettingsNow()

block phoneStrip:
  # on a phone: a strip of icons (and back, on a wider screen)
  dockCompact = false
  for c in dock.columns: c.iconic = false
  let wide = dock.width
  dockCompact = true
  for c in dock.columns: c.iconic = true
  doAssert dock.width < wide
  dockCompact = false
  for c in dock.columns: c.iconic = false
  run(2)

block leaveZenAndView:
  # the button at the top right takes the click, not the canvas under it
  zenMode = true
  run(2)
  doAssert view.w == mdiAreaRect("board").w        # (no panels in Zen mode)
  setTool(tDraw)
  let n = bd.page.shapes.len
  tap(leaveRect())
  doAssert not zenMode
  doAssert bd.page.shapes.len == n
  setTool(tSelect)
  viewMode = true
  run(2)
  tap(leaveRect())
  doAssert not viewMode
  # Alt+Z and Alt+R still go in and out
  key(KeyZ, {AltPressed})
  run(2)
  doAssert zenMode
  key(KeyZ, {AltPressed})
  run(2)
  doAssert not zenMode

block linesConnectShapes:
  # a line drawn from a shape to another: a connector held by both (an
  # arrow with no heads), that follows them
  run(2)
  let ka = bd.addShape(bd.geoShape(gkRectangle, -150, -40, 80, 80))
  let kb = bd.addShape(bd.geoShape(gkEllipse, 60, -40, 80, 80))
  sel = @[]
  bd.page.zoom = 1
  bd.page.camX = -view.w.float / 2
  bd.page.camY = -view.h.float / 2 + 100
  run(2)
  let pa = scr(-110, 0)
  doAssert view.contains(point(int(pa.x), int(pa.y))) and view.contains(point(int(scr(100, 0).x), int(scr(100, 0).y)))
  let pb = scr(100, 0)
  setTool(tLine)
  dragThrough([pa, (pa.x + 20, pa.y + 4), (pb.x - 20, pb.y), pb])
  let c = bd.page.shapes[^1]
  doAssert c.kind == skArrow and c.head0 == ahNone and c.head1 == ahNone, $c.kind
  doAssert c.t0.bound == ka and c.t1.bound == kb
  let (e0, _) = bd.arrowEnds(c)
  bd.update(ka, proc (s: var Shape) = s.y += 200)
  let (f0, _) = bd.arrowEnds(bd.find(c.id)[])
  doAssert f0.y > e0.y + 100                       # (its end went with the shape)
  # ... from the empty canvas onto a shape: held at that end
  setTool(tLine)
  let pe = scr(-60, 150)
  dragThrough([pe, (pe.x + 30, pe.y - 20), (pb.x - 10, pb.y), pb])
  let d = bd.page.shapes[^1]
  doAssert d.kind == skArrow and d.t0.bound == 0 and d.t1.bound == kb
  # ... and on the empty canvas: a line, as before
  setTool(tLine)
  let q = scr(-40, 70)
  dragThrough([q, (q.x + 40, q.y + 10), (q.x + 80, q.y + 20)])
  doAssert bd.page.shapes[^1].kind == skLine
  setTool(tSelect)

block zoomOnSharpScreens:
  # 100%: a page unit to each pixel of the device (half a logical pixel on
  # a tablet), as the zoom box and the menus say
  doAssert unitScale() == 1.0
  resetZoom()
  doAssert abs(bd.page.zoom - 1.0) < 1e-9 and abs(zoom() - 1.0) < 1e-9
  pxScale = 2
  doAssert unitScale() == 0.5 and abs(zoom() - 0.5) < 1e-9
  zoomSteps(true)
  doAssert abs(bd.page.zoom - 2.0) < 1e-9 and abs(zoom() - 1.0) < 1e-9
  resetZoom()
  doAssert abs(bd.page.zoom - 1.0) < 1e-9
  pxScale = 3
  doAssert unitScale() == 0.5                        # (not less)
  pxScale = 1

echo "ok board app"
