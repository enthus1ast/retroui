# Retro Designer's modules, and Nim's own parser it reads files with: the
# compiler's sources beside this Nim, else nimble's `compiler` package.
import std/[os, strutils, compilesettings]
switch("path", thisDir() / ".." / "src" / "retrodesigner")
switch("define", "retroDesignerTest")
# (beside this Nim's lib: $PREFIX/lib/nim in Termux, the Nim folder elsewhere)
let nimRoot = querySetting(libPath).parentDir
# (a Nim whose compiler sources come without the dist folders they import --
#  Nim 2.4 as Termux packages it --: the copy `retrokit designer` completed)
let completed = getEnv("XDG_CACHE_HOME", getHomeDir() / ".cache") / "retroui" / ("nim-" & NimVersion)
if fileExists(nimRoot / "compiler" / "nifstreams.nim") and not dirExists(nimRoot / "dist" / "nimony") and
   dirExists(completed / "compiler"):
  switch("path", completed)
elif fileExists(nimRoot / "compiler" / "parser.nim"):
  switch("path", nimRoot)
else:
  let (o, code) = gorgeEx("nimble path compiler")
  if code == 0:
    for l in o.splitLines:
      let d = l.strip
      if d.len > 0 and fileExists(d / "compiler" / "parser.nim"): switch("path", d)
      elif d.len > 0 and fileExists(d / "parser.nim"): switch("path", d.parentDir)
