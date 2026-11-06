## X11's keys, wheel and buttons as a real X server sends them, typed by
## xdotool into a window of the driver's own: Ctrl+C with a Cyrillic layout
## (alone, and with a Latin one), Ctrl+1 on AZERTY, the keypad, the
## sideways wheel (buttons 6 and 7), the side buttons, clicks counted for
## each button, the pointer leaving the window, the title in UTF-8, the
## clipboard with an old program's Latin-1. Needs an X server ($DISPLAY,
## e.g. `Xvfb :95 &`), xdotool and setxkbmap; skipped without them.

import std/[os, osproc, strutils]
import retroui/uirelays

when defined(linux) and not defined(android):
  if getEnv("DISPLAY").len == 0 or findExe("xdotool").len == 0 or
     findExe("setxkbmap").len == 0:
    echo "test_x11input: skipped (no DISPLAY, xdotool or setxkbmap)"
    quit 0
  delEnv("GDK_SCALE")
  delEnv("QT_SCALE_FACTOR")

  proc sh(cmd: string): string =
    let (o, code) = execCmdEx(cmd)
    doAssert code == 0, cmd & ": " & o
    o.strip

  let layoutBefore = sh("setxkbmap -query").splitLines
  discard createWindow(300, 200)
  setWindowTitle("x11 input — ä")
  fillRect(rect(0, 0, 300, 200), color(0, 128, 128))
  refresh()

  var events: seq[Event]
  proc drain(ms = 300) =
    ## The events of the next `ms` milliseconds.
    let till = getTicks() + ms
    var e: Event
    while getTicks() < till:
      if waitEvent(e, 20): events.add e

  drain(500)
  let win = sh("xdotool search --name 'x11 input'").splitLines[0]
  discard sh("xdotool windowmove " & win & " 0 0 windowfocus --sync " & win)
  drain()

  # (the title: _NET_WM_NAME in UTF-8, WM_NAME in Latin-1)
  let props = sh("xprop -id " & win & " _NET_WM_NAME WM_NAME")
  # (xprop writes what is not ASCII as octal)
  doAssert "_NET_WM_NAME(UTF8_STRING) = \"x11 input \\342\\200\\224 \\303\\244\"" in props, props
  doAssert "WM_NAME(STRING) = \"x11 input ? \\344\"" in props, props

  proc keysOf(xdo: string): seq[Event] =
    events.setLen 0
    discard sh("xdotool " & xdo)
    drain()
    for e in events:
      if e.kind in {KeyDownEvent, TextInputEvent}: result.add e

  proc downs(es: seq[Event]): seq[(KeyCode, set[Modifier])] =
    for e in es:
      if e.kind == KeyDownEvent and e.key != KeyNone: result.add (e.key, e.mods)

  proc typed(es: seq[Event]): string =
    for e in es:
      if e.kind == TextInputEvent:
        for c in e.text:
          if c != '\0': result.add c

  # the US layout: as always
  discard sh("setxkbmap -layout us")
  doAssert (KeyC, {CtrlPressed}) in downs(keysOf("key ctrl+c"))

  # Russian alone: Ctrl+C is still C (its place); the letters type Cyrillic
  discard sh("setxkbmap -layout ru")
  var ks = keysOf("key ctrl+Cyrillic_es")
  doAssert (KeyC, {CtrlPressed}) in downs(ks), $downs(ks)
  ks = keysOf("key Cyrillic_es")
  doAssert typed(ks) == "с", typed(ks)
  doAssert (KeyC, {}) in downs(ks), $downs(ks)
  doAssert (KeyV, {CtrlPressed}) in downs(keysOf("key ctrl+Cyrillic_em"))
  doAssert (KeyZ, {CtrlPressed}) in downs(keysOf("key ctrl+Cyrillic_ya"))

  # Russian with US second: the US group's key
  discard sh("setxkbmap -layout ru,us")
  doAssert (KeyA, {CtrlPressed}) in downs(keysOf("key ctrl+Cyrillic_ef"))
  doAssert (KeyS, {CtrlPressed}) in downs(keysOf("key ctrl+Cyrillic_yeru"))

  # Greek and Hebrew
  discard sh("setxkbmap -layout gr")
  doAssert (KeyC, {CtrlPressed}) in downs(keysOf("key ctrl+Greek_psi"))
  discard sh("setxkbmap -layout il")
  doAssert (KeyX, {CtrlPressed}) in downs(keysOf("key ctrl+hebrew_samech"))

  # AZERTY: the digits are shifted, Ctrl+1 is still 1; A is where it is
  discard sh("setxkbmap -layout fr")
  doAssert (Key1, {CtrlPressed}) in downs(keysOf("key ctrl+ampersand"))
  doAssert (KeyA, {CtrlPressed}) in downs(keysOf("key ctrl+a"))

  # the keypad, with Num Lock on and off
  discard sh("setxkbmap -layout us")
  # (xdotool turns Num Lock on for KP_7, and leaves it on: the digits last)
  ks = keysOf("key KP_Enter KP_Add KP_Subtract KP_Home KP_Delete KP_Up KP_7")
  const none: set[Modifier] = {}
  doAssert downs(ks) == @[(KeyEnter, none), (KeyPlus, none), (KeyMinus, none), (KeyHome, none),
                          (KeyDelete, none), (KeyUp, none), (Key7, none)], $downs(ks)
  doAssert typed(ks) == "+-7", typed(ks)
  doAssert (KeyPlus, {CtrlPressed}) in downs(keysOf("key ctrl+KP_Add"))

  # the wheel: up, down, left (6), right (7)
  proc pointerOf(xdo: string): seq[Event] =
    events.setLen 0
    discard sh("xdotool " & xdo)
    drain()
    for e in events:
      if e.kind in {MouseDownEvent, MouseUpEvent, MouseWheelEvent, MouseMoveEvent}:
        result.add e

  discard sh("xdotool mousemove --window " & win & " 100 100")
  drain()
  var ps = pointerOf("click 4 click 5 click 6 click 7")
  var wheels: seq[(int, int)]
  for e in ps:
    if e.kind == MouseWheelEvent: wheels.add (e.x, e.y)
    doAssert e.kind notin {MouseDownEvent, MouseUpEvent}, "a wheel is no click: " & $e.kind
  doAssert wheels == @[(0, 1), (0, -1), (-1, 0), (1, 0)], $wheels

  # the side buttons: back and forward; buttons past them: nothing
  ps = pointerOf("click 8 click 9 click 10")
  var buttons: seq[MouseButton]
  for e in ps:
    if e.kind == MouseDownEvent: buttons.add e.button
  doAssert buttons == @[BackButton, ForwardButton], $buttons

  # clicks counted for one button: left, right, left is not a triple
  ps = pointerOf("click 1 click 3 click 1")
  var counts: seq[(MouseButton, int)]
  for e in ps:
    if e.kind == MouseDownEvent: counts.add (e.button, e.clicks)
  doAssert counts == @[(LeftButton, 1), (RightButton, 1), (LeftButton, 1)], $counts
  ps = pointerOf("sleep 0.6 click --repeat 2 --delay 80 1")
  counts.setLen 0
  for e in ps:
    if e.kind == MouseDownEvent: counts.add (e.button, e.clicks)
  doAssert counts == @[(LeftButton, 1), (LeftButton, 2)], $counts

  # the pointer leaves the window: a move to OutsideWindow
  ps = pointerOf("mousemove 900 700")
  doAssert ps.len > 0 and ps[^1].kind == MouseMoveEvent and ps[^1].x == OutsideWindow,
    $ps

  # the clipboard: what an old program (STRING) is given is Latin-1
  putClipboardText("Grüße — 1")
  if findExe("xclip").len > 0:
    let latin = execCmdEx("xclip -o -selection clipboard -t STRING | od -An -tx1").output
    doAssert "fc" in latin and "3f" in latin, latin       # (ü; the dash: ?)
  doAssert getClipboardText() == "Grüße — 1"

  for line in layoutBefore:
    if line.startsWith("layout:"): discard sh("setxkbmap -layout " & line[7 .. ^1].strip)
  shutdown()
  echo "test_x11input: ok"
else:
  echo "test_x11input: skipped (not X11)"
