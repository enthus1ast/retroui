## The Windows 3.1 window frame on desktops (`setClassicFrame`), headless:
## where its parts are, what a press on each asks of the system (move, size,
## maximize, minimize), the control menu, the colors of an inactive window,
## how the bars move down under it, switching it at run time and keeping
## the choice in the settings.

import std/os
import retro
import retro/uirelays/[input, screen, services]
import harness

fakeDriver()

# ---- a system that can do without its frame ----------------------------------------------------

var
  systemFrame = true                  # the system's frame is on
  drags: seq[tuple[part: WindowPart; keyboard: bool]]
  maxed = false
  activeWin = true
  minimized = 0
  asked: tuple[w, h: int]             # the window size the app asked for
  cursorNow = curDefault

proc fakeSetSystemFrame(on: bool): bool =
  systemFrame = on
  true
proc fakeDrag(part: WindowPart; keyboard: bool): bool =
  drags.add (part, keyboard)
  # (the system took the button's release: the driver reports it)
  if not keyboard: queue.add Event(kind: MouseUpEvent, x: 1, y: 1, button: LeftButton)
  true
proc fakeSetMaximized(on: bool) =
  maxed = on
  queue.add Event(kind: WindowResizeEvent, x: W, y: H)
proc fakeMinimize(): bool =
  inc minimized
  true
frameRelays = FrameRelays(setSystemFrame: fakeSetSystemFrame, dragWindow: fakeDrag,
                          setMaximized: fakeSetMaximized,
                          maximized: proc (): bool = maxed,
                          active: proc (): bool = activeWin)
systemRelays.minimize = fakeMinimize
let harnessCreate = windowRelays.createWindow
windowRelays.createWindow = proc (l: var ScreenLayout; icon: pointer; iconLen: int) =
  asked = (l.width, l.height)
  harnessCreate(l, icon, iconLen)
windowRelays.setCursor = proc (c: CursorKind) = cursorNow = c

# Built with the system's frame (the default); RETRO_FRAME wins over that.
doAssert retroFrame == "system"
putEnv("RETRO_FRAME", "classic")
startApp("frame", 400, 300)
doAssert classicFrame() and classicFrameWanted() and canClassicFrame()
doAssert not systemFrame, "the window is made without the system's frame"
# (the frame goes round the size asked for -- its title bar as the metrics
# had it before the window, a pixel or so off what the font then makes it)
doAssert asked.w == 400 + 2 * 5 and asked.h - 300 - 2 * 5 in MenuH + 1 .. MenuH + 2,
  "the frame goes round the size asked for: " & $asked

var closes = 0
view = proc () =
  menubar:
    menu "&File":
      discard menuItem("&Open")
  label "Content"
  statusbar("Ready")
  if closeRequested():
    inc closes
    cancelClose()
run(2)

const Navy = 0x000080'u32
const White = 0xFFFFFF'u32
const Black = 0x000000'u32
const Gray = 0xC0C0C0'u32
let ch = MenuH            # the title bar's height (and its buttons' size)
let c = 5 + ch            # where the corners' parts end along the border

block layout:
  # the border all round, the title bar (and its line) inside it: the bars
  # and the content start below, as under a phone's title bar
  doAssert ui.frameBorder == 5 and ui.captionH == ch + 1
  doAssert ui.safe == (5, 5, 5, 5), $ui.safe
  doAssert ui.barY == 5 + ch + 1 + MenuH + 1, "the menu bar is under the title bar"
  doAssert ui.bottom < H - 5, "the status bar is over the bottom border"
  let f = frameLayout()
  doAssert f.caption == rect(5, 5, W - 10, ch), $f.caption
  doAssert f.controlBox == rect(5, 5, ch, ch)
  doAssert f.maximize == rect(W - 5 - ch, 5, ch, ch)
  doAssert f.minimize == rect(W - 5 - 2 * ch, 5, ch, ch)
  doAssert f.corner == c

block drawn:
  doAssert px(0, 200) == Black and px(W - 1, 200) == Black, "the outer line"
  doAssert px(2, 200) == Gray and px(W - 3, 200) == Gray, "the gray band"
  doAssert px(4, 200) == Black and px(W - 5, 200) == Black, "the inner line"
  doAssert px(320, H - 3) == Gray, "the band at the bottom"
  # the dark lines across the band, where the corners' parts end
  doAssert px(c, 2) == Black and px(2, c) == Black, "top left corner lines"
  doAssert px(W - c, 2) == Black and px(W - 3, c) == Black, "top right"
  doAssert px(2, H - 1 - c) == Black and px(c, H - 3) == Black, "bottom left"
  doAssert px(c - 1, 2) == Gray and px(c + 1, 2) == Gray
  # the active title bar, the line under it, the menu bar under that
  doAssert px(40, 10) == Navy and px(W - 60, 10) == Navy, "the title bar"
  doAssert px(40, 5 + ch) == Black, "the line under the title bar"
  doAssert px(100, 5 + ch + 4) == White, "the menu bar"
  doAssert px(8, 8) == Gray, "the control-menu box"

block parts:
  for (x, y, want) in [(0, 0, fpTopLeft), (2, c - 1, fpTopLeft), (2, c, fpLeft),
                       (2, 240, fpLeft), (W - 1, 240, fpRight), (320, 1, fpTop),
                       (320, H - 1, fpBottom), (W - 1, H - 1, fpBottomRight),
                       (c - 1, H - 2, fpBottomLeft), (W - 2, 2, fpTopRight),
                       (W - 2, H - c, fpBottomRight), (W - 2, H - c - 1, fpRight),
                       (10, 10, fpControlBox), (W - 10, 10, fpMaximize),
                       (W - 10 - ch, 10, fpMinimize), (320, 10, fpCaption),
                       (320, 5 + ch, fpCaption), (320, 6 + ch, fpNone),
                       (320, 240, fpNone)]:
    doAssert framePartAt(x, y) == want, $(x, y) & ": " & $framePartAt(x, y)
  doAssert systemPart(fpCaption) == wpCaption and systemPart(fpTopLeft) == wpTopLeft
  doAssert systemPart(fpMinimize) == wpClient
  # right to left the window is drawn mirrored: its left edge is on the right
  ui.rtl = true
  doAssert systemPart(fpLeft) == wpRight and systemPart(fpBottomLeft) == wpBottomRight
  ui.rtl = false

block moveAndSize:
  # the title bar moves the window, the border and its corners size it:
  # the system does it, from the press
  down(320, 12)
  run()
  doAssert drags == @[(wpCaption, false)], $drags
  run()
  doAssert not ui.mouseDown, "the release the system took is reported"
  for (x, y, want) in [(2, 240, wpLeft), (W - 2, H - 2, wpBottomRight),
                       (320, 1, wpTop), (W - 2, 2, wpTopRight)]:
    drags.setLen 0
    down(x, y)
    run(2)
    doAssert drags == @[(want, false)], $(x, y) & ": " & $drags
  # the sizing arrows over the border
  move(2, 240)
  run()
  doAssert cursorNow == curSizeWE, $cursorNow
  move(W - 2, H - 2)
  run()
  doAssert cursorNow == curSizeNWSE, $cursorNow
  move(320, H - 2)
  run()
  doAssert cursorNow == curSizeNS
  move(320, 200)
  run()
  doAssert cursorNow != curSizeNS

block maximize:
  # a double click on the title bar maximizes: no border then, the title bar
  # at the top of the screen, the bars right under it
  drags.setLen 0
  down(320, 12, clicks = 2)
  run()
  up(320, 12)
  run(2)
  doAssert maxed and drags.len == 0
  doAssert ui.frameBorder == 0 and ui.safe == (0, 0, 0, 0)
  doAssert ui.barY == ch + 1 + MenuH + 1
  doAssert framePartAt(0, 240) == fpNone and framePartAt(320, 10) == fpCaption
  let mx = rect(W - ch, 0, ch, ch)
  doAssert frameLayout().maximize == mx
  doAssert px(0, 200) != Black, "no border"
  # the maximize button restores
  click(mx)
  run()
  doAssert not maxed and ui.frameBorder == 5
  click(rect(W - 5 - ch, 5, ch, ch))
  run()
  doAssert maxed
  click(mx)
  run()
  doAssert not maxed

block minimize:
  click(rect(W - 5 - 2 * ch, 5, ch, ch))
  doAssert minimized == 1

block controlMenu:
  # a click on the control-menu box opens its menu; its letters choose
  click(rect(5, 5, ch, ch), dx = 8)
  doAssert ui.popup != 0, "the control menu is open"
  key(KeyX)                        # Ma&ximize
  run(2)
  doAssert maxed and ui.popup == 0
  key(KeySpace, {AltPressed})      # Alt+Space opens it too
  run()
  doAssert ui.popup != 0
  key(KeyR)                        # &Restore
  run(2)
  doAssert not maxed
  key(KeySpace, {AltPressed})
  run()
  drags.setLen 0
  key(KeyM)                        # &Move: with the arrow keys
  run(2)
  doAssert drags == @[(wpCaption, true)], $drags
  key(KeySpace, {AltPressed})
  run()
  key(KeyEsc)
  run()
  doAssert ui.popup == 0
  # a double click on the box closes the window (the app is asked first)
  down(10, 10)
  run()
  up(10, 10)
  run()
  down(10, 10, clicks = 2)
  run()
  up(10, 10)
  run(2)
  doAssert closes == 1, $closes
  doAssert ui.popup == 0

block inactive:
  # another window in front: the title bar white, its title black
  queue.add Event(kind: WindowFocusLostEvent)
  activeWin = false
  run()
  doAssert px(40, 10) == White, "an inactive title bar"
  queue.add Event(kind: WindowFocusGainedEvent)
  activeWin = true
  run()
  doAssert px(40, 10) == Navy

block menusUnderIt:
  # the menu bar's menus open under the title bar, and a click on the frame
  # while one is open only closes it
  click(rect(5 + 4, 5 + ch + 1, 30, MenuH), dx = 8)
  doAssert ui.popup != 0 and ui.menuOpen
  drags.setLen 0
  down(320, 12)
  run()
  up(320, 12)
  run()
  doAssert ui.popup == 0 and drags.len == 0

block runTime:
  # switched off: the system's frame again, nothing over the bars
  setClassicFrame(false)
  run(2)
  doAssert systemFrame and not classicFrame()
  doAssert ui.frameBorder == 0 and ui.captionH == 0 and ui.barY == MenuH + 1
  doAssert framePartAt(2, 240) == fpNone
  doAssert px(100, 5) == White, "the menu bar at the top"
  # and on again
  setClassicFrame(true)
  run(2)
  doAssert not systemFrame and classicFrame() and ui.frameBorder == 5
  doAssert px(40, 10) == Navy

block settings:
  # kept only when it is not what the app was built with; RETRO_FRAME, when
  # set, wins over what was kept (and is not kept itself)
  var s: Settings
  storeAppearance(s)
  doAssert not s.hasKey("look.frame"), "(RETRO_FRAME says)"
  delEnv("RETRO_FRAME")
  storeAppearance(s)
  doAssert s.getOrDefault("look.frame") == "classic"
  setClassicFrame(false)
  storeAppearance(s)
  doAssert not s.hasKey("look.frame"), "the default is not kept"
  s["look.frame"] = "classic"
  restoreAppearance(s)
  doAssert classicFrame()
  putEnv("RETRO_FRAME", "system")
  s["look.frame"] = "system"
  restoreAppearance(s)
  doAssert classicFrame(), "RETRO_FRAME wins over what was kept"
  delEnv("RETRO_FRAME")

block noFrameWhereItCannot:
  # a system that cannot do without its frame (Wayland, phones): asked
  # for, the 3.1 frame is not drawn
  let saved = frameRelays
  setClassicFrame(false)
  frameRelays = FrameRelays()
  doAssert not canClassicFrame()
  setClassicFrame(true)
  run()
  doAssert not classicFrame() and classicFrameWanted() and ui.frameBorder == 0
  frameRelays = saved
  setClassicFrame(true)
  run()
  doAssert classicFrame()

echo "test_frame: ok"
