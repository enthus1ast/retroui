## Fuzzes the charts headlessly: every kind of chart with random series
## (NaN, infinities, huge, tiny, negative, empty, ragged), random options,
## random sizes, the mouse moving and clicking over them; and random CSV
## text read as tables.
##
##   nim c -d:release --stackTrace:on --lineTrace:on tests/fuzz/fuzz_charts.nim
##   tests/fuzz/fuzz_charts 20000 7        # rounds, random seed

import std/[random, strutils, os, math]
import retro
import retro/uirelays/input
import ../harness

randomize(if paramCount() >= 2: parseInt(paramStr(2)) else: 7)
let rounds = if paramCount() >= 1: parseInt(paramStr(1)) else: 20000

const specials = [NaN, Inf, -Inf, 0.0, -0.0, 1e308, -1e308, 1e-308, 5e-324, 1.0, -1.0,
                  0.5, 1e15, -1e15, 123456789.123]

proc value(): float =
  case rand(5)
  of 0: sample(specials)
  of 1: float(rand(-100 .. 100))
  of 2: rand(1.0) * pow(10.0, float(rand(-20 .. 20)))
  else: rand(-1000.0 .. 1000.0)

proc values(n: int): seq[float] =
  for _ in 0 ..< n: result.add value()

proc randomSeries(): seq[Series] =
  for k in 0 ..< rand(0 .. 5):
    let n = sample([0, 1, 2, 3, 7, 12, 40, rand(0 .. 300)])
    var s = series(sample(["", "A", "Sales 2026", "مبيعات", "x".repeat(rand(0 .. 80))]), values(n))
    if rand(3) == 0: s.xs = values(rand(0 .. n + 2))
    if rand(3) == 0: s.sizes = values(rand(0 .. n + 2))
    if rand(3) == 0:
      s.opens = values(rand(0 .. n + 2))
      s.highs = values(rand(0 .. n + 2))
      s.lows = values(rand(0 .. n + 2))
    if rand(4) == 0: s.asLine = true
    if rand(5) == 0:
      for _ in 0 ..< rand(0 .. n + 2): s.colors.add color(uint8(rand(255)), uint8(rand(255)), uint8(rand(255)))
    result.add s

proc randomLabels(): seq[string] =
  for _ in 0 ..< sample([0, 1, 3, 12, rand(0 .. 400)]):
    result.add sample(["", "Jan", "a much longer label than fits", "١٢٣", "\xFF\xFE", "😀", "x"])

proc randomOpts(): ChartOpts =
  result.title = sample(["", "Sales", "t".repeat(rand(0 .. 200))])
  result.subtitle = sample(["", "by month"])
  result.legend = LegendAt(rand(ord(high(LegendAt))))
  result.dataLabels = rand(1) == 0
  result.smooth = rand(1) == 0
  result.markers = rand(1) == 0
  result.grid = rand(1) == 0
  if rand(3) == 0: result.lo = value()
  if rand(3) == 0: result.hi = value()
  if rand(3) == 0: result.target = value()
  if rand(4) == 0: result.bands = @[(value(), color(1, 2, 3)), (value(), color(200, 0, 0))]
  result.bins = sample([0, 1, 2, 1000, -5])
  if rand(3) == 0: result.totalAt = @[rand(-2 .. 20), rand(0 .. 3)]
  result.totalLabel = sample(["", "Total"])
  result.hole = sample([0.0, 0.5, 1.0, -1.0, NaN])
  result.format = NumFormat(decimals: sample([-1, 0, 2, 20, -7]), short: rand(1) == 0,
                            percent: rand(4) == 0, prefix: sample(["", "$"]),
                            suffix: sample(["", " OMR"]))
  if rand(3) == 0: result.palette = @businessColors

proc randomCsv(): string =
  const bits = ["a", "1", "1,234.5", "\"", "\"\"", ",", ";", "\t", "\n", "\r\n", "\r",
                "(12)", "$5", "12%", "\xEF\xBB\xBF", "١٢", " ", "x".repeat(70), "\0", "-"]
  for _ in 0 ..< rand(0 .. 400): result.add sample(bits)

fakeDriver()
startApp("fuzz charts", W, H)

var kind = chBar
var labels: seq[string]
var ser: seq[Series]
var opts: ChartOpts
var sizes = (300, 200)
var csvRows = 0

view = proc () =
  discard chart(kind, labels, ser, opts, height = sizes[1], w = sizes[0])
  if rand(5) == 0:
    gauge("g", value(), lo = value(), hi = value(), target = value(), height = sizes[1] div 2)

for round in 1 .. rounds:
  kind = ChartKind(rand(ord(high(ChartKind))))
  labels = randomLabels()
  ser = randomSeries()
  opts = randomOpts()
  sizes = (sample([1, 10, 60, 200, 640, 2000]), sample([0, 1, 30, 120, 300, -1]))
  # the mouse over it, a click, keys
  for _ in 0 ..< rand(0 .. 3):
    let x = rand(0 .. W - 1)
    let y = rand(0 .. H - 1)
    case rand(4)
    of 0: move(x, y)
    of 1:
      down(x, y)
      up(x, y)
    of 2: key(sample([KeyTab, KeyLeft, KeyRight, KeyHome, KeyEnd, KeyEnter]))
    else:
      ui.touch = not ui.touch
  run(1)
  # a CSV table
  let t = parseCsv(randomCsv())
  csvRows += t.rows.len
  for c in 0 ..< min(t.headers.len, 4):
    discard t.column(c)
    discard t.labels(c)
  discard t.numericColumns
  var v: float
  discard toNumber(randomCsv(), v)
  discard fmtValue(value(), opts.format)
  discard niceRange(value(), value(), rand(-3 .. 20))
  if round mod 1000 == 0: echo "round ", round
ui.touch = false
echo "charts fuzz passed (", rounds, " rounds, ", csvRows, " CSV rows)"
