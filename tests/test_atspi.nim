## Screen readers on Linux, end to end: the app on a real X server, AT-SPI's
## bus and registry, and a client on another thread doing what Orca does --
## the app's objects walked (roles, names), a button pressed, text put in a
## box, the focus moved and its event heard. Needs an X server ($DISPLAY),
## dbus-daemon and AT-SPI (at-spi2-core); skipped without them.

import std/[os, osproc, strutils]
import retroui
import retroui/uirelays/[dbus, atspi]

let launcher = ["/usr/libexec/at-spi-bus-launcher", "/usr/lib/at-spi2-core/at-spi-bus-launcher"]
var haveAtspi = false
for l in launcher: haveAtspi = haveAtspi or fileExists(l)
if getEnv("DISPLAY").len == 0 or findExe("dbus-daemon").len == 0 or not haveAtspi:
  echo "test_atspi: skipped (no DISPLAY, dbus-daemon or AT-SPI)"
  quit 0

# a session bus of the test's own, assistive tools on in it
let addrFile = getTempDir() / "retro-atspi-bus-" & $getCurrentProcessId()
doAssert execShellCmd("dbus-daemon --session --fork --print-pid=4 --print-address=3 3>" &
                      quoteShell(addrFile) & " 4>" & quoteShell(addrFile & ".pid") &
                      " >/dev/null 2>&1 </dev/null") == 0
putEnv("DBUS_SESSION_BUS_ADDRESS", readFile(addrFile).strip.splitLines[0])
block:
  let s = sessionBus()
  doAssert s != nil
  var w: DBusWriter
  w.str("org.a11y.Status")
  w.str("IsEnabled")
  w.sig("b")
  w.boolean(true)
  let r = s.callWait("org.a11y.Bus", "/org/a11y/bus", "org.freedesktop.DBus.Properties",
                     "Set", "ssv", w.buf, timeoutMs = 5000)
  doAssert r.kind == dkMethodReturn, "assistive tools turned on: " & r.errorName
  s.close()

const
  Root = "/org/a11y/atspi/accessible/root"
  IfAcc = "org.a11y.atspi.Accessible"

type Found = object
  roles: seq[string]
  greetPressed, textPut, focusHeard: bool
  error: string

var
  appName: Channel[string]
  report: Channel[Found]
  name = "World"
  greeted = ""
  frames = 0

proc client() {.thread.} =
  ## What a screen reader does, on the accessibility bus.
  var f: Found
  try:
    let dest = appName.recv()
    let s = sessionBus()
    let a = s.callWait("org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress")
    var ar = a.reader()
    let bus = connectBus(ar.str())
    var m: DBusWriter
    m.str("type='signal',interface='org.a11y.atspi.Event.Object',member='StateChanged'")
    discard bus.callWait("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                         "AddMatch", "s", m.buf)
    proc children(path: string): seq[string] =
      let r = bus.callWait(dest, path, IfAcc, "GetChildren", timeoutMs = 5000)
      var rd = r.reader()
      let n = int(rd.u32())
      rd.align(8)
      let stop = rd.pos + n
      while rd.pos < stop and not rd.bad:
        rd.align(8)
        discard rd.str()
        result.add rd.str()
    proc roleName(path: string): string =
      var rd = bus.callWait(dest, path, IfAcc, "GetRoleName").reader()
      rd.str()
    proc nameOf(path: string): string =
      var w: DBusWriter
      w.str(IfAcc)
      w.str("Name")
      var rd = bus.callWait(dest, path, "org.freedesktop.DBus.Properties", "Get", "ss", w.buf).reader()
      rd.variant().text
    let win = children(Root)
    doAssert win.len == 1, "the app's one window"
    var greet, entry = ""
    for p in children(win[0]):
      let r = roleName(p)
      let n = nameOf(p)
      f.roles.add r & " " & n
      if r == "push button" and n == "Greet": greet = p
      if r == "entry": entry = p
    # text into the box, then the button pressed
    var w: DBusWriter
    w.str("Sultan")
    var rd = bus.callWait(dest, entry, "org.a11y.atspi.EditableText", "SetTextContents", "s", w.buf).reader()
    f.textPut = rd.boolean()
    sleep(400)
    var w2: DBusWriter
    w2.i32(0)
    rd = bus.callWait(dest, greet, "org.a11y.atspi.Action", "DoAction", "i", w2.buf).reader()
    f.greetPressed = rd.boolean()
    sleep(400)
    # the focus moved: its event is heard
    discard bus.receive()
    discard bus.callWait(dest, entry, "org.a11y.atspi.Component", "GrabFocus")
    for _ in 0 ..< 30:
      for e in bus.receive():
        if e.kind == dkSignal and e.member == "StateChanged" and e.path == entry:
          var er = e.reader()
          if er.str() == "focused" and er.i32() == 1: f.focusHeard = true
      if f.focusHeard: break
      sleep(100)
  except CatchableError as e:
    f.error = e.msg
  report.send f

appName.open()
report.open()
var th: Thread[void]
createThread(th, client)
var found: Found
var got = false

app "Hello", 320, 120:
  inc frames
  row([60, -1]):
    label "&Name:"
    edit name
  if button("&Greet"): greeted = "Hello, " & name & "!"
  label greeted
  if frames == 10:
    let n = atspiBusName()
    doAssert n.len > 0, "the app registered with AT-SPI"
    appName.send n
  if frames > 10:
    let (ok, f) = report.tryRecv()
    if ok:
      found = f
      got = true
      quitApp()
  if frames > 600: quitApp()
  wakeIn(20)

joinThread(th)
discard execShellCmd("kill " & readFile(addrFile & ".pid").strip & " 2>/dev/null")
removeFile(addrFile)
removeFile(addrFile & ".pid")
doAssert got, "the client finished"
doAssert found.error.len == 0, found.error
doAssert "entry Name:" in found.roles, $found.roles
doAssert "push button Greet" in found.roles, $found.roles
doAssert found.textPut and name == "Sultan", name
doAssert found.greetPressed and greeted == "Hello, Sultan!", greeted
doAssert found.focusHeard, "the focus event"
echo "test_atspi: ok (", found.roles.join(", "), ")"
