## Tests of the work shared among the cores (retroui/parallel).

import std/[atomics]
import retroui/parallel

block everyPieceOnce:
  for n in [0, 1, 2, 3, 7, 100, 1001, 100_000]:
    var hits = newSeq[int32](n)
    let p = cast[ptr UncheckedArray[int32]](if n > 0: addr hits[0] else: nil)
    parallelFor(n, proc (lo, hi: int) =
      for i in lo ..< hi: inc p[i])
    for i in 0 ..< n: doAssert hits[i] == 1, "piece " & $i & " of " & $n

block rows:
  var img = newSeq[int](640 * 480)
  let p = cast[ptr UncheckedArray[int]](addr img[0])
  parallelRows(480, y):
    for x in 0 ..< 640: p[y * 640 + x] = y * 1000 + x
  for y in 0 ..< 480:
    for x in 0 ..< 640: doAssert img[y * 640 + x] == y * 1000 + x

block nested:
  # a parallelFor inside a piece runs on the spot
  var total: Atomic[int]
  parallelFor(64, proc (lo, hi: int) =
    for i in lo ..< hi:
      parallelFor(10, proc (a, b: int) =
        discard total.fetchAdd(b - a)))
  doAssert total.load == 640

block manyJobs:
  # one job after another, quickly: none of them sees the other's pieces
  for k in 1 .. 2000:
    var s: Atomic[int]
    parallelFor(k mod 37 + 1, proc (lo, hi: int) =
      for i in lo ..< hi: discard s.fetchAdd(i + 1))
    let n = k mod 37 + 1
    doAssert s.load == n * (n + 1) div 2, $k

block failing:
  var raised = false
  try:
    parallelFor(1000, proc (lo, hi: int) =
      if lo == 0: raise newException(IOError, "no"))
  except ValueError: raised = true
  doAssert raised
  # and the pool still works
  var s: Atomic[int]
  parallelFor(100, proc (lo, hi: int) = discard s.fetchAdd(hi - lo))
  doAssert s.load == 100

echo "parallel: all passed (", threadCount(), " threads)"
