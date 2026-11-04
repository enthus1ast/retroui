## A real window on X11 opened, drawn and closed: the program must come
## back from `stopApp` (XCloseDisplay) alive. Needs an X server ($DISPLAY,
## e.g. `Xvfb :94 &`); skipped without one.
##
## (libXrandr, loaded to read the monitor's size, used to be unloaded
## right after: the RandR hooks it had put in the display through libXext
## then pointed at unmapped code, and every app crashed as it closed.)

import std/os
import retro
import retro/uirelays/screen

when defined(linux) and not defined(android):
  if getEnv("DISPLAY").len == 0:
    echo "test_x11close: skipped (no DISPLAY)"
    quit 0
  # (the monitor's size is what is asked when nothing else gives the scale)
  delEnv("GDK_SCALE")
  delEnv("QT_SCALE_FACTOR")
  putEnv("RETRO_GPU", "0")
  startApp("x11 close test", 240, 120)
  for _ in 0 ..< 3:
    invalidate()                        # (a frame now: no waiting for input)
    if beginFrame():
      label "Hello"
      discard button("OK")
      endFrame()
  # (a system font open as the window closes: closed with it)
  var fm: FontMetrics
  discard openFont("", 14, fm)
  stopApp()
  stopApp()                             # (a second time: nothing left to close)
  echo "test_x11close: ok"
else:
  echo "test_x11close: skipped (not X11)"
