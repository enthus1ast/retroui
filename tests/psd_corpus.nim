## How close Retro Photo comes to Photoshop on a folder of PSD/PSB files:
## each is opened, its layers drawn by our engine, and the result compared
## with the merged picture Photoshop saved in the file (mean difference,
## 0..255 a channel, and the share of pixels off by more than 16).
##
##   nim c -r -d:release tests/psd_corpus.nim /path/to/psd_files [--list]

import std/[os, strutils, algorithm, monotimes, times]
import retro/[photo, psd, photofiles]

let dir = if paramCount() >= 1: paramStr(1) else: "/tmp/psdtools/tests/psd_files"
let list = "--list" in commandLineParams()
var files: seq[string]
for f in walkDirRec(dir):
  if f.toLowerAscii.endsWith(".psd") or f.toLowerAscii.endsWith(".psb"): files.add f
files.sort()

var opened, failed, compared, close, near: int
var worst: seq[(float, string)]
let t0 = getMonoTime()
for f in files:
  var doc: Doc
  var p: PsdDoc
  try:
    let data = readFile(f)
    p = readPsd(data)
    doc = docOfPsd(p, f.splitFile.name)
    inc opened
  except CatchableError as e:
    inc failed
    if list: echo "FAIL ", f.extractFilename, ": ", e.msg
    continue
  if p.composite.len != p.w * p.h or doc.w != p.w or doc.h != p.h or p.layers.len == 0: continue
  # (files whose merged picture is blank or white: saved without one)
  var blank = true
  for px in p.composite:
    if px != 0xFFFFFFFF'u32 and px != 0'u32:
      blank = false
      break
  if blank: continue
  doc.updateComposite()
  var sum = 0.0
  var off = 0
  let n = p.w * p.h
  for i in 0 ..< n:
    let a = p.composite[i]
    let b = doc.compPtr[i]
    # (on white: what is transparent compared as it shows)
    proc onWhite(c: uint32; k: int): int =
      let al = int(c shr 24)
      let v = int((c shr (16 - 8 * k)) and 255)
      (v * al + 255 * (255 - al)) div 255
    var m = 0
    for k in 0 .. 2:
      # (Photoshop keeps its merged picture's colors matted on white)
      let d = abs(int((a shr (16 - 8 * k)) and 255) - onWhite(b, k))
      sum += d.float
      m = max(m, d)
    if m > 16: inc off
  inc compared
  let mean = sum / (3 * n).float
  let share = off / n
  if mean < 2 and share < 0.02: inc close
  elif mean < 8: inc near
  worst.add (mean, f.parentDir.extractFilename & "/" & f.extractFilename & " (" & $p.w & "x" & $p.h & ", " & $p.layers.len & " layers, " &
             formatFloat(share * 100, ffDecimal, 1) & "% off)")
worst.sort(proc (a, b: (float, string)): int = cmp(b[0], a[0]))
echo files.len, " files: ", opened, " opened, ", failed, " could not be read"
echo compared, " compared with Photoshop's merged picture: ", close, " the same (mean < 2), ",
     near, " near (mean < 8), ", compared - close - near, " different"
echo "in ", (getMonoTime() - t0).inMilliseconds, " ms"
if list:
  for (m, name) in worst[0 ..< min((if "--all" in commandLineParams(): worst.len else: 25), worst.len)]:
    echo formatFloat(m, ffDecimal, 1).align(6), "  ", name
