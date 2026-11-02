## Feeds damaged and random models to the OBJ and STL loaders, and draws
## what they accept: nothing may fail other than with `ValueError`.
##
##   nim c -r -d:release --stackTrace:on --lineTrace:on tests/fuzz/fuzz_view3d.nim 20000

import std/[os, random, strutils, math]
import retro/gfx
import retro/view3d

let dir = currentSourcePath().parentDir.parentDir / "data" / "3d"
var seeds: seq[string]
for f in ["cube.obj", "pyramid.obj", "cube_ascii.stl", "cube_bin.stl"]:
  seeds.add readFile(dir / f)
let rounds = if paramCount() >= 1: parseInt(paramStr(1)) else: 20000
var r = initRand(20261027)
var accepted, refused = 0

proc mutate(s: string): string =
  result = s
  for _ in 0 .. r.rand(6):
    if result.len == 0: result.add char(r.rand(255))
    case r.rand(9)
    of 0, 1: result[r.rand(result.high)] = char(r.rand(255))             # a byte
    of 2: result[r.rand(result.high)] = "0123456789-+. /\nefvn"[r.rand(19)]
    of 3: result.insert($r.rand(-100 .. 100), r.rand(result.len))
    of 4:
      let a = r.rand(result.high)
      result.delete(a .. min(result.high, a + r.rand(20)))
    of 5: result.insert(["nan", "inf", "-1e39", "1e400", "-0", "99999999999"][r.rand(5)],
                        r.rand(result.len))
    of 6: result.insert("\nf " & $r.rand(-9 .. 9) & " " & $r.rand(-9 .. 9) & "/" &
                        $r.rand(-3 .. 3) & "/" & $r.rand(-3 .. 3) & " " & $r.rand(-9 .. 9) & "\n",
                        r.rand(result.len))
    of 7:
      let b = seeds[r.rand(seeds.high)]
      let a = r.rand(b.high)
      result.insert(b[a .. min(b.high, a + r.rand(200))], r.rand(result.len))
    of 8:
      # a binary STL whose count says something else
      if result.len >= 84: result[80 + r.rand(3)] = char(r.rand(255))
    else: result.setLen(r.rand(result.len))

proc randomText(): string =
  for _ in 0 .. r.rand(30):
    case r.rand(4)
    of 0: result.add "v " & $r.rand(-1e3 .. 1e3) & " " & $r.rand(-1e3 .. 1e3) & " " &
                     $r.rand(-1e3 .. 1e3) & "\n"
    of 1: result.add "vn 0 " & $r.rand(1.0) & " 1\n"
    of 2: result.add "f " & $r.rand(-12 .. 12) & " " & $r.rand(-12 .. 12) & " " &
                     $r.rand(-12 .. 12) & "\n"
    of 3: result.add "vertex " & $r.rand(10.0) & " 1 2\n"
    else: result.add "facet normal 0 0 1\nendfacet\n"

proc tryOne(data: string) =
  for kind in 0 .. 1:
    var m: Mesh3
    try:
      m = if kind == 0: loadObj(data) else: loadStl(data)
    except ValueError:
      inc refused
      continue
    inc accepted
    # what was accepted is sound: indices in range, points finite
    for t in m.tris:
      for k in t: doAssert k >= 0 and k < m.verts.len
    for v in m.verts: doAssert v.x == v.x and v.y == v.y and v.z == v.z
    if m.smooth: doAssert m.normals.len == m.verts.len
    # and it draws
    var scene = Scene3()
    m.edges = r.rand(1) == 0
    m.twoSided = r.rand(2) == 0
    scene.wireframe = r.rand(5) == 0
    discard scene.add m
    var cam = camera3(yaw = r.rand(360.0), pitch = r.rand(-80.0 .. 80.0))
    fitView(scene, cam)
    if r.rand(3) == 0: cam.distance = r.rand(1e-3 .. 1e3).float32
    let b = render3d(scene, cam, 1 + r.rand(64), 1 + r.rand(48))
    doAssert b.px.len == b.w * b.h

for i in 0 ..< rounds:
  let data = case r.rand(3)
             of 0: randomText()
             of 1:
               var s = newString(r.rand(400))
               for c in s.mitems: c = char(r.rand(255))
               s
             else: mutate(seeds[r.rand(seeds.high)])
  tryOne(data)
  if i mod 5000 == 0 and i > 0: echo "round ", i

# shapes with odd sizes draw too
for i in 0 ..< 300:
  var scene = Scene3()
  let k = r.rand(-1e6 .. 1e6)
  scene.add sphere(k, segments = r.rand(-5 .. 40), rings = r.rand(-5 .. 30))
  scene.add box(r.rand(-10.0 .. 10.0), 0, r.rand(1e9))
  scene.add cone(r.rand(3.0), r.rand(-3.0 .. 3.0), segments = r.rand(0 .. 50))
  scene.addGrid(r.rand(-5.0 .. 5.0), r.rand(-3 .. 30))
  var cam = camera3(yaw = r.rand(720.0), pitch = r.rand(-200.0 .. 200.0),
                    distance = r.rand(-1.0 .. 100.0), fov = r.rand(-10.0 .. 400.0))
  if r.rand(1) == 0: fitView(scene, cam)
  discard render3d(scene, cam, r.rand(-5 .. 80), r.rand(-5 .. 60))

echo "view3d fuzz passed: ", rounds, " rounds, ", accepted, " models accepted, ",
     refused, " refused"
