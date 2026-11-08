# Retro Designer's modules, and Nim's own parser it reads files with: the
# compiler's sources beside this Nim, else nimble's `compiler` package.
import std/[os, strutils]
switch("path", thisDir() / ".." / "src" / "retrodesigner")
switch("define", "retroDesignerTest")
let nimRoot = getCurrentCompilerExe().parentDir.parentDir
if fileExists(nimRoot / "compiler" / "parser.nim"):
  switch("path", nimRoot)
else:
  let (o, code) = gorgeEx("nimble path compiler")
  if code == 0:
    for l in o.splitLines:
      let d = l.strip
      if d.len > 0 and fileExists(d / "compiler" / "parser.nim"): switch("path", d)
      elif d.len > 0 and fileExists(d / "parser.nim"): switch("path", d.parentDir)
