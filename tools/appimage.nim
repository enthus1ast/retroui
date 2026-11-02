## A Linux program as an AppImage -- one file that runs on most Linux
## systems, with its name, version, icon and menu entry:
##
##   nim c -r tools/appimage.nim build/linux/retrofiles "Retro Files" 3.3 icon.png build/RetroFiles-x86_64.AppImage
##
## makes an AppDir next to the AppImage (usr/bin/<program>, AppRun,
## <program>.desktop, the icon at 256 pixels as <program>.png, .DirIcon and
## usr/share/icons/hicolor/256x256/apps/<program>.png) and packs it with
## appimagetool. A sixth argument gives the menu categories
## ("System;FileTools;FileManager;"); without it they come from the name
## (Photo, Paint, Image, Draw: Graphics; File: Utility and FileManager;
## else Utility).
##
## appimagetool (the one on the PATH, else the AppImage project's own) and
## the AppImage runtime are downloaded once, with curl or wget, into
## ~/.cache/retro-appimage ($XDG_CACHE_HOME, or $RETRO_APPIMAGE_DIR), so
## nothing is fetched while packing; appimagetool, itself an AppImage, is
## unpacked there, so no FUSE is needed to run it. Without them -- no
## network -- the AppDir is kept and packed as <out>.AppDir.tar.gz instead.
##
## Libraries are not bundled: the program loads X11 (and EGL) at run time
## and every desktop has them; fonts and pictures are compiled into it.
## What it does need is a glibc as new as the one it was linked with (said
## at the end): `nimble photoappimage` and `filesappimage` link with an
## older one through zig (tools/zigcc.sh) when there is zig.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, osproc, strutils]
import retro/[gfx, imaging]

const
  ToolUrl = "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$1.AppImage"
  RuntimeUrl = "https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-$1"
  IconSize = 256

proc cacheDir(): string =
  getEnv("RETRO_APPIMAGE_DIR", getCacheDir("retro-appimage"))

proc elfArch(file: string): string =
  ## The AppImage name of the machine `file` is for ("" when not an ELF).
  var f: File
  if not open(f, file): return ""
  var head = newString(20)
  let n = f.readBuffer(addr head[0], head.len)
  f.close()
  if n < head.len or not head.startsWith("\x7FELF"): return ""
  case ord(head[18]) or (ord(head[19]) shl 8)
  of 0x3E: "x86_64"
  of 0xB7: "aarch64"
  of 0x03: "i686"
  of 0x28: "armhf"
  else: ""

proc hostArch(): string =
  case hostCPU
  of "amd64": "x86_64"
  of "arm64": "aarch64"
  of "i386": "i686"
  of "arm": "armhf"
  else: hostCPU

proc download(url, file: string): bool =
  ## (`file` from `url` once: kept in the cache when it is a program)
  if fileExists(file): return true
  createDir(file.parentDir)
  let part = file & ".part"
  var cmd = ""
  if findExe("curl").len > 0:
    cmd = quoteShellCommand(["curl", "-fL", "--retry", "3", "-o", part, url])
  elif findExe("wget").len > 0:
    cmd = quoteShellCommand(["wget", "-O", part, url])
  else:
    echo "appimage: no curl or wget to download ", url
    return false
  echo "downloading ", url
  if execCmd(cmd) != 0 or elfArch(part).len == 0:
    removeFile(part)
    echo "appimage: cannot download ", url
    return false
  moveFile(part, file)
  setFilePermissions(file, getFilePermissions(file) + {fpUserExec, fpGroupExec, fpOthersExec})
  true

proc unpackedTool(cache: string): string =
  ## (appimagetool from the cache, unpacked there once -- an AppImage run
  ## that way needs no FUSE and leaves nothing behind in /tmp: its AppRun)
  let dir = cache / ("appimagetool-" & hostArch())
  if fileExists(dir / "AppRun"): return dir / "AppRun"
  let image = dir & ".AppImage"
  if not download(ToolUrl % hostArch(), image): return ""
  removeDir(cache / "squashfs-root")
  if execCmd("cd " & quoteShell(cache) & " && " & quoteShell(image) &
             " --appimage-extract > /dev/null") != 0 or
     not fileExists(cache / "squashfs-root" / "AppRun"):
    echo "appimage: cannot unpack ", image
    return ""
  moveDir(cache / "squashfs-root", dir)
  removeFile(image)
  dir / "AppRun"

proc glibcNeeded(file: string): string =
  ## (the newest glibc version `file` asks for: its GLIBC_2.x symbol versions)
  let data = readFile(file)
  var best = (0, 0, 0)
  var at = data.find("GLIBC_2.")
  while at >= 0:
    var i = at + 6
    var v: seq[int]
    var n = -1
    while i < data.len and data[i] in {'0' .. '9', '.'}:
      if data[i] == '.':
        if n >= 0: v.add n
        n = -1
      else: n = max(n, 0) * 10 + ord(data[i]) - ord('0')
      inc i
    if n >= 0: v.add n
    while v.len < 3: v.add 0
    best = max(best, (v[0], v[1], v[2]))
    at = data.find("GLIBC_2.", i)
  if best[0] == 0: return ""
  $best[0] & "." & $best[1] & (if best[2] > 0: "." & $best[2] else: "")

proc channel(v, a: float): uint32 = uint32(clamp(v / a + 0.5, 0.0, 255.0))

proc enlarged(b: Bitmap; size: int): Bitmap =
  ## (`b` made `size` pixels on its longer side, each new pixel blended from
  ## the four around it -- weighed by their alpha, so the transparent edge
  ## does not darken the picture)
  let k = size / max(b.w, b.h)
  let w = max(1, int(b.w.float * k + 0.5))
  let h = max(1, int(b.h.float * k + 0.5))
  result = newBitmap(w, h)
  for y in 0 ..< h:
    let fy = clamp((y.float + 0.5) / k - 0.5, 0.0, float(b.h - 1))
    let y0 = int(fy)
    let y1 = min(y0 + 1, b.h - 1)
    let ty = fy - y0.float
    for x in 0 ..< w:
      let fx = clamp((x.float + 0.5) / k - 0.5, 0.0, float(b.w - 1))
      let x0 = int(fx)
      let x1 = min(x0 + 1, b.w - 1)
      let tx = fx - x0.float
      var a, r, g, bl = 0.0
      for (sx, sy, wt) in [(x0, y0, (1 - tx) * (1 - ty)), (x1, y0, tx * (1 - ty)),
                           (x0, y1, (1 - tx) * ty), (x1, y1, tx * ty)]:
        let p = b.px[sy * b.w + sx]
        let pa = float(p shr 24) * wt
        a += pa
        r += float((p shr 16) and 255) * pa
        g += float((p shr 8) and 255) * pa
        bl += float(p and 255) * pa
      if a > 0:
        result.px[y * w + x] = (uint32(min(a + 0.5, 255.0)) shl 24) or (channel(r, a) shl 16) or
                               (channel(g, a) shl 8) or channel(bl, a)
  result.changed()

proc iconPng(file: string): string =
  ## The icon at 256 x 256: made smaller or larger, centered on a
  ## transparent square.
  let src = decodePng(readFile(file))
  if src == nil or src.w <= 0: quit "appimage: cannot read " & file
  let b = if src.w > IconSize or src.h > IconSize: thumbnail(src, IconSize, IconSize)
          elif max(src.w, src.h) < IconSize: enlarged(src, IconSize)
          else: src
  let sq = newBitmap(IconSize, IconSize)
  let ox = (IconSize - b.w) div 2
  let oy = (IconSize - b.h) div 2
  for y in 0 ..< b.h:
    for x in 0 ..< b.w: sq.px[(y + oy) * IconSize + x + ox] = b.px[y * b.w + x]
  encodePng(sq, level = 9)

proc categoriesFor(name: string): string =
  let n = name.toLowerAscii
  if "photo" in n or "paint" in n or "image" in n or "draw" in n: "Graphics;"
  elif "file" in n: "Utility;FileManager;"
  else: "Utility;"

proc main() =
  if paramCount() < 5:
    quit "usage: appimage program \"Name\" version icon.png out.AppImage [\"Categories;\"]"
  let program = paramStr(1)
  let name = paramStr(2)
  let version = paramStr(3)
  let icon = paramStr(4)
  let outFile = absolutePath(paramStr(5))
  var categories = if paramCount() >= 6: paramStr(6) else: categoriesFor(name)
  if not categories.endsWith(";"): categories.add ';'
  let arch = elfArch(program)
  if arch.len == 0: quit "appimage: " & program & " is not a Linux program (ELF)"
  let id = program.extractFilename
  # (the window's WM_CLASS: the program's name with a capital, see the X11
  # driver -- what a taskbar matches the menu entry by)
  var wmClass = id
  wmClass[0] = wmClass[0].toUpperAscii

  # ---- the AppDir
  let appDir = outFile.changeFileExt("AppDir")
  removeDir(appDir)
  createDir(appDir / "usr" / "bin")
  copyFileWithPermissions(program, appDir / "usr" / "bin" / id)
  writeFile(appDir / "AppRun",
    "#!/bin/sh\n" &
    "# (the AppImage's entry: the program in usr/bin, given what the AppImage was)\n" &
    "HERE=\"$(dirname \"$(readlink -f \"$0\")\")\"\n" &
    "exec \"$HERE/usr/bin/" & id & "\" \"$@\"\n")
  setFilePermissions(appDir / "AppRun", {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead,
                     fpGroupExec, fpOthersRead, fpOthersExec})
  writeFile(appDir / id & ".desktop",
    "[Desktop Entry]\n" &
    "Type=Application\n" &
    "Name=" & name & "\n" &
    "Exec=" & id & " %F\n" &
    "Icon=" & id & "\n" &
    "Categories=" & categories & "\n" &
    "Terminal=false\n" &
    "StartupWMClass=" & wmClass & "\n" &
    "X-AppImage-Version=" & version & "\n")
  let png = iconPng(icon)
  writeFile(appDir / id & ".png", png)
  writeFile(appDir / ".DirIcon", png)
  let hicolor = appDir / "usr" / "share" / "icons" / "hicolor" / "256x256" / "apps"
  createDir(hicolor)
  writeFile(hicolor / id & ".png", png)

  # ---- appimagetool and the runtime, from the cache
  let cache = cacheDir()
  var tool = findExe("appimagetool")
  if tool.len == 0: tool = unpackedTool(cache)
  let runtime = cache / ("runtime-" & arch)
  if tool.len == 0 or not download(RuntimeUrl % arch, runtime):
    let tarball = outFile.changeFileExt("AppDir.tar.gz")
    if execCmd(quoteShellCommand(["tar", "-C", appDir.parentDir, "-czf", tarball,
                                  appDir.extractFilename])) != 0:
      quit "appimage: tar failed"
    echo "appimage: NO AppImage made (appimagetool or its runtime could not be had);"
    echo "  the AppDir is ", appDir, " and packed as ", tarball
    echo "  (appimagetool ", appDir, " ", outFile, " makes the AppImage later)"
    return

  # ---- packed
  removeFile(outFile)
  putEnv("APPIMAGE_EXTRACT_AND_RUN", "1")   # (no FUSE needed to run appimagetool)
  putEnv("ARCH", arch)
  putEnv("VERSION", version)
  let code = execCmd(quoteShellCommand([tool, "--no-appstream", "--runtime-file", runtime,
                                        appDir, outFile]))
  if code != 0 or not fileExists(outFile): quit "appimage: appimagetool failed"
  removeDir(appDir)
  echo "wrote ", outFile
  let glibc = glibcNeeded(program)
  if glibc.len > 0: echo "  (it runs where glibc is ", glibc, " or later)"

main()
