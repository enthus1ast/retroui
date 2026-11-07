## retrokit -- start, check and build Retro Nim UI apps.
##
##   retrokit new myapp [--kind:hello|form|business|files|charts]
##   retrokit doctor                  what this machine has, what is missing
##   retrokit run app.nim [options]   build (release) and run it
##       --window      on a screen with no window manager (Termux:X11): the
##                     app as a window of its own size, in its 3.1 frame, in
##                     the middle of a desktop, scaled to the screen
##       --scale:N     everything N percent of its normal size (and the window)
##       --size:WxH    the window this many design pixels (to try layouts)
##       --theme:NAME  a built-in theme ("Dark", "OLED Black"...)
##       --watch       built again and started again on every save, in the
##                     same place (with --window); --live is both
##       other options go to the Nim compiler
##   retrokit small app.nim           the smallest build (optimized for size, stripped)
##   retrokit apk app.nim [options]   an Android APK (the retroapk tool)
##
## No dependencies but Nim and a C compiler.

import std/[os, osproc, strutils, dynlib, sequtils, times, hashes]

const usage = """
retrokit -- start, check and build Retro Nim UI apps

  retrokit new NAME [--kind:hello|form|business|files|charts]
      a folder NAME with NAME.nim, NAME.nimble (tasks: run, small, apk)
      and an icon
  retrokit doctor
      checks Nim, the C compiler, the screen libraries and the Android tools
      (clang + lld or zig: APKs without the NDK)
  retrokit run APP.nim [options]
      build it (release) and run it; options:
        --window      on a screen with no window manager (Termux:X11): the
                      app as a window of its own size, in its 3.1 frame, in
                      the middle of a desktop, scaled to the screen
        --scale:N     everything N percent of its normal size (the window too)
        --size:WxH    the window W x H design pixels, to try layouts
        --theme:NAME  a built-in theme ("Dark", "OLED Black"...)
        --watch       on every save of a .nim file in the app's folder, built
                      again and started again where the window was; the old
                      one runs on while the code does not build
        --live        --window and --watch together
      anything else goes to the Nim compiler (-d:..., --opt:...)
  retrokit small APP.nim       the smallest build: optimized for size, stripped
  retrokit apk APP.nim [...]   an Android APK (same options as retroapk)
"""

const templates = [
  ("hello", """import retroui

var name = "World"
var greeted = ""

app "$1", 360, 160:
  row([50, -1]):
    label "&Name:"
    edit name
  row:
    if button("&Greet", isDefault = true):
      greeted = "Hello, " & name & "!"
    if button("E&xit"): quitApp()
  label greeted
"""),
  ("form", """import retroui

var name, email, phone = ""
var birthday = today()
var plan = 0
var news = true
var saved = ""

app "$1", 520, 360:
  form 0:
    field "&Name:": edit name
    field "&E-mail:": edit email
    field "&Phone:": maskedEdit(phone, "+### #### ####")
    field "&Birthday:": datePicker birthday
    field "Pl&an:": combo(["Free", "Pro", "Business"], plan)
    field "": checkbox("Send me &news", news)
  row:
    spring()
    if button("&Save", isDefault = true, enabled = name.len > 0):
      saved = "Saved " & name & "."
    if button("Cancel"): quitApp()
  label saved
"""),
  ("business", """import retroui

type Order = object
  customer: string
  amount: float
  paid: bool
  status: string

var orders = @[
  Order(customer: "Al Noor Trading", amount: 1250.5, paid: true, status: "green"),
  Order(customer: "Gulf Print House", amount: 830.0, paid: false, status: "orange"),
  Order(customer: "Sohar Steel", amount: 4200.75, paid: false, status: "red")]
var cols = @[column("Customer", 200), numberColumn("Amount", 100),
             checkColumn("Paid", 50), colorColumn("Status", 60)]
var sel = 0
var pos = 0

app "$1", 640, 420:
  menubar:
    menu "&File":
      if menuItem("E&xit"): quitApp()
  let ev = grid(cols, orders.len, proc (r, c: int): string =
      case c
      of 0: orders[r].customer
      of 1: formatNumber(orders[r].amount)
      of 2: (if orders[r].paid: "1" else: "0")
      else: orders[r].status,
    sel, height = -1, rowHeaders = true,
    footer = proc (c: int): string =
      if c == 0: "Total"
      elif c == 1:
        var t = 0.0
        for o in orders: t += o.amount
        formatNumber(t)
      else: "")
  if ev.toggled: orders[ev.row].paid = ev.text == "1"
  pos = sel
  if recordNav(pos, orders.len) != raNone: sel = pos
  statusbar($orders.len & " orders")
"""),
  ("files", """import std/os
import retroui

var folder = newFolderModel(getHomeDir())
var paneW = 280          # the details pane's width (beside) and height (under)
var paneH = 200

app "$1", 900, 600:
  let pb = pathBar(folder.dir)
  if pb.go.len > 0: folder.open(pb.go)
  sidePane(true, paneW, paneH):
    let ev = fileList(folder, fvIcons)
    if ev.activated:
      if ev.item.isDir: folder.open(ev.item.path)
      else: discard openFile(ev.item.path)
  do:
    discard filePreview(folder)
"""),
  ("charts", """import retroui

let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]

app "$1", 800, 520:
  chart("Sales and costs (thousands)", chCombo, months,
        [series("Sales", [12.0, 15.5, 14.2, 18.9, 21.3, 24.0]),
         lineSeries("Costs", [8.0, 9.1, 9.8, 11.0, 12.4, 13.0])],
        height = -1)
"""),
]

proc nimbleFor(name: string): string =
  "# Package\n\nversion       = \"0.1.0\"\nauthor        = \"You\"\n" &
  "description   = \"" & name & ", made with Retro Nim UI\"\nlicense       = \"MIT\"\n" &
  "bin           = @[\"" & name & "\"]\n\n# Dependencies\n\nrequires \"nim >= 2.0.0\"\n" &
  "requires \"retroui\"\n\n# Tasks\n\n" &
  "task run, \"Build and run\":\n  exec \"nim c -r -d:release " & name & ".nim\"\n\n" &
  "task small, \"The smallest build\":\n  exec \"nim c -d:release -d:useMalloc --opt:size -d:lto --passL:-s " &
  name & ".nim\"\n\n" &
  "task apk, \"An Android APK\":\n  exec \"retroapk " & name & ".nim --name:\\\"" & name &
  "\\\" --icon:icon.png\"\n"

proc tinyIcon(): string =
  ## A 32x32 PNG: a 3.1 window (navy title, gray frame, white inside).
  ## Written without the kit, so the tool stays small.
  proc crc32(s: string): uint32 =
    var c = 0xFFFFFFFF'u32
    for ch in s:
      c = c xor uint32(ord(ch))
      for _ in 0 ..< 8: c = if (c and 1) != 0: (c shr 1) xor 0xEDB88320'u32 else: c shr 1
    not c
  proc be32(v: uint32): string =
    result = newString(4)
    result[0] = char((v shr 24) and 255)
    result[1] = char((v shr 16) and 255)
    result[2] = char((v shr 8) and 255)
    result[3] = char(v and 255)
  proc chunk(kind, data: string): string =
    be32(uint32(data.len)) & kind & data & be32(crc32(kind & data))
  proc adler(s: string): uint32 =
    var a = 1'u32
    var b = 0'u32
    for ch in s:
      a = (a + uint32(ord(ch))) mod 65521
      b = (b + a) mod 65521
    (b shl 16) or a
  var raw = ""
  for y in 0 ..< 32:
    raw.add '\0'
    for x in 0 ..< 32:
      let edge = x == 0 or y == 0 or x == 31 or y == 31
      let (r, g, b) =
        if edge: (0, 0, 0)
        elif y < 8: (0, 0, 128)
        elif x < 2 or x > 29 or y > 29: (192, 192, 192)
        else: (255, 255, 255)
      raw.add char(r)
      raw.add char(g)
      raw.add char(b)
  # stored (uncompressed) deflate blocks
  var z = "\x78\x01"
  var i = 0
  while i < raw.len:
    let n = min(65535, raw.len - i)
    z.add(if i + n >= raw.len: '\1' else: '\0')
    z.add char(n and 255)
    z.add char(n shr 8)
    z.add char((not n) and 255)
    z.add char(((not n) shr 8) and 255)
    z.add raw[i ..< i + n]
    i += n
  z.add be32(adler(raw))
  "\x89PNG\r\n\x1a\n" & chunk("IHDR", be32(32) & be32(32) & "\x08\x02\x00\x00\x00") &
    chunk("IDAT", z) & chunk("IEND", "")

proc newApp(name, kind: string) =
  if name.len == 0 or not name.validIdentifier:
    quit "retrokit: the name must be a Nim identifier (letters, digits, _): " & name
  if dirExists(name): quit "retrokit: " & name & " already exists"
  var body = ""
  for (k, t) in templates:
    if k == kind: body = t.replace("$1", name)
  if body.len == 0:
    quit "retrokit: no kind " & kind & " (hello, form, business, files, charts)"
  createDir(name)
  writeFile(name / name & ".nim", body)
  writeFile(name / name & ".nimble", nimbleFor(name))
  writeFile(name / "icon.png", tinyIcon())
  writeFile(name / "config.nims",
    "# where the retroui package is when it is not installed with nimble:\n" &
    "# switch(\"path\", \"/path/to/retroui/src\")\n" &
    "# (the system's malloc: memory let go of goes back to the system)\n" &
    "switch(\"define\", \"useMalloc\")\n" &
    "when defined(windows): switch(\"app\", \"gui\")\n")
  echo "Made ", name, "/ (", kind, "):"
  echo "  cd ", name, " && nimble run        # build and run"
  echo "  nimble small                         # the smallest build"
  echo "  nimble apk                           # an Android APK"

proc found(cmd: string): string =
  let p = findExe(cmd)
  if p.len > 0: p else: ""

proc doctor() =
  var ok = true
  proc line(good: bool; what, detail: string; fix = "") =
    echo (if good: "  ok    " else: "  MISS  "), what, (if detail.len > 0: ": " & detail else: "")
    if not good and fix.len > 0: echo "        -> ", fix
  echo "Retro Nim UI doctor (", hostOS, " ", hostCPU, ")"
  let nimV = try: execProcess("nim --version").splitLines[0] except CatchableError: ""
  line(nimV.len > 0, "Nim", nimV, "install Nim 2.x: https://nim-lang.org/install.html")
  if nimV.len == 0: ok = false
  var cc = ""
  for c in ["gcc", "clang", "cc", "cl"]:
    if found(c).len > 0:
      cc = c
      break
  line(cc.len > 0, "C compiler", cc,
       when defined(windows): "install MinGW-w64 (choosenim installs it) or Visual Studio Build Tools"
       elif defined(macosx): "xcode-select --install"
       else: "install gcc or clang (apt install gcc, pkg install clang in Termux)")
  if cc.len == 0: ok = false
  when defined(linux) or defined(bsd):
    if existsEnv("TERMUX_VERSION") and not existsEnv("DISPLAY"):
      line(false, "screen", "no DISPLAY",
           "start Termux:X11 (or a VNC server) and export DISPLAY=:0; or build an APK")
    for lib in ["libX11.so.6", "libXft.so.2"]:
      let h = loadLib(lib)
      line(h != nil, lib, (if h != nil: "found" else: "not found"),
           "install the X11 client libraries (apt install libx11-6 libxft2)")
      if h != nil: unloadLib(h)
    line(existsEnv("DISPLAY") or existsEnv("WAYLAND_DISPLAY"), "display",
         getEnv("DISPLAY", getEnv("WAYLAND_DISPLAY")),
         "run inside a desktop session (Wayland works through XWayland)")
  # Android: Termux's clang, an NDK, or -- no NDK -- a clang that has lld,
  # or zig, with the sysroot retroapk carries; with none of them retroapk
  # fetches the NDK
  let termuxCC = existsEnv("TERMUX_VERSION") and found("clang").len > 0
  let ndk = getEnv("ANDROID_NDK_HOME", getEnv("ANDROID_NDK_ROOT"))
  let fetched = getEnv("RETRO_NDK_DIR", getHomeDir() / ".retro" / "ndk")
  var have = ""
  if termuxCC: have = "Termux clang"
  elif existsEnv("RETRO_ANDROID_CC"): have = getEnv("RETRO_ANDROID_CC")
  elif ndk.len > 0 and dirExists(ndk): have = "NDK " & ndk
  elif dirExists(fetched):
    for kind, p in walkDir(fetched):
      if kind == pcDir and p.extractFilename.startsWith("android-ndk"): have = "NDK " & p
  # (the same search as retroapk's: clang with ld.lld beside it or on the
  # PATH -- Apple's clang has none --, then zig or pip's ziglang)
  var clangs: seq[string]
  when defined(macosx):
    clangs.add ["/opt/homebrew/opt/llvm/bin/clang", "/usr/local/opt/llvm/bin/clang"]
  clangs.add found("clang")
  when defined(windows):
    clangs.add getEnv("ProgramFiles", r"C:\Program Files") / "LLVM" / "bin" / "clang.exe"
  for v in countdown(30, 14): clangs.add found("clang-" & $v)
  var noNdk = ""
  for c in clangs:
    if c.len == 0 or not fileExists(c): continue
    let ver = c.extractFilename.changeFileExt("").substr(5)    # "-18" of clang-18
    var llds = @[c.parentDir / "ld.lld" & ExeExt, found("ld.lld"), found("ld.lld" & ver)]
    when defined(macosx):
      llds.add ["/opt/homebrew/opt/lld/bin/ld.lld", "/usr/local/opt/lld/bin/ld.lld"]
    if llds.anyIt(it.len > 0 and fileExists(it)):
      noNdk = "clang + lld (no NDK needed): " & c
      break
  if noNdk.len == 0 and found("zig").len > 0: noNdk = "zig (no NDK needed): " & found("zig")
  if noNdk.len == 0:
    for py in ["python3", "python", "py"]:
      if found(py).len > 0 and execCmdEx(quoteShellCommand([found(py), "-c",
                                         "import ziglang"])).exitCode == 0:
        noNdk = "zig from pip's ziglang (no NDK needed)"
        break
  if have.len > 0 or noNdk.len > 0:
    line(true, "Android APKs", (if have.len > 0: have else: noNdk))
  elif existsEnv("TERMUX_VERSION"):
    line(true, "Android APKs", "retroapk installs clang with pkg on first use")
  else:
    line(false, "Android APKs", "no clang with lld, no zig, no NDK",
         (when defined(windows): "winget install LLVM.LLVM (or zig.zig)"
          elif defined(macosx): "brew install llvm lld (or zig)"
          elif defined(bsd): "clang and lld from packages or ports (or zig)"
          else: "install clang and lld (apt install clang lld) or zig") &
         "; without them retroapk fetches the NDK once (about 700 MB; nimble ndk: now)")
  line(true, "APK signing", "built in (no apksigner, no OpenSSL, no Java)")
  line(found("adb").len > 0 or existsEnv("TERMUX_VERSION"), "installing on a device",
       (if found("adb").len > 0: "adb" elif existsEnv("TERMUX_VERSION"): "Termux's installer" else: "no adb"),
       "optional: install adb to put the APK on a phone from here")
  when defined(macosx):
    line(found("xcrun").len > 0, "iOS", "xcrun", "install Xcode for retroios")
  echo(if ok: "Ready to build Retro apps." else: "Fix what is missing above, then run retrokit doctor again.")
  if not ok: quit(1)

proc build(app: string; extra: openArray[string]; run: bool): int =
  if not fileExists(app): quit "retrokit: no file " & app
  var args = @["c", "-d:release", "-d:useMalloc", "--hints:off"]
  for e in extra: args.add e
  if run: args.add "-r"
  args.add app
  echo "nim ", args.join(" ")
  let p = startProcess(findExe("nim"), args = args, options = {poParentStreams})
  result = p.waitForExit()
  p.close()

# ---- run --watch: built again on every save ------------------------------------------------
#
# The app is built to one of two files in turn (a running program's file
# cannot be written over), the new one is started, and the one before is
# ended once the new one is up: the window is never gone in between, and
# with --window it opens where the last one was ($RETRO_WINDOW_STATE). The
# compiler's cache is the usual one, so only what changed is compiled again.
# Closing the window ends it; an app that crashes is started again with the
# next save.

var watching = false

proc sourcesStamp(dir: string): Hash =
  ## (the sources in the app's folder and two levels below it, and when each
  ## was written: hidden folders, caches and links to folders -- Termux's
  ## ~/storage -- left out, so an app in the home folder is cheap to watch)
  var h: Hash = 0
  var todo = @[(dir, 0)]
  while todo.len > 0:
    let (d, depth) = todo.pop()
    for kind, f in walkDir(d):
      let n = f.extractFilename
      if n.startsWith("."): continue
      case kind
      of pcFile:
        if n.endsWith(".nim") or n.endsWith(".nims") or n == "nim.cfg":
          try: h = h !& hash(f) !& hash(getLastModificationTime(f).toUnixFloat)
          except OSError: discard
      of pcDir:
        if depth < 2 and n notin ["nimcache", "build", "node_modules", "storage"]:
          todo.add (f, depth + 1)
      else: discard
  !$h

proc watchRun(app: string; extra: seq[string]): int =
  let name = app.splitFile.name
  let dir = app.absolutePath.parentDir
  let work = getTempDir() / "retrokit-" & name & "-" & $getCurrentProcessId()
  createDir(work)
  putEnv("RETRO_WINDOW_STATE", work / "window")
  var running: Process = nil
  var slot = 0
  var builds = 0

  proc buildOnce(): string =
    ## The app built again; its file, or "" when it does not build.
    slot = 1 - slot
    let exe = work / (name & $slot & ExeExt)
    var args = @["c", "-d:release", "-d:useMalloc", "--hints:off", "-o:" & exe]
    for e in extra: args.add e
    args.add app
    if builds == 0: echo "nim ", args.join(" ")
    inc builds
    let t0 = epochTime()
    let p = startProcess(findExe("nim"), args = args, options = {poParentStreams})
    let code = p.waitForExit()
    p.close()
    if code != 0: return ""
    echo "retrokit: built in ", formatFloat(epochTime() - t0, ffDecimal, 1), " s"
    exe

  proc start(exe: string) =
    let p = startProcess(exe, workingDir = getCurrentDir(), options = {poParentStreams})
    # (the one before goes once the new one is up: no blank screen between)
    sleep(700)
    if running != nil:
      running.terminate()
      if running.waitForExit(2000) == -1 or running.running: running.kill()
      running.close()
    running = p

  var stamp = sourcesStamp(dir)
  let first = buildOnce()
  if first.len > 0: start(first)
  echo "retrokit: watching ", dir, " -- save to see the change; close the window or Ctrl+C to stop"
  while true:
    sleep(300)
    if running != nil and not running.running:
      let code = running.peekExitCode
      running.close()
      running = nil
      if code == 0:
        removeDir(work)
        return 0                                  # (the window was closed)
      echo "retrokit: the app ended (", code, "); save a fix to start it again"
    let now = sourcesStamp(dir)
    if now != stamp:
      sleep(150)                                  # (an editor may write in steps)
      stamp = sourcesStamp(dir)
      let exe = buildOnce()
      if exe.len > 0: start(exe)
      elif running != nil: echo "retrokit: the window keeps the code before; fix it and save"

proc runOptions(args: openArray[string]): seq[string] =
  ## `run`'s own options, put in the environment the app starts with; what
  ## is left goes to the compiler.
  for a in args:
    let (key, value) =
      if a.startsWith("--") and (':' in a or '=' in a):
        let i = a.find({':', '='})
        (a[2 ..< i], a[i + 1 .. ^1])
      else: (a.strip(chars = {'-'}), "")
    case key
    of "window", "w": putEnv("RETRO_WINDOW", "1")
    of "scale":
      try: putEnv("RETRO_SCALE", $clamp(parseInt(value.strip(chars = {'%'})), 50, 300))
      except ValueError: quit "retrokit: --scale wants a percent, like --scale:150"
    of "size":
      if 'x' notin value: quit "retrokit: --size wants a width and a height, like --size:420x840"
      putEnv("RETRO_SIZE", value)
    of "theme": putEnv("RETRO_THEME", value)
    of "watch": watching = true
    of "live":
      putEnv("RETRO_WINDOW", "1")
      watching = true
    else: result.add a

proc main() =
  let args = commandLineParams()
  if args.len == 0 or args[0] in ["-h", "--help", "help"]:
    echo usage
    return
  case args[0]
  of "new":
    var name, kind = ""
    kind = "hello"
    for a in args[1 .. ^1]:
      if a.startsWith("--kind:"): kind = a[7 .. ^1]
      elif name.len == 0: name = a
    newApp(name, kind)
  of "doctor": doctor()
  of "run":
    # (the file may come before or after the options)
    let rest = runOptions(args[1 .. ^1])
    let app = rest.filterIt(it.endsWith(".nim"))
    if app.len == 0: quit usage
    if not fileExists(app[0]): quit "retrokit: no file " & app[0]
    if watching: quit watchRun(app[0], rest.filterIt(it != app[0]))
    quit build(app[0], rest.filterIt(it != app[0]), true)
  of "small":
    if args.len < 2: quit usage
    let code = build(args[1], @["--opt:size", "-d:lto", "--passL:-s"] & args[2 .. ^1], false)
    let exe = args[1].changeFileExt(ExeExt)
    if code == 0 and fileExists(exe):
      echo exe, ": ", getFileSize(exe) div 1024, " KB"
    quit code
  of "apk":
    let tool = findExe("retroapk")
    if tool.len == 0: quit "retrokit: retroapk is not installed (nimble install retroui)"
    let p = startProcess(tool, args = args[1 .. ^1], options = {poParentStreams})
    let code = p.waitForExit()
    p.close()
    quit code
  else:
    quit usage

when isMainModule: main()
