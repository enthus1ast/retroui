## How long painting takes: strokes of brushes from 20 to 5000 pixels on a
## 6000 x 4000 layer, and how much memory a stroke takes.
##
##   nim c -r -d:release -d:useMalloc tests/bench_paint.nim

import std/[strutils, monotimes, times, math]
import retroui/[photo, photopaint]

proc ms(t: MonoTime): float = (getMonoTime() - t).inMicroseconds.float / 1000

let d = newDoc(6000, 4000)
d.markAll()
d.updateComposite()
echo "memory at the start: ", memoryUsed() div (1024 * 1024), " MB"

proc stroke(dia, hardness: int; tool = tkBrush; name = "") =
  var tip = BrushTip(diameter: dia, hardness: hardness, spacing: 25, roundness: 100)
  var o = PaintOpts(tool: tool, color: 0xFF2040C0'u32, bg: 0xFFFFFFFF'u32, opacity: 100)
  d.beginStep("Paint")
  let t = getMonoTime()
  var s = d.beginStroke(o, tip, 500, 2000)
  s.startStroke()
  # (a stroke 5000 pixels long, in steps a mouse makes)
  for i in 1 .. 250:
    s.strokeTo(500 + i.float * 20, 2000 + sin(i.float / 40) * 1200)
  s.endStroke()
  let took = ms(t)
  d.endStep()
  echo alignLeft((if name.len > 0: name else: $dia & " px " & (if hardness >= 100: "hard" else: "soft")), 22),
       align(formatFloat(took, ffDecimal, 1), 9), " ms  ", align($s.dabs, 6), " dabs  ",
       formatFloat(took * 1000 / max(1, s.dabs).float, ffDecimal, 1), " us a dab  memory ",
       memoryUsed() div (1024 * 1024), " MB"
  d.undo()

for (dia, h) in [(20, 0), (100, 0), (100, 100), (500, 0), (1000, 0), (2500, 0), (5000, 0), (5000, 100)]:
  stroke(dia, h)
stroke(200, 0, tkAirbrush, "200 px airbrush")
stroke(200, 0, tkSmudge, "200 px smudge")
stroke(200, 0, tkBlur, "200 px blur")
stroke(200, 0, tkDodge, "200 px dodge")
