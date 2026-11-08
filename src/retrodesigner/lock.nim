## Retro Designer's hold on the file it designs: one of the designer or your
## editor has it, never both. The designer writes a lock beside the file
## (`.NAME.lock`: who holds it), and while it holds it the file is kept from
## other programs -- on Windows by holding it open so that no one else can
## write it, elsewhere by making it read-only (most editors then warn).
## "Edit Code" gives the file to your editor (saved, the lock let go) and
## takes it back, read again, when the editor closes. A lock left by a
## designer that is gone (it crashed) is taken over, the file's rights put
## back.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, times, osproc]
when defined(windows):
  import std/widestrs
else:
  import std/posix

type
  Hold* = object
    path*: string
    held*: bool
    by*: string                  ## who has it when we do not ("" no one)
    mode: int                    ## the file's rights before (POSIX)
    when defined(windows):
      handle: pointer

proc lockPath*(path: string): string =
  let (dir, name, ext) = splitFile(path)
  dir / ("." & name & ext & ".lock")

proc hostName*(): string =
  when defined(windows): getEnv("COMPUTERNAME", "this computer")
  else:
    try: readFile("/etc/hostname").strip
    except IOError: getEnv("HOSTNAME", "this computer")

proc alive(pid: int): bool =
  if pid <= 0: return false
  when defined(windows):
    try:
      let o = execProcess("tasklist", args = ["/FI", "PID eq " & $pid, "/NH"],
                          options = {poUsePath, poDaemon})
      $pid in o
    except CatchableError: true
  else:
    kill(Pid(pid), 0) == 0 or errno == EPERM

when defined(windows):
  proc CreateFileW(name: WideCString; access, share: uint32; sa: pointer; disp, flags: uint32;
                   tmpl: pointer): pointer {.stdcall, dynlib: "kernel32", importc.}
  proc CloseHandle(h: pointer): int32 {.stdcall, dynlib: "kernel32", importc.}
  const
    GenericRead = 0x80000000'u32
    FileShareRead = 0x1'u32
    OpenExisting = 3'u32
    InvalidHandle = cast[pointer](-1)

proc guard(h: var Hold) =
  ## The file kept from other programs.
  when defined(windows):
    let w = newWideCString(h.path)
    h.handle = CreateFileW(toWideCString(w), GenericRead, FileShareRead, nil, OpenExisting, 0, nil)
    if h.handle == InvalidHandle: h.handle = nil
  else:
    var st: Stat
    if stat(h.path.cstring, st) == 0:
      h.mode = int(st.st_mode) and 0o7777
      discard chmod(h.path.cstring, Mode(h.mode and not 0o222))

proc unguard(h: var Hold) =
  ## The file open to other programs again.
  when defined(windows):
    if h.handle != nil:
      discard CloseHandle(h.handle)
      h.handle = nil
  else:
    if h.mode != 0:
      discard chmod(h.path.cstring, Mode(h.mode))

when not defined(windows):
  # (killed -- the session ending, a terminal closed --: the file's rights
  #  and the lock put back all the same; only what a signal may do)
  var
    sigFile, sigLock: array[4096, char]
    sigMode: Mode
    sigArmed, sigSet: bool

  proc onSignal(sig: cint) {.noconv.} =
    if sigArmed:
      if sigMode != Mode(0): discard chmod(cast[cstring](addr sigFile[0]), sigMode)
      discard unlink(cast[cstring](addr sigLock[0]))
    exitnow(128 + sig)

  proc keep(dest: var array[4096, char]; s: string) =
    let n = min(s.len, dest.len - 1)
    if n > 0: copyMem(addr dest[0], unsafeAddr s[0], n)
    dest[n] = '\0'

  proc arm(h: Hold) =
    keep(sigFile, h.path)
    keep(sigLock, lockPath(h.path))
    sigMode = Mode(h.mode)
    sigArmed = true
    if not sigSet:
      sigSet = true
      for s in [SIGTERM, SIGHUP, SIGINT, SIGQUIT]: discard signal(s, onSignal)

proc readLock(path: string): tuple[pid: int; host: string; mode: int] =
  try:
    let f = readFile(lockPath(path)).splitLines
    for l in f:
      let kv = l.split('=', 1)
      if kv.len < 2: continue
      case kv[0].strip
      of "pid": result.pid = parseInt(kv[1].strip)
      of "host": result.host = kv[1].strip
      of "mode": result.mode = parseInt(kv[1].strip)
      else: discard
  except CatchableError: discard

proc take*(path: string): Hold =
  ## The file held by this designer, unless another one that is running
  ## has it (then `held` is false and `by` says who).
  result.path = path.absolutePath
  if not fileExists(result.path): return
  let lp = lockPath(result.path)
  if fileExists(lp):
    let l = readLock(result.path)
    if l.pid != getCurrentProcessId() and l.host == hostName() and alive(l.pid):
      result.by = "Retro Designer (" & $l.pid & ")"
      return
    # (a lock left by a designer that is gone: the file's rights back)
    when not defined(windows):
      if l.mode != 0: discard chmod(result.path.cstring, Mode(l.mode))
  result.guard()
  try:
    writeFile(lp, "pid=" & $getCurrentProcessId() & "\nhost=" & hostName() &
              "\nmode=" & $result.mode & "\nsince=" & $now() & "\n")
    result.held = true
    when not defined(windows): arm(result)
  except IOError:
    result.unguard()

proc release*(h: var Hold) =
  ## The file let go: its rights back, the lock gone.
  if not h.held: return
  when not defined(windows): sigArmed = false
  h.unguard()
  try: removeFile(lockPath(h.path)) except OSError: discard
  h.held = false

proc writeHeld*(h: var Hold; text: string) =
  ## The file written while this designer holds it.
  if h.held: h.unguard()
  try:
    writeFile(h.path, text)
  finally:
    if h.held: h.guard()

# ---- your editor --------------------------------------------------------------------------------

proc terminalPrefix(): seq[string] =
  ## How a terminal program is started in a window of its own.
  when defined(windows): @["cmd", "/c", "start", "/wait", "cmd", "/c"]
  elif defined(macosx): @[]
  else:
    if findExe("retro-desktop").len > 0 and getEnv("DISPLAY").len > 0: @["retro-desktop", "terminal", "-e"]
    elif findExe("x-terminal-emulator").len > 0: @["x-terminal-emulator", "-e"]
    elif findExe("xterm").len > 0: @["xterm", "-e"]
    elif findExe("gnome-terminal").len > 0: @["gnome-terminal", "--wait", "--"]
    elif findExe("konsole").len > 0: @["konsole", "-e"]
    else: @[]

proc defaultEditor*(): string =
  ## The editor command: {file} and {line} are put in. The file's own
  ## editor setting comes first (this is when there is none).
  let env = getEnv("VISUAL", getEnv("EDITOR"))
  let term = terminalPrefix().join(" ")
  if findExe("ned").len > 0:
    return (if term.len > 0: term & " " else: "") & "ned {file}:{line}"
  if env.len > 0:
    let name = env.splitWhitespace[0].extractFilename
    if name in ["vim", "vi", "nvim", "nano", "emacs", "hx", "helix", "micro", "kak", "joe", "mg"]:
      return (if term.len > 0: term & " " else: "") & env & " +{line} {file}"
    return env & " {file}"
  if findExe("code").len > 0: return "code --wait -g {file}:{line}"
  when defined(windows): "notepad {file}"
  elif defined(macosx): "open -W -t {file}"
  else: (if term.len > 0: term & " " else: "") & "nano +{line} {file}"

proc startEditor*(command, file: string; line: int): Process =
  ## The editor started at the line (its process: the designer waits for
  ## it to close).
  var parts = command.splitWhitespace
  if parts.len == 0: return nil
  for p in parts.mitems:
    p = p.replace("{file}", file).replace("{line}", $max(1, line))
  let exe = findExe(parts[0])
  if exe.len == 0: return nil
  try:
    startProcess(exe, args = parts[1 .. ^1], options = {poParentStreams})
  except OSError:
    nil
