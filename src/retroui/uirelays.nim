## uirelays - Native Nim UI library based on dependency injection via
## global callbacks ("relays"). Has Windows API, X11, Cocoa, UIKit (iOS),
## Android, GTK4, SDL2, SDL3, siwin and FigDraw drivers.
##
## Importing this module re-exports coords, screen and input, and
## automatically selects and initializes the native backend for the
## current platform. For finer control, import the submodules directly
## and call ``initBackend()`` yourself.
##
## The toolkit draws and reads input through it; an app built with `app`
## never calls it. Use it alone for a window of your own drawing:
##
## ```nim
## import retroui/uirelays
## discard createWindow(640, 480)
## setWindowTitle("Relays")
## var e: Event
## block running:
##   while true:
##     while pollEvent(e):
##       if e.kind == QuitEvent: break running
##     fillRect(rect(0, 0, 640, 480), color(0, 128, 128))
##     refresh()
##     sleep(16)
## shutdown()
## ```

import uirelays / [coords, screen, input, backend]
export coords, screen, input

initBackend()
