## The charts (retro/charts): numbers, axes, CSV tables, every kind of
## chart with good and bad data, and the mouse, fingers and keys on them.

import std/[math, os, strutils, times]
import retro
import retro/uirelays/input
import harness

proc px(x, y: int): uint32 = pixels[y * W + x] and 0xFFFFFF'u32

proc count(r: Rect; c: uint32): int =
  for y in max(0, r.y) ..< min(H, r.y + r.h):
    for x in max(0, r.x) ..< min(W, r.x + r.w):
      if px(x, y) == c: inc result

# ---- numbers -----------------------------------------------------------------------------------

block numbers:
  doAssert compact(1260) == "1.3K" and compact(25_400) == "25K" and compact(2_500_000) == "2.5M"
  doAssert compact(NaN) == "-" and compact(Inf) == "inf"
  doAssert fmtValue(1234.5) == "1,234.50"
  doAssert fmtValue(1234) == "1,234"
  doAssert fmtValue(1234.5, NumFormat(prefix: "$", decimals: 0)) == "$1,235"
  doAssert fmtValue(0.256, NumFormat(percent: true, decimals: 1)) == "25.6%"
  doAssert fmtValue(2_500_000, NumFormat(short: true)) == "2.5M"
  doAssert fmtValue(3_000, NumFormat(short: true, suffix: " OMR")) == "3K OMR"
  doAssert fmtValue(-1500, NumFormat(short: true)) == "-1.5K"
  doAssert fmtValue(NaN) == "-" and fmtValue(Inf) == "inf" and fmtValue(-Inf) == "-inf"
  doAssert fmtValue(1e20).contains("e+")
  let (a, b, s) = niceRange(3, 97)
  doAssert a == 0 and b == 100 and s == 20, $(a, b, s)
  let (c, d, t) = niceRange(-0.3, 0.7, 5)
  doAssert c <= -0.3 and d >= 0.7 and t in [0.1, 0.2, 0.25, 0.5], $(c, d, t)
  doAssert niceRange(5, 5).hi > niceRange(5, 5).lo
  doAssert niceRange(NaN, NaN) == (0.0, 1.0, 0.2)
  let big = niceRange(-1e300, 1e300)
  doAssert big.lo < big.hi and big.step > 0
  var v: float
  doAssert toNumber("1,234.50", v) and v == 1234.5
  doAssert toNumber("$1,234", v) and v == 1234
  doAssert toNumber("(450)", v) and v == -450
  doAssert toNumber("1.234,5", v) and v == 1234.5
  doAssert toNumber("12,5", v) and v == 12.5
  doAssert toNumber("12%", v) and v == 12
  doAssert toNumber(" 7 ", v) and v == 7
  doAssert toNumber("١٢٣", v) and v == 123, "Arabic-Indic digits"
  doAssert toNumber("−5", v) and v == -5, "a Unicode minus"
  doAssert not toNumber("abc", v) and not toNumber("", v) and not toNumber("-", v)

# ---- CSV -----------------------------------------------------------------------------------------

block csv:
  let t = parseCsv("\xEF\xBB\xBFMonth,Sales,\"Note, with comma\"\r\nJan,\"1,200\",\"say \"\"hi\"\"\"\r\nFeb,900,\"two\nlines\"\nMar,,x\n")
  doAssert t.headers == @["Month", "Sales", "Note, with comma"], $t.headers
  doAssert t.rows.len == 3
  doAssert t.cell(0, 2) == "say \"hi\"" and t.cell(1, 2) == "two\nlines"
  let s = t.column("sales")
  doAssert s.len == 3 and s[0] == 1200 and s[1] == 900 and s[2] != s[2], $s
  doAssert t.labels("Month") == @["Jan", "Feb", "Mar"]
  doAssert t.numericColumns == @[1]
  doAssert t.column("nothing").len == 0 and t.cell(99, 99) == ""
  let semi = parseCsv("a;b\n1,5;2\n")
  doAssert semi.headers == @["a", "b"] and semi.column("a") == @[1.5]
  let tabs = parseCsv("x\ty\n1\t2\n")
  doAssert tabs.column("y") == @[2.0]
  let noHead = parseCsv("1,2,3\n4,5,6\n")
  doAssert noHead.headers == @["Column 1", "Column 2", "Column 3"] and noHead.rows.len == 2
  let ragged = parseCsv("a,b\n1\n1,2,3\n")
  doAssert ragged.headers.len == 3 and ragged.cell(0, 1) == ""
  doAssert parseCsv("").rows.len == 0
  doAssert readCsv("/no/such/file.csv").error.len > 0
  let path = getTempDir() / "retro-charts-test.csv"
  writeFile(path, "k,v\na,1\nb,2\n")
  doAssert readCsv(path).column("v") == @[1.0, 2.0]
  removeFile(path)

block sampleFiles:
  let dir = currentSourcePath().parentDir / "data" / "charts"
  let sales = readCsv(dir / "sales.csv")
  doAssert sales.error == "" and sales.headers == @["Month", "2025", "2026", "Change"]
  doAssert sales.column("2026")[0] == 1350 and sales.labels("Month")[11] == "Dec"
  let reg = readCsv(dir / "regions-semicolon.csv")
  doAssert reg.headers.len == 5 and reg.column("Q1") == @[120.5, 80, 45, 30], $reg.column("Q1")
  doAssert reg.labels("Region")[3] == "West; coast"
  let st = readCsv(dir / "stock-ohlc.csv")
  let s = tableSeries(st, chCandle, [1, 2, 3, 4])
  doAssert s.len == 1 and s[0].opens.len == 6 and s[0].values[0] == 102.5
  let pipe = readCsv(dir / "pipeline.tsv")
  doAssert pipe.column("Value (OMR)")[4] == 148500 and pipe.numericColumns == @[1, 2]

# ---- every chart, with good and bad data ---------------------------------------------------------------

fakeDriver()
startApp("charts", W, H)

let labels = @["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
let datasets = @[
  ("normal", @[series("2025", [12.0, 15, 14, 18, 21, 25]), series("2026", [14.0, 17, 19, 22, 20, 28])]),
  ("empty", newSeq[Series]()),
  ("no values", @[series("x", [])]),
  ("one", @[series("x", [5.0])]),
  ("negative", @[series("x", [-5.0, -2, 3, -8, 0, 4]), series("y", [1.0, -1, 2, -2, 3, -3])]),
  ("nan", @[series("x", [NaN, 3, NaN, Inf, -Inf, 2])]),
  ("huge", @[series("x", [1e308, -1e308, 1e300, 5, 0, 1e-300])]),
  ("zeros", @[series("x", [0.0, 0, 0, 0, 0, 0])])]

block everyKindDraws:
  var bubbles = series("b", [1.0, 2, 3])
  bubbles.xs = @[1.0, NaN, 3]
  bubbles.sizes = @[10.0, -5, Inf]
  for kind in ChartKind:
    for (name, data) in datasets:
      var ser = data
      if kind in {chScatter, chBubble}: ser.add bubbles
      if kind == chCandle:
        ser = @[ohlcSeries("p", [1.0, 2, NaN], [3.0, Inf, 2], [0.5, 1, 1], [2.0, 1.5, 3])]
      for w in [160, 640]:
        view = proc () =
          discard chart(name, kind, labels, ser, height = 200, w = w,
                        opts = ChartOpts(dataLabels: true, smooth: name == "normal",
                                         totalAt: @[0], target: 20, key: name & $w))
        run(2)
  # options: ranges, formats, palettes, explicit legends
  view = proc () =
    discard chart("opts", chBar, labels, datasets[0][1], height = 200,
                  opts = ChartOpts(lo: -10, hi: 50, legend: laBottom, palette: @businessColors,
                                   format: NumFormat(prefix: "$", short: true), xTitle: "Month",
                                   yTitle: "Sales", subtitle: "2025 and 2026"))
    discard chart("h", chHistogram, [], [series("v", [1.0, 1, 2, 3, 5, 8, 13, 21])], height = 150,
                  opts = ChartOpts(bins: 500))
    gauge("g", NaN, hi = NaN)
    gauge("g2", 1e300, lo = 5, hi = 1)
  run(2)
  # the charts of before
  view = proc () =
    barChart([3.0, 5, 2], ["a", "b", "c"], "Bars", w = 200, h = 120)
    lineChart([@[1.0, 3, 2], @[2.0, 1, 4]], names = ["x", "y"], w = 200, h = 120)
    pieChart([1.0, 1, 2], ["p", "q", "r"], w = 200, h = 120)
    barChart([], [], "none")
    pieChart([0.0, -1], [], "none")
  run(2)

# ---- the mouse, fingers and keys -------------------------------------------------------------------------

block hoverClickLegend:
  var ev: ChartEvent
  var r: Rect
  var clicks = 0
  var clickedOn: ChartEvent
  view = proc () =
    let e = chart("Sales", chBar, ["a", "b", "c"], [series("One", [10.0, 20, 30]),
                  series("Two", [5.0, 15, 25])], height = 300, w = 600,
                  opts = ChartOpts(legend: laRight))
    r = ui.lastRect
    if e.clicked:
      inc clicks
      clickedOn = e
    if e.clicked or e.hidden >= 0 or e.index >= 0: ev = e
  run(3)
  let blue = 0x0000FF'u32
  doAssert count(r, blue) > 500, "the first series' bars are drawn"
  # the mouse over a bar of the first series shows its tooltip
  var bx, by = -1
  for y in countdown(r.y + r.h - 40, r.y + 40):
    for x in r.x + 40 ..< r.x + 300:
      if px(x, y) == blue and bx < 0:
        bx = x + 3
        by = y - 3
  doAssert bx > 0
  move(bx, by)
  run(3)
  doAssert ev.index == 0 and ev.series == 0, "the bar under the mouse: " & $ev
  doAssert count(rect(0, 0, W, H), 0xFFFFE1) > 200, "a tooltip"
  # a click reports it
  down(bx, by)
  run()
  up(bx, by)
  run(2)
  doAssert clicks == 1 and clickedOn.index == 0 and clickedOn.series == 0, $clickedOn
  # the legend: a click hides the first series, another shows it again
  var lx, ly = -1   # (right of the bars: the right-most blue)
  for y in r.y ..< r.y + r.h:
    for x in r.x + r.w - 150 ..< r.x + r.w - 4:
      if px(x, y) == blue and x - 2 > lx:
        lx = x - 2
        ly = y + 2
  doAssert lx > 0, "the legend's swatch"
  move(r.x + 5, r.y + 5)
  run()
  down(lx, ly)
  run()
  up(lx, ly)
  run(3)
  doAssert ev.hidden == 0
  doAssert count(rect(r.x, r.y, r.w - 160, r.h), blue) < 50, "hidden"
  down(lx, ly)
  run()
  up(lx, ly)
  run(3)
  doAssert count(rect(r.x, r.y, r.w - 160, r.h), blue) > 500, "shown again"

block touchAndKeys:
  var ev: ChartEvent
  var r: Rect
  ui.touch = true
  view = proc () =
    let e = chart("Share", chPie, ["North", "South", "East"], [series("s", [50.0, 30, 20])],
                  height = 300, w = 400, opts = ChartOpts(legend: laNone))
    r = ui.lastRect
    if e.index >= 0 or e.clicked: ev = e
  run(3)
  # a tap on the big slice (right of the middle): its tooltip stays
  let cx = r.x + r.w div 2
  let cy = r.y + r.h div 2 + 8
  queue.add Event(kind: MouseMoveEvent, x: cx + 50, y: cy, fromMouse: false)
  queue.add Event(kind: MouseDownEvent, x: cx + 50, y: cy, button: LeftButton, clicks: 1, fromMouse: false)
  run()
  queue.add Event(kind: MouseUpEvent, x: cx + 50, y: cy, button: LeftButton, fromMouse: false)
  run(3)
  doAssert ev.clicked or ev.index == 0, $ev
  doAssert ev.index == 0, "the slice tapped: " & $ev
  run(3)
  doAssert count(rect(0, 0, W, H), 0xFFFFE1) > 100, "its tooltip stays after the tap"
  ui.touch = false
  # the keys: Tab gives the chart the focus, Right walks the bars
  var entered = ChartEvent(index: -1)
  view = proc () =
    let e = chart("Keys", chLine, ["a", "b", "c", "d"], [series("s", [1.0, 4, 2, 5])],
                  height = 250, w = 400)
    r = ui.lastRect
    if e.index >= 0 or e.clicked: ev = e
    if e.clicked: entered = e
  ev = ChartEvent(index: -1, series: -1)
  move(2, 2)
  run(2)
  key(KeyTab)
  run()
  key(KeyRight)
  run()
  key(KeyRight)
  run(2)
  doAssert ev.index == 2, "Right twice: the third point " & $ev
  key(KeyEnter)
  run()
  doAssert entered.clicked and entered.index == 2, $entered

block savePng:
  var r: Rect
  view = proc () =
    barChart([3.0, 5, 2], ["a", "b", "c"], "Bars", w = 200, h = 120)
    r = ui.lastRect
  run(2)
  let path = getTempDir() / "retro-chart-export.png"
  removeFile(path)
  exportPng(r, path)
  run(5)
  let res = exportResult()
  doAssert res.done and res.ok and fileExists(path), $res
  let b = decodePng(readFile(path))
  doAssert b.w == r.w and b.h == r.h
  var blue = 0
  for p in b.px:
    if (p and 0xFFFFFF'u32) == 0x0000FF: inc blue
  doAssert blue > 100, "the bars are in the picture"
  removeFile(path)

block manyPoints:
  # 100,000 values: drawn in good time (per pixel column only what shows)
  var big: seq[float]
  for i in 0 ..< 100_000: big.add sin(float(i) / 500) * 100 + float(i mod 7)
  view = proc () =
    discard chart("Many", chLine, [], [series("x", big)], height = 200, w = 600)
    discard chart("Many areas", chArea, [], [series("x", big)], height = 200, w = 600)
  let t0 = epochTime()
  run(3)
  let took = epochTime() - t0
  doAssert took < 3.0, "100,000 points took " & $took & " s"

echo "charts tests passed"
