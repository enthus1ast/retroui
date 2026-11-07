## The window's pixels in shared memory (X11, MIT-SHM), on a real X server:
## the frame is drawn straight into the memory the server reads, only the
## parts that changed are put, and what the window shows is what was drawn
## -- the same as without shared memory ($RETRO_SURFACE=0). Needs an X
## server ($DISPLAY, e.g. `Xvfb :95 &`) and xwd; skipped without them.

import std/[os, osproc, strutils]
import retroui
import retroui/uirelays/screen

if getEnv("DISPLAY").len == 0 or findExe("xwd").len == 0:
  echo "test_shm: skipped (no DISPLAY or xwd)"
  quit 0

proc windowPixel(title: string; x, y: int): uint32 =
  ## A pixel of the window titled `title`, as the X server has it.
  let dump = getTempDir() / "retro-shm-" & $getCurrentProcessId() & ".xwd"
  if execCmd("xwd -silent -name " & quoteShell(title) & " -out " & quoteShell(dump)) != 0:
    return 0xFFFFFFFF'u32
  let d = readFile(dump)
  removeFile(dump)
  proc be32(at: int): int =
    (ord(d[at]) shl 24) or (ord(d[at + 1]) shl 16) or (ord(d[at + 2]) shl 8) or ord(d[at + 3])
  let headerSize = be32(0)
  let bytesPerLine = be32(48)
  let ncolors = be32(76)
  let at = headerSize + ncolors * 12 + y * bytesPerLine + x * 4
  # (32 bits a pixel, least significant byte first on this machine's server)
  uint32(ord(d[at])) or (uint32(ord(d[at + 1])) shl 8) or (uint32(ord(d[at + 2])) shl 16)

var
  frames = 0
  color = color(200, 40, 40)
  lent = false
  sawRed, sawBlue: uint32

app "SHM test", 200, 120:
  inc frames
  let r = canvas(dp(40), dp(30))
  fill(r, color)
  case frames
  of 6:
    lent = surfaceRelays.lockSurface != nil
    sawRed = windowPixel("SHM test", r.x * zoomLevel() + 5, r.y * zoomLevel() + 5)
    color = color(30, 60, 220)
  of 12:
    sawBlue = windowPixel("SHM test", r.x * zoomLevel() + 5, r.y * zoomLevel() + 5)
    quitApp()
  else: discard
  wakeIn(40)

doAssert lent, "the X11 driver lends the window's pixels"
doAssert sawRed == 0xC82828'u32, "the window shows the frame drawn: " & toHex(sawRed)
doAssert sawBlue == 0x1E3CDC'u32, "and the part that changed after: " & toHex(sawBlue)
echo "test_shm: ok", (if getEnv("RETRO_SURFACE") == "0": " (without shared memory)" else: "")
