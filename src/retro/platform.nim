## Platform services for apps: a folder for the app's files, small saved
## settings, opening links, and what kind of device this is.

import std/[os, tables, strutils, osproc]
import uirelays/[services, input]
import core, gfx

export services.dataDir, services.openUrl, services.platformName,
       services.openFile, services.shareFile, services.places,
       services.storageAccess, services.requestStorageAccess,
       services.minimizeApp
export input.getClipboardText, input.putClipboardText
export tables   # (Settings is a table: len, hasKey, [], []=, pairs...)

proc isMobile*(): bool =
  ## A phone or tablet (touch screen, back button, on-screen keyboard).
  ui.touch or platformName() in ["android", "ios"]

type Settings* = OrderedTable[string, string]

proc settingsFile(app: string): string = dataDir(app) / "settings.ini"

proc unescape(s: string): string =
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len:
      result.add(if s[i+1] == 'n': '\n' else: s[i+1])
      i += 2
    else:
      result.add s[i]
      inc i

proc loadSettings*(app: string): Settings =
  ## The settings `saveSettings` stored for `app` (empty the first time).
  try:
    for line in lines(settingsFile(app)):
      var k = 0
      while k < line.len and line[k] != '=':
        if line[k] == '\\': inc k
        inc k
      if k > 0 and k < line.len:
        result[unescape(line[0 ..< k])] = unescape(line[k+1 .. ^1])
  except IOError, OSError:
    discard

proc saveSettings*(app: string; s: Settings): bool {.discardable.} =
  ## Store `s` in the app's data folder; written to a temporary file and
  ## moved into place, so a crash never leaves half a file. False when it
  ## could not be written (a full disk): the app goes on.
  var text = ""
  for k, v in s:
    text.add k.multiReplace(("\\", "\\\\"), ("=", "\\="), ("\n", "\\n"))
    text.add '='
    text.add v.multiReplace(("\\", "\\\\"), ("\n", "\\n"))
    text.add '\n'
  let f = settingsFile(app)
  try:
    writeFile(f & ".tmp", text)
    moveFile(f & ".tmp", f)
    result = true
  except IOError, OSError:
    result = false

proc get*(s: Settings; key: string; default = ""): string =
  ## A setting (`default` when it is not set).
  s.getOrDefault(key, default)

proc getInt*(s: Settings; key: string; default = 0): int =
  ## A setting as a number (`default` when it is not set or not a number).
  try: parseInt(s.getOrDefault(key, $default)) except ValueError: default

proc getBool*(s: Settings; key: string; default = false): bool =
  ## A setting as true or false (`default` when it is not set).
  s.getOrDefault(key, $default) == "true"

proc put*(s: var Settings; key: string; value: string) = s[key] = value
  ## Set a setting (`saveSettings` stores them).
proc put*(s: var Settings; key: string; value: int | bool) = s[key] = $value
  ## Set a setting (`saveSettings` stores them).

var uiFontPath* = ""
  ## The file of the UI's font when it is one of the user's (`loadUiFontFile`).

proc boldBeside*(path: string): string =
  ## The bold of a font file, when it lies beside it ("X-Regular.ttf":
  ## "X-Bold.ttf", "X.ttf": "XBold.ttf", "X-Bold.ttf", "X Bold.ttf").
  let (dir, name, ext) = path.splitFile
  # (the path's own separator: building for Windows elsewhere, `/` would be `\`)
  let sep = if '/' in path: "/" else: $DirSep
  var stems: seq[string]
  for sfx in ["-Regular", " Regular", "_Regular", "Regular", "-Roman", "-Book"]:
    if name.endsWith(sfx): stems.add name[0 ..< name.len - sfx.len]
  stems.add name
  for st in stems:
    for b in ["-Bold", " Bold", "_Bold", "Bold", "bd", "-bold"]:
      let p = dir & sep & st & b & ext
      if p != path and fileExists(p): return p
  ""

const
  appFontPath {.strdefine: "retroAppFont".} = ""
    ## a font built into the app (`-d:retroAppFont=path/X-Regular.ttf`,
    ## its bold beside it): the app's own, read at build time
  appFontBoldPath {.strdefine: "retroAppFontBold".} = ""
    ## its bold, when it is not beside it
  appFontBoldFile = (when appFontBoldPath.len > 0: appFontBoldPath
                     elif appFontPath.len > 0: boldBeside(appFontPath)
                     else: "")
  appFontRegular = (when appFontPath.len > 0: staticRead(appFontPath) else: "")
  appFontBold = (when appFontBoldFile.len > 0: staticRead(appFontBoldFile) else: "")
  appFontKey* = "builtin:" & (when appFontPath.len > 0: appFontPath.splitFile.name else: "")
    ## what `uiFontPath` says while the app's own font is the UI's

proc hasAppFont*(): bool = appFontRegular.len > 0
  ## The app was built with a font of its own (`-d:retroAppFont`).

proc loadUiFontFile*(path: string) =
  ## The font in `path` (a .ttf; its bold beside it, when there is one) as
  ## the UI's font (`ufFile`); `appFontKey`: the app's own font, built in.
  ## Raises `IOError` or `FontError`.
  if path == appFontKey and hasAppFont():
    setUiFontFile(appFontRegular, appFontBold)
  else:
    let regular = readFile(path)
    let b = boldBeside(path)
    setUiFontFile(regular, if b.len > 0: readFile(b) else: "")
  uiFontPath = path

proc useAppFont*() =
  ## The app's own font (built in with `-d:retroAppFont`) as the UI's;
  ## nothing when there is none. Apps built so start with it (until the
  ## user chooses another in `appearanceSettings`).
  if hasAppFont():
    try: loadUiFontFile(appFontKey)
    except CatchableError: discard

proc uiFontKey*(f: UiFont): string =
  ## The word settings keep font `f` as: "w98", "kawkab", "retro",
  ## "smooth", "file", "fixedsys", "opensans" (what `storeAppearance`
  ## writes; `uiFontOfKey` reads it back).
  case f
  of ufW98: "w98"
  of ufKawkab: "kawkab"
  of ufRetro: "retro"
  of ufSmooth: "smooth"
  of ufFile: "file"
  of ufFixedsys: "fixedsys"
  of ufOpenSans: "opensans"

proc uiFontOfKey*(key: string; f: var UiFont): bool =
  ## The built-in font `key` names (a word of `uiFontKey`), into `f`; false
  ## for an unknown word or "file" (a font from a file: `loadUiFontFile`).
  for u in UiFont:
    if u != ufFile and uiFontKey(u) == key:
      f = u
      return true

proc recentFiles*(s: Settings; key = "recent"): seq[string] =
  ## The files last opened (or saved), the newest first (`addRecentFile`).
  for i in 1 .. 100:
    let p = s.getOrDefault(key & "." & $i, "")
    if p.len == 0: break
    result.add p

proc addRecentFile*(s: var Settings; path: string; keep = 10; key = "recent") =
  ## `path` first in the list of recent files (once), keeping `keep` (0:
  ## the list is cleared). Store `s` with `saveSettings`.
  var l = recentFiles(s, key)
  let i = l.find(path)
  if i >= 0: l.delete(i)
  if path.len > 0: l.insert(path, 0)
  if l.len > keep: l.setLen(max(0, keep))
  for i in 1 .. 100: s.del(key & "." & $i)
  for i, p in l: s[key & "." & $(i + 1)] = p

proc storeAppearance*(s: var Settings) =
  ## Puts the look the user chose (colors, sizes, font, the window's frame)
  ## into `s`.
  let t = themeIndex()
  if t >= 0: s["look.colors"] = $t
  s["look.size"] = $uiScale()
  s["look.text"] = $textScale()
  s["look.smooth"] = $smoothScrolling
  s["look.controls"] = (case controlSizes()
                        of csAuto: "auto"
                        of csDesktop: "desktop"
                        of csTouch: "touch")
  s["look.hdtext"] = $hdText()
  s["look.icons"] = (case iconStyle()
                     of isAuto: "auto"
                     of isPixel: "pixel"
                     of isLine: "line")
  s["look.gpu"] = (case gpuMode()
                   of gmAuto: "auto"
                   of gmGpu: "gpu"
                   of gmCpu: "cpu")
  s["look.font"] = uiFontKey(uiFont())
  s["look.fontv"] = "2"
  if uiFontPath.len > 0: s["look.fontfile"] = uiFontPath
  # (the window's frame is kept by the toolkit itself, for every app:
  # `chooseClassicFrame`; the key stores of before held it)
  s.del("look.frame")

proc restoreAppearance*(s: Settings) =
  ## Brings back the look `storeAppearance` stored.
  let t = s.getInt("look.colors", -1)
  if t in 0 .. builtinThemes.high:
    ui.theme = builtinThemes[t].theme
    invalidate()
  themeFromEnv()
  # ($RETRO_SCALE, when set, wins over what was kept -- as $RETRO_THEME does)
  if s.hasKey("look.size") and not existsEnv("RETRO_SCALE"): setUiScale(s.getInt("look.size", 100))
  if s.hasKey("look.text"): setTextScale(s.getInt("look.text", 100))
  if s.hasKey("look.smooth"): setSmoothScrolling(s.getBool("look.smooth", true))
  case s.getOrDefault("look.controls", "")
  of "auto": setControlSizes(csAuto)
  of "desktop": setControlSizes(csDesktop)
  of "touch": setControlSizes(csTouch)
  else: discard
  if s.hasKey("look.hdtext"): setHdText(s.getBool("look.hdtext", true))
  case s.getOrDefault("look.icons", "")
  of "pixel": setIconStyle(isPixel)
  of "line": setIconStyle(isLine)
  of "auto": setIconStyle(isAuto)
  else: discard
  # ($RETRO_GPU, when set, wins over what was kept)
  case (if existsEnv("RETRO_GPU"): "" else: s.getOrDefault("look.gpu", ""))
  of "auto": setGpuMode(gmAuto)
  of "gpu": setGpuMode(gmGpu)
  of "cpu": setGpuMode(gmCpu)
  else: discard
  # (the frame a store of before kept: the user's choice, kept from now on
  # by the toolkit -- unless one was made since; $RETRO_FRAME wins)
  if not existsEnv("RETRO_FRAME") and keptFrame().len == 0:
    case s.getOrDefault("look.frame", "")
    of "classic": chooseClassicFrame(true)
    of "system": chooseClassicFrame(false)
    else: discard
  # (the old "look.pixelfont" key said false for everyone before Retro Sans
  # was the default: only a choice made since counts)
  # (Kawkab Mono was the default before MS W98 UI: stored before then, it
  # is the old default, not a choice)
  let font = s.getOrDefault("look.font", "")
  case (if font == "kawkab" and not s.hasKey("look.fontv"): "" else: font)
  of "retro": setUiFont(ufRetro)
  of "smooth": setUiFont(ufSmooth)
  of "kawkab": setUiFont(ufKawkab)
  of "w98": setUiFont(ufW98)
  of "fixedsys": setUiFont(ufFixedsys)
  of "opensans": setUiFont(ufOpenSans)
  of "file":
    # (the font from a file: when it is still there)
    let p = s.getOrDefault("look.fontfile", "")
    if (p.len > 0 and fileExists(p)) or (p == appFontKey and hasAppFont()):
      try: loadUiFontFile(p)
      except CatchableError: discard
  of "": useAppFont()        # (nothing chosen yet: the app's own font, when it has one)
  else: discard

proc canOpenTerminal*(): bool =
  ## `openTerminal` can work here (a desktop).
  when defined(android) or defined(ios): false else: true

proc openTerminal*(dir: string): bool {.discardable.} =
  ## Opens a terminal window in the folder `dir` (the system's own: on
  ## Linux $TERMINAL or the first of the usual ones there; Windows
  ## Terminal or the command prompt; macOS's Terminal). False when none
  ## could be started.
  when defined(android) or defined(ios):
    false
  else:
    proc start(exe: string; args: openArray[string]): bool =
      try:
        let p = startProcess(exe, workingDir = dir, args = args, options = {poUsePath, poDaemon})
        p.close()
        true
      except OSError: false
    when defined(windows):
      if findExe("wt").len > 0 and start("wt", ["-d", dir]): return true
      start("cmd.exe", ["/c", "start", "cmd.exe", "/K", "cd /d \"" & dir & "\""])
    elif defined(macosx):
      start("open", ["-a", "Terminal", dir])
    else:
      var tried: seq[string]
      let own = getEnv("TERMINAL")
      if own.len > 0: tried.add own
      tried.add ["x-terminal-emulator", "gnome-terminal", "konsole", "xfce4-terminal",
                 "kitty", "alacritty", "wezterm", "foot", "tilix", "mate-terminal",
                 "lxterminal", "terminator", "xterm"]
      for t in tried:
        if findExe(t).len > 0:
          # (each starts in the working folder; gnome-terminal and konsole are told too)
          let args = case t
                     of "gnome-terminal", "mate-terminal", "xfce4-terminal", "tilix":
                       @["--working-directory=" & dir]
                     of "konsole": @["--workdir", dir]
                     else: @[]
          if start(t, args): return true
      false
