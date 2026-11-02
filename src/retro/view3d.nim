## A small 3D view: scenes of meshes drawn by the kit itself (no GPU, no
## libraries), for product viewers, 3D bar charts and simple scenes.
##
## - `Scene3`: meshes (`box`, `sphere`, `cylinder`, `cone`, `plane`, or
##   loaded with `loadObj` / `loadStl` / `loadModel`), lines (`addGrid`,
##   `addAxes`), labels; `bars3d` makes a 3D bar chart
## - `Camera3`: orbits a target; `fitView` frames the scene
## - `view3d`: the widget -- a drag turns the scene (Shift or Ctrl + drag,
##   or a finger held a moment, moves it), the wheel zooms, arrows, + / -
##   and Home work when it has the focus, the +, - and home buttons in its
##   corner do too; a click picks the mesh under it
## - `render3d`: the same picture into a `Bitmap` (to save as PNG)
##
## Triangles are filled with a z-buffer at the screen's own resolution, lit
## by one light (flat, or smooth with `Mesh3.smooth`), with outlines when
## asked. A frame where nothing changed costs nothing: the picture is drawn
## again only when the scene, the camera or the size changed. After
## changing a mesh's points or triangles in place, call `sceneChanged`.
##
## .. code-block:: nim
##   var scene = Scene3()
##   discard scene.add box(1, 1, 1, color(0, 0, 160))
##   scene.addGrid()
##   var cam = camera3()
##   fitView(scene, cam)
##   app "3D", 800, 600:
##     let ev = view3d(scene, cam)
##     if ev.clicked and ev.picked >= 0: echo scene.meshes[ev.picked].name

import std/[math, tables, strutils, parseutils, os]
import uirelays/input
import gfx, core, widgets, pixelicons, nerdicons

template th: untyped = ui.theme

type
  Vec3* = object
    x*, y*, z*: float32

  Mesh3* = object
    ## Points and the triangles between them (counter-clockwise seen from
    ## outside), placed in the scene by `pos`, `rot` (degrees about x, y,
    ## then z) and `scale`.
    name*: string
    verts*: seq[Vec3]
    tris*: seq[array[3, int32]]
    color*: Color            ## of every triangle (when `colors` is empty)
    colors*: seq[Color]      ## one per triangle
    normals*: seq[Vec3]      ## one per point, for `smooth` (else worked out)
    smooth*: bool            ## shaded smoothly across the triangles
    twoSided*: bool          ## both sides drawn (planes, open surfaces)
    edges*: bool             ## its triangles outlined
    visible*: bool
    pos*, rot*, scale*: Vec3

  Line3* = object
    a*, b*: Vec3
    color*: Color

  Label3* = object
    at*: Vec3
    text*: string
    color*: Color            ## alpha 0: the theme's text color
    bold*: bool

  Scene3* = object
    ## What a `view3d` shows.
    meshes*: seq[Mesh3]
    lines*: seq[Line3]
    labels*: seq[Label3]
    background*: Color       ## alpha 0: a soft gradient in the theme's colors
    ambient*: float32        ## 0..1, how light the side away from the light is
    wireframe*: bool         ## only the edges of the triangles
    version: int

  Camera3* = object
    ## Looks at `target` from `distance` away, turned `yaw` degrees about
    ## the vertical and `pitch` degrees up; `fov` is the vertical angle.
    target*: Vec3
    yaw*, pitch*, distance*, fov*: float32
    home: tuple[set: bool; target: Vec3; yaw, pitch, distance: float32]

  View3DEvent* = object
    ## What happened in a `view3d` this frame.
    clicked*: bool           ## a click or tap that did not turn the scene
    picked*: int             ## ... the mesh under it (-1: none)
    pickedTri*: int          ## ... and its triangle
    hovered*: int            ## the mesh under the mouse now (-1: none; not fingers)
    hoveredTri*: int
    activated*: bool         ## a double click on a mesh (`picked`)
    cameraChanged*: bool     ## turned, moved or zoomed this frame

const
  MaxTriangles* = 2_000_000  ## the most a loaded model may have
  MaxPoints* = 6_000_000
  MaxModelBytes* = 256 * 1024 * 1024

proc vec3*(x, y, z: float): Vec3 {.inline.} = Vec3(x: x.float32, y: y.float32, z: z.float32)
  ## A point (or direction) in 3D.

proc `+`(a, b: Vec3): Vec3 {.inline.} = Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
proc `-`(a, b: Vec3): Vec3 {.inline.} = Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
proc `*`(a: Vec3; k: float32): Vec3 {.inline.} = Vec3(x: a.x * k, y: a.y * k, z: a.z * k)
proc dot(a, b: Vec3): float32 {.inline.} = a.x * b.x + a.y * b.y + a.z * b.z
proc cross(a, b: Vec3): Vec3 {.inline.} =
  Vec3(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x)
proc len(a: Vec3): float32 {.inline.} = sqrt(dot(a, a))
proc unit(a: Vec3): Vec3 {.inline.} =
  let l = len(a)
  if l > 1e-20: a * (1'f32 / l) else: Vec3(y: 1)
proc finite(v: float32): bool {.inline.} = v == v and abs(v) < 1e30
proc finite(v: Vec3): bool {.inline.} = finite(v.x) and finite(v.y) and finite(v.z)

# ---- meshes --------------------------------------------------------------------------------------

proc newMesh*(name = ""; color = color(0, 0, 160)): Mesh3 =
  ## An empty mesh of one color (add its `verts` and `tris`).
  Mesh3(name: name, color: color, visible: true, scale: vec3(1, 1, 1))

proc triangleCount*(m: Mesh3): int = m.tris.len
  ## How many triangles the mesh has.

proc box*(w, h, d: float; color = color(0, 0, 160); name = "box"): Mesh3 =
  ## A box `w` wide (x), `h` high (y) and `d` deep (z), centered.
  result = newMesh(name, color)
  let (x, y, z) = (w.float32 / 2, h.float32 / 2, d.float32 / 2)
  result.verts = @[Vec3(x: -x, y: -y, z: -z), Vec3(x: x, y: -y, z: -z),
                   Vec3(x: x, y: y, z: -z), Vec3(x: -x, y: y, z: -z),
                   Vec3(x: -x, y: -y, z: z), Vec3(x: x, y: -y, z: z),
                   Vec3(x: x, y: y, z: z), Vec3(x: -x, y: y, z: z)]
  result.tris = @[[4'i32, 5, 6], [4'i32, 6, 7],      # front (+z)
                  [1'i32, 0, 3], [1'i32, 3, 2],      # back
                  [5'i32, 1, 2], [5'i32, 2, 6],      # right
                  [0'i32, 4, 7], [0'i32, 7, 3],      # left
                  [7'i32, 6, 2], [7'i32, 2, 3],      # top
                  [0'i32, 1, 5], [0'i32, 5, 4]]      # bottom

proc sphere*(radius: float; color = color(0, 0, 160); segments = 24; rings = 16;
             name = "sphere"): Mesh3 =
  ## A sphere, shaded smoothly.
  result = newMesh(name, color)
  result.smooth = true
  let seg = clamp(segments, 3, 512)
  let rg = clamp(rings, 2, 512)
  for j in 0 .. rg:
    let phi = PI * j.float / rg.float
    for i in 0 .. seg:
      let th2 = 2 * PI * i.float / seg.float
      let n = vec3(sin(phi) * sin(th2), cos(phi), sin(phi) * cos(th2))
      result.verts.add n * radius.float32
      result.normals.add n
  let row = seg + 1
  for j in 0 ..< rg:
    for i in 0 ..< seg:
      let a = int32(j * row + i)
      let b = int32((j + 1) * row + i)
      if j > 0: result.tris.add [a, b, a + 1]
      if j < rg - 1: result.tris.add [a + 1, b, b + 1]

proc lathe(name: string; color: Color; seg: int; bottomR, topR, h: float32;
           caps: bool): Mesh3 =
  ## A cylinder or cone about the y axis, from y = -h/2 to h/2.
  result = newMesh(name, color)
  result.smooth = true
  let seg = clamp(seg, 3, 1024)
  let y0 = -h / 2
  let y1 = h / 2
  let slope = (bottomR - topR) / max(1e-6'f32, h)
  for i in 0 .. seg:
    let a = 2 * PI * i.float / seg.float
    let (s, c) = (sin(a).float32, cos(a).float32)
    let n = unit(Vec3(x: s, y: slope, z: c))
    result.verts.add Vec3(x: s * bottomR, y: y0, z: c * bottomR)
    result.normals.add n
    result.verts.add Vec3(x: s * topR, y: y1, z: c * topR)
    result.normals.add n
  for i in 0 ..< seg:
    let a = int32(2 * i)
    result.tris.add [a, a + 2, a + 1]
    result.tris.add [a + 1, a + 2, a + 3]
  if caps:
    for (y, r, up) in [(y0, bottomR, false), (y1, topR, true)]:
      if r <= 0: continue
      let center = int32(result.verts.len)
      let n = Vec3(y: if up: 1 else: -1)
      result.verts.add Vec3(y: y)
      result.normals.add n
      for i in 0 .. seg:
        let a = 2 * PI * i.float / seg.float
        result.verts.add Vec3(x: sin(a).float32 * r, y: y, z: cos(a).float32 * r)
        result.normals.add n
      for i in 0 ..< seg:
        let a = center + 1 + int32(i)
        if up: result.tris.add [center, a, a + 1]
        else: result.tris.add [center, a + 1, a]

proc cylinder*(radius, height: float; color = color(0, 0, 160); segments = 24;
               name = "cylinder"): Mesh3 =
  ## A cylinder standing on the y axis, centered.
  lathe(name, color, segments, radius.float32, radius.float32, height.float32, true)

proc cone*(radius, height: float; color = color(0, 0, 160); segments = 24;
           name = "cone"): Mesh3 =
  ## A cone pointing up the y axis, centered.
  lathe(name, color, segments, radius.float32, 0, height.float32, true)

proc plane*(w, d: float; color = color(192, 192, 192); name = "plane"): Mesh3 =
  ## A flat rectangle in the x-z plane (seen from both sides).
  result = newMesh(name, color)
  result.twoSided = true
  let (x, z) = (w.float32 / 2, d.float32 / 2)
  result.verts = @[Vec3(x: -x, z: z), Vec3(x: x, z: z), Vec3(x: x, z: -z), Vec3(x: -x, z: -z)]
  result.tris = @[[0'i32, 1, 2], [0'i32, 2, 3]]

proc add*(scene: var Scene3; m: Mesh3): int {.discardable.} =
  ## Adds `m`; its index in `scene.meshes`.
  scene.meshes.add m
  inc scene.version
  scene.meshes.high

proc addLine*(scene: var Scene3; a, b: Vec3; color = color(128, 128, 128)) =
  ## Adds a line from `a` to `b`.
  scene.lines.add Line3(a: a, b: b, color: color)
  inc scene.version

proc addLabel*(scene: var Scene3; at: Vec3; text: string; color = Color(); bold = false) =
  ## Text shown at the point `at` (it keeps facing the screen).
  scene.labels.add Label3(at: at, text: text, color: color, bold: bold)
  inc scene.version

proc addGrid*(scene: var Scene3; size = 10.0; divisions = 10; y = 0.0;
              color = color(160, 160, 160)) =
  ## A square grid of lines in the x-z plane, `size` across.
  let n = clamp(divisions, 1, 1000)
  let h = size / 2
  for i in 0 .. n:
    let t = -h + size * i.float / n.float
    scene.lines.add Line3(a: vec3(t, y, -h), b: vec3(t, y, h), color: color)
    scene.lines.add Line3(a: vec3(-h, y, t), b: vec3(h, y, t), color: color)
  inc scene.version

proc addAxes*(scene: var Scene3; length = 1.0) =
  ## The x (red), y (green) and z (blue) axes from the origin.
  scene.addLine(vec3(0, 0, 0), vec3(length, 0, 0), color(220, 0, 0))
  scene.addLine(vec3(0, 0, 0), vec3(0, length, 0), color(0, 160, 0))
  scene.addLine(vec3(0, 0, 0), vec3(0, 0, length), color(0, 0, 220))

proc sceneChanged*(scene: var Scene3) =
  ## Call after changing points, triangles or colors in place: the view
  ## draws the scene again.
  inc scene.version

proc centerMesh*(m: var Mesh3; size = 0.0) =
  ## Moves the mesh's points so its middle is at the origin; with `size`,
  ## also scales them so its largest side is `size` long.
  if m.verts.len == 0: return
  var lo = m.verts[0]
  var hi = m.verts[0]
  for v in m.verts:
    lo = Vec3(x: min(lo.x, v.x), y: min(lo.y, v.y), z: min(lo.z, v.z))
    hi = Vec3(x: max(hi.x, v.x), y: max(hi.y, v.y), z: max(hi.z, v.z))
  let c = (lo + hi) * 0.5'f32
  let ext = max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z))
  let k = if size > 0 and ext > 0: size.float32 / ext else: 1'f32
  for v in m.verts.mitems: v = (v - c) * k

# ---- loading models -------------------------------------------------------------------------------

proc fail(msg: string) {.noreturn.} = raise newException(ValueError, msg)

proc skipSpace(s: string; i: var int; lineEnd: int) {.inline.} =
  while i < lineEnd and s[i] in {' ', '\t'}: inc i

proc readFloat(s: string; i: var int; lineEnd: int): float32 =
  skipSpace(s, i, lineEnd)
  var f: float
  if i > lineEnd: fail("a number was expected")
  let n = parseFloat(s.toOpenArray(i, lineEnd - 1), f)
  if n == 0: fail("a number was expected")
  i += n
  if not finite(f.float32) or abs(f) > 1e30: fail("a number that is not finite")
  f.float32

proc loadObj*(data: string; name = "model"): Mesh3 =
  ## A mesh from the text of a Wavefront OBJ file: its `v` points, `vn`
  ## normals and `f` faces (polygons are cut into triangles; negative
  ## indices count back; a point with different normals in different faces
  ## becomes one point per normal, so hard edges stay hard). Other lines
  ## (materials, groups, textures) are skipped. Raises `ValueError` for what
  ## is not a sound OBJ (or is too big: `MaxTriangles`, `MaxPoints`).
  if data.len > MaxModelBytes: fail("the model is too big")
  result = newMesh(name, color(160, 160, 176))
  var points, normals: seq[Vec3]
  var cornerV, cornerN: seq[int32]     # three corners to a triangle
  var allNormals = true
  var i = 0
  var face: seq[tuple[v, n: int32]]
  while i < data.len:
    var e = i
    while e < data.len and data[e] notin {'\n', '\r'}: inc e
    var p = i
    skipSpace(data, p, e)
    if p + 1 < e and data[p] == 'v' and data[p + 1] in {' ', '\t'}:
      p += 2
      let x = readFloat(data, p, e)
      let y = readFloat(data, p, e)
      let z = readFloat(data, p, e)
      if points.len >= MaxPoints: fail("too many points")
      points.add Vec3(x: x, y: y, z: z)
    elif p + 2 < e and data[p] == 'v' and data[p + 1] == 'n' and data[p + 2] in {' ', '\t'}:
      p += 3
      let x = readFloat(data, p, e)
      let y = readFloat(data, p, e)
      let z = readFloat(data, p, e)
      if normals.len >= MaxPoints: fail("too many normals")
      normals.add unit(Vec3(x: x, y: y, z: z))
    elif p + 1 < e and data[p] == 'f' and data[p + 1] in {' ', '\t'}:
      p += 2
      face.setLen(0)
      while true:
        skipSpace(data, p, e)
        if p >= e: break
        var idx: int
        let n = parseInt(data.toOpenArray(p, e - 1), idx)
        if n == 0: fail("a face index was expected")
        p += n
        let np = points.len
        let vi = if idx < 0: np + idx else: idx - 1
        if vi < 0 or vi >= np: fail("a face points to a point that is not there")
        # texture and normal indices: a/b, a/b/c, a//c
        var ni = -1
        if p < e and data[p] == '/':
          inc p
          if p < e and data[p] != '/':
            var t: int
            p += parseInt(data.toOpenArray(p, e - 1), t)
          if p < e and data[p] == '/':
            inc p
            var t: int
            let m = parseInt(data.toOpenArray(p, e - 1), t)
            if m == 0: fail("a normal index was expected")
            p += m
            ni = if t < 0: normals.len + t else: t - 1
            if ni < 0 or ni >= normals.len: fail("a face points to a normal that is not there")
        if ni < 0: allNormals = false
        if face.len >= 4096: fail("a face with too many corners")
        face.add (int32(vi), int32(ni))
        if p < e and data[p] notin {' ', '\t'}: fail("a face is not well formed")
      if face.len < 3: fail("a face with fewer than three corners")
      for k in 1 ..< face.len - 1:
        if cornerV.len >= MaxTriangles * 3: fail("too many triangles")
        for c in [face[0], face[k], face[k + 1]]:
          cornerV.add c.v
          cornerN.add c.n
    i = e
    while i < data.len and data[i] in {'\n', '\r'}: inc i
  if cornerV.len == 0: fail("there are no faces")
  if allNormals and normals.len > 0:
    # one point for each point-and-normal pair used
    var seen = initTable[int64, int32]()
    for k in 0 ..< cornerV.len:
      let key = (cornerV[k].int64 shl 32) or cornerN[k].int64
      var at = seen.getOrDefault(key, -1)
      if at < 0:
        at = int32(result.verts.len)
        seen[key] = at
        result.verts.add points[cornerV[k]]
        result.normals.add normals[cornerN[k]]
      cornerV[k] = at
    result.smooth = true
  else:
    result.verts = move points
  for k in countup(0, cornerV.len - 3, 3):
    result.tris.add [cornerV[k], cornerV[k + 1], cornerV[k + 2]]

proc loadStl*(data: string; name = "model"): Mesh3 =
  ## A mesh from an STL file, binary or text. Raises `ValueError` for what
  ## is not one (or has more than `MaxTriangles`).
  if data.len > MaxModelBytes: fail("the model is too big")
  result = newMesh(name, color(160, 160, 176))
  template addPoint(v: Vec3) =
    result.verts.add v
  var binary = false
  if data.len >= 84:
    let n = uint32(data[80].uint8) or (uint32(data[81].uint8) shl 8) or
            (uint32(data[82].uint8) shl 16) or (uint32(data[83].uint8) shl 24)
    if n.uint64 * 50 + 84 == data.len.uint64: binary = true
  if binary:
    let n = (data.len - 84) div 50
    if n > MaxTriangles: fail("too many triangles")
    if n == 0: fail("there are no triangles")
    result.verts = newSeqOfCap[Vec3](n * 3)
    result.tris = newSeqOfCap[array[3, int32]](n)
    proc f32(s: string; at: int): float32 =
      var u = uint32(s[at].uint8) or (uint32(s[at + 1].uint8) shl 8) or
              (uint32(s[at + 2].uint8) shl 16) or (uint32(s[at + 3].uint8) shl 24)
      cast[float32](u)
    for t in 0 ..< n:
      let base = 84 + t * 50 + 12            # (after the facet's normal)
      for k in 0 .. 2:
        let v = Vec3(x: f32(data, base + k * 12), y: f32(data, base + k * 12 + 4),
                     z: f32(data, base + k * 12 + 8))
        if not finite(v): fail("a point that is not finite")
        addPoint(v)
      let a = int32(t * 3)
      result.tris.add [a, a + 1, a + 2]
    return
  # text: "vertex x y z", three to a facet
  var i = 0
  var inFacet = 0
  while i < data.len:
    var e = i
    while e < data.len and data[e] notin {'\n', '\r'}: inc e
    var p = i
    skipSpace(data, p, e)
    if e - p >= 6 and data[p ..< p + 6] == "vertex":
      p += 6
      let x = readFloat(data, p, e)
      let y = readFloat(data, p, e)
      let z = readFloat(data, p, e)
      if result.verts.len >= MaxTriangles * 3: fail("too many triangles")
      addPoint(Vec3(x: x, y: y, z: z))
      inc inFacet
      if inFacet == 3:
        let a = int32(result.verts.len - 3)
        result.tris.add [a, a + 1, a + 2]
        inFacet = 0
    elif e - p >= 8 and data[p ..< p + 8] == "endfacet":
      if inFacet != 0: fail("a facet without three points")
    i = e
    while i < data.len and data[i] in {'\n', '\r'}: inc i
  if result.tris.len == 0: fail("not an STL model")

proc loadModel*(path: string): Mesh3 =
  ## An OBJ or STL file (by its extension), centered at the origin and
  ## scaled to 2 units across. Raises `ValueError` or `IOError`.
  if getFileSize(path) > MaxModelBytes: fail("the model is too big")
  let data = readFile(path)
  let name = path.extractFilename
  result = if path.toLowerAscii.endsWith(".obj"): loadObj(data, name)
           else: loadStl(data, name)
  centerMesh(result, 2.0)

# ---- 3D bar charts -------------------------------------------------------------------------------

const barColors = [color(0, 0, 192), color(192, 0, 0), color(0, 128, 0),
                   color(208, 144, 0), color(128, 0, 128), color(0, 128, 128),
                   color(96, 96, 96), color(0, 96, 192)]

proc niceNumber(v: float): string =
  if abs(v - round(v)) < 1e-9: $int(round(v))
  else: formatFloat(v, ffDecimal, 2).strip(leading = false, chars = {'0'}).strip(
          leading = false, chars = {'.'})

proc bars3d*(values: openArray[seq[float]]; rowLabels: openArray[string] = [];
             colLabels: openArray[string] = []; colors: openArray[Color] = [];
             showValues = false): Scene3 =
  ## A 3D bar chart: `values[row][col]` stand as bars on a floor, a row of
  ## bars per series (front to back), one color per row (`colors`, else the
  ## kit's), labels along the sides and, with `showValues`, on the bars.
  ## Negative values go down. Pair it with `fitView`.
  var rows = values.len
  var cols = 0
  var hi = 0.0
  for r in values:
    cols = max(cols, r.len)
    for v in r:
      if v == v and abs(v) < 1e300: hi = max(hi, abs(v))
  rows = min(rows, 200)
  cols = min(cols, 200)
  let unitH = if hi > 0: max(2.0, (rows + cols).float * 0.4) / hi else: 1.0
  let x0 = -(cols - 1).float / 2
  let z0 = -(rows - 1).float / 2
  for r in 0 ..< rows:
    let c = if r < colors.len: colors[r] else: barColors[r mod barColors.len]
    for k in 0 ..< min(cols, values[r].len):
      let v = values[r][k]
      if v != v or abs(v) >= 1e300: continue
      let h = max(0.001, abs(v) * unitH)
      var m = box(0.7, h, 0.7, c,
                  name = (if r < rowLabels.len: rowLabels[r] & ", " else: "") &
                         (if k < colLabels.len: colLabels[k] & ": " else: "") & niceNumber(v))
      m.pos = vec3(x0 + k.float, (if v >= 0: h / 2 else: -h / 2), z0 + r.float)
      m.edges = true
      result.add m
      if showValues:
        result.addLabel(vec3(x0 + k.float, (if v >= 0: h + 0.25 else: -h - 0.25), z0 + r.float),
                        niceNumber(v))
  var floor = plane(max(1, cols).float + 0.6, max(1, rows).float + 0.6, color(224, 224, 224), "floor")
  floor.pos = vec3(0, -0.002, 0)
  result.add floor
  for r in 0 ..< rows:
    if r < rowLabels.len:
      result.addLabel(vec3(x0 - 0.6 - 0.12 * rowLabels[r].len.float, 0, z0 + r.float),
                      rowLabels[r], bold = true)
  for k in 0 ..< cols:
    if k < colLabels.len:
      result.addLabel(vec3(x0 + k.float, 0, z0 + rows.float - 0.1), colLabels[k])
  result.ambient = 0.45

# ---- the camera ------------------------------------------------------------------------------------

proc camera3*(yaw = 35.0; pitch = 25.0; distance = 6.0; target = vec3(0, 0, 0);
              fov = 40.0): Camera3 =
  ## A camera looking at `target` (see `Camera3`); `resetView` comes back
  ## to it.
  result = Camera3(yaw: yaw.float32, pitch: pitch.float32, distance: distance.float32,
                   target: target, fov: fov.float32)
  result.home = (true, target, yaw.float32, pitch.float32, distance.float32)

proc resetView*(cam: var Camera3) =
  ## Back to where `camera3` or `fitView` put it.
  if cam.home.set:
    cam.target = cam.home.target
    cam.yaw = cam.home.yaw
    cam.pitch = cam.home.pitch
    cam.distance = cam.home.distance

proc rotation(r: Vec3): array[9, float32] =
  ## The matrix turning by `r` degrees about x, then y, then z.
  let (sx, cx) = (sin(r.x.float * PI / 180).float32, cos(r.x.float * PI / 180).float32)
  let (sy, cy) = (sin(r.y.float * PI / 180).float32, cos(r.y.float * PI / 180).float32)
  let (sz, cz) = (sin(r.z.float * PI / 180).float32, cos(r.z.float * PI / 180).float32)
  # Rz * Ry * Rx
  [cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx,
   sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx,
   -sy, cy * sx, cy * cx]

proc apply(m: array[9, float32]; v: Vec3): Vec3 {.inline.} =
  Vec3(x: m[0] * v.x + m[1] * v.y + m[2] * v.z,
       y: m[3] * v.x + m[4] * v.y + m[5] * v.z,
       z: m[6] * v.x + m[7] * v.y + m[8] * v.z)

proc worldPoint(m: Mesh3; rot: array[9, float32]; v: Vec3): Vec3 {.inline.} =
  apply(rot, Vec3(x: v.x * m.scale.x, y: v.y * m.scale.y, z: v.z * m.scale.z)) + m.pos

proc bounds*(scene: Scene3): tuple[lo, hi: Vec3; empty: bool] =
  ## The box around the visible meshes and the lines.
  result.empty = true
  template take(p: Vec3) =
    if finite(p):
      if result.empty:
        result.lo = p
        result.hi = p
        result.empty = false
      else:
        result.lo = Vec3(x: min(result.lo.x, p.x), y: min(result.lo.y, p.y), z: min(result.lo.z, p.z))
        result.hi = Vec3(x: max(result.hi.x, p.x), y: max(result.hi.y, p.y), z: max(result.hi.z, p.z))
  for m in scene.meshes:
    if not m.visible: continue
    let rot = rotation(m.rot)
    for v in m.verts: take(worldPoint(m, rot, v))
  for l in scene.lines:
    take(l.a)
    take(l.b)

proc fitView*(scene: Scene3; cam: var Camera3) =
  ## Aims the camera at the middle of the scene, far enough to see all of
  ## it; Home (and the home button) come back to this view.
  let b = bounds(scene)
  if b.empty: return
  let c = (b.lo + b.hi) * 0.5'f32
  let radius = max(0.001'f32, len(b.hi - b.lo) * 0.5'f32)
  let half = max(5.0, cam.fov.float) * PI / 360
  cam.target = c
  cam.distance = float32(radius / sin(half) * 1.05)
  cam.home = (true, cam.target, cam.yaw, cam.pitch, cam.distance)

type Basis = object
  eye, right, up, fwd: Vec3

proc basis(cam: Camera3): Basis =
  let yaw = cam.yaw.float * PI / 180
  let pitch = clamp(cam.pitch.float, -89.9, 89.9) * PI / 180
  let dir = vec3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
  result.eye = cam.target + dir * max(1e-4'f32, cam.distance)
  result.fwd = unit(cam.target - result.eye)
  result.right = unit(cross(result.fwd, Vec3(y: 1)))
  result.up = cross(result.right, result.fwd)

proc toView(b: Basis; p: Vec3): Vec3 {.inline.} =
  let d = p - b.eye
  Vec3(x: dot(d, b.right), y: dot(d, b.up), z: dot(d, b.fwd))

# ---- drawing ---------------------------------------------------------------------------------------

type
  SVert = object
    x, y, iz, shade: float32     # screen position, 1/depth, light (0..1)
  RenderCtx = object
    w, h: int
    px: ptr UncheckedArray[uint32]
    z: seq[float32]              # 1/depth of what is drawn (0: nothing)
    focal, near: float32
    view: seq[seq[Vec3]]         # the points of each mesh, seen from the eye
    spheres: seq[tuple[c: Vec3; r: float32]]   # the meshes' bounds, likewise
    labels: seq[tuple[x, y: float32; ok: bool]]

const LightDir = Vec3(x: -0.36, y: 0.55, z: -0.75)   # toward the light, eye space

proc pack(c: Color; k: float32): uint32 {.inline.} =
  let k = clamp(k, 0, 1.2)
  let r = min(255, int(c.r.float32 * k))
  let g = min(255, int(c.g.float32 * k))
  let b = min(255, int(c.b.float32 * k))
  0xFF000000'u32 or (r.uint32 shl 16) or (g.uint32 shl 8) or b.uint32

{.push boundChecks: off, overflowChecks: off, rangeChecks: off.}

proc project(ctx: RenderCtx; v: Vec3; shade: float32): SVert {.inline.} =
  let iz = 1'f32 / v.z
  SVert(x: ctx.w.float32 * 0.5'f32 + v.x * ctx.focal * iz,
        y: ctx.h.float32 * 0.5'f32 - v.y * ctx.focal * iz, iz: iz, shade: shade)

proc fillTri(ctx: var RenderCtx; a0, b0, c0: SVert; col: Color; smooth: bool) =
  var a = a0
  var b = b0
  var c = c0
  var area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  if not (abs(area) > 1e-6'f32) or not (abs(area) < 1e14'f32): return
  if area < 0:
    swap(b, c)
    area = -area
  let fw = ctx.w.float32
  let fh = ctx.h.float32
  let minX = clamp(min(a.x, min(b.x, c.x)), 0, fw)
  let maxX = clamp(max(a.x, max(b.x, c.x)), 0, fw)
  let minY = clamp(min(a.y, min(b.y, c.y)), 0, fh)
  let maxY = clamp(max(a.y, max(b.y, c.y)), 0, fh)
  let x0 = int(minX)
  let x1 = min(ctx.w - 1, int(maxX))
  let y0 = int(minY)
  let y1 = min(ctx.h - 1, int(maxY))
  if x0 > x1 or y0 > y1: return
  let inv = 1'f32 / area
  # edge functions, stepped along x and y
  let e0dx = (b.y - c.y)
  let e1dx = (c.y - a.y)
  let e2dx = (a.y - b.y)
  let e0dy = (c.x - b.x)
  let e1dy = (a.x - c.x)
  let e2dy = (b.x - a.x)
  let px0 = x0.float32 + 0.5'f32
  var py = y0.float32 + 0.5'f32
  let flat = pack(col, a.shade)
  let zp = cast[ptr UncheckedArray[float32]](unsafeAddr ctx.z[0])
  for y in y0 .. y1:
    var w0 = (px0 - b.x) * e0dx + (py - b.y) * e0dy
    var w1 = (px0 - c.x) * e1dx + (py - c.y) * e1dy
    var w2 = (px0 - a.x) * e2dx + (py - a.y) * e2dy
    let row = y * ctx.w
    for x in x0 .. x1:
      if w0 >= 0 and w1 >= 0 and w2 >= 0:
        let l0 = w0 * inv
        let l1 = w1 * inv
        let l2 = 1'f32 - l0 - l1
        let iz = l0 * a.iz + l1 * b.iz + l2 * c.iz
        let i = row + x
        if iz > zp[i]:
          zp[i] = iz
          ctx.px[i] = if smooth: pack(col, l0 * a.shade + l1 * b.shade + l2 * c.shade)
                      else: flat
      w0 += e0dx
      w1 += e1dx
      w2 += e2dx
    py += 1

proc drawLine(ctx: var RenderCtx; a, b: SVert; c: uint32; bias: float32) =
  ## A line with the depth test (`bias`: how far in front it may win).
  if not (finite(a.x) and finite(a.y) and finite(b.x) and finite(b.y)): return
  let dx = b.x - a.x
  let dy = b.y - a.y
  let n = int(min(1e5'f32, max(abs(dx), abs(dy)))) + 1
  let zp = cast[ptr UncheckedArray[float32]](unsafeAddr ctx.z[0])
  for k in 0 .. n:
    let t = k.float32 / n.float32
    let x = a.x + dx * t
    let y = a.y + dy * t
    if x < 0 or y < 0 or x >= ctx.w.float32 or y >= ctx.h.float32: continue
    let i = int(y) * ctx.w + int(x)
    let iz = a.iz + (b.iz - a.iz) * t
    if iz * (1'f32 + bias) >= zp[i]:
      ctx.px[i] = c
      zp[i] = max(zp[i], iz)

{.pop.}

proc clipNear(ctx: RenderCtx; vs: openArray[tuple[p: Vec3; s: float32]];
              outv: var seq[SVert]) =
  ## The polygon `vs` cut at the near plane, projected.
  outv.setLen(0)
  for k in 0 ..< vs.len:
    let (p, s) = vs[k]
    let (q, t) = vs[(k + 1) mod vs.len]
    let pin = p.z >= ctx.near
    let qin = q.z >= ctx.near
    if pin: outv.add project(ctx, p, s)
    if pin != qin:
      let f = (ctx.near - p.z) / (q.z - p.z)
      outv.add project(ctx, p + (q - p) * f, s + (t - s) * f)

proc shadeOf(n: Vec3; ambient: float32; twoSided: bool): float32 {.inline.} =
  var d = dot(unit(n), LightDir)
  if twoSided: d = abs(d)
  ambient + (1 - ambient) * max(0'f32, d)

proc renderInto(ctx: var RenderCtx; scene: Scene3; cam: Camera3; bg: Color) =
  let w = ctx.w
  let h = ctx.h
  # the background: a soft gradient, or the scene's color
  let top = if bg.a != 0: bg else: mixColor(th.field, th.face, 0.15)
  let bottom = if bg.a != 0: bg else: mixColor(th.field, th.face, 0.85)
  for y in 0 ..< h:
    let c = pack(mixColor(top, bottom, y / max(1, h - 1)), 1)
    let row = y * w
    for x in 0 ..< w: ctx.px[row + x] = c
  for z in ctx.z.mitems: z = 0
  let b = basis(cam)
  ctx.focal = (h.float32 * 0.5'f32) / tan(clamp(cam.fov, 5, 170) * PI.float32 / 360)
  ctx.near = max(1e-4'f32, cam.distance * 0.002'f32)
  let ambient = if scene.ambient > 0: clamp(scene.ambient, 0, 1) else: 0.35'f32
  ctx.view.setLen(scene.meshes.len)
  ctx.spheres.setLen(scene.meshes.len)
  var poly: seq[tuple[p: Vec3; s: float32]]
  var clipped: seq[SVert]
  var shades: seq[float32]
  var smoothN: seq[Vec3]
  for mi, m in scene.meshes:
    ctx.view[mi].setLen(0)
    ctx.spheres[mi] = (Vec3(), -1'f32)
    if not m.visible or m.verts.len == 0: continue
    let rot = rotation(m.rot)
    # the points seen from the eye, and a sphere around them
    var vv = move ctx.view[mi]
    vv.setLen(m.verts.len)
    var lo, hi: Vec3
    for k, v in m.verts:
      let p = toView(b, worldPoint(m, rot, v))
      vv[k] = p
      if k == 0:
        lo = p
        hi = p
      else:
        lo = Vec3(x: min(lo.x, p.x), y: min(lo.y, p.y), z: min(lo.z, p.z))
        hi = Vec3(x: max(hi.x, p.x), y: max(hi.y, p.y), z: max(hi.z, p.z))
    ctx.spheres[mi] = ((lo + hi) * 0.5'f32, len(hi - lo) * 0.5'f32)
    # smooth: the light at each point, from its normal
    let smooth = m.smooth and not scene.wireframe
    if smooth:
      let given = m.normals.len == m.verts.len
      if not given:
        smoothN.setLen(m.verts.len)
        for n in smoothN.mitems: n = Vec3()
        for t in m.tris:
          if t[0] < 0 or t[1] < 0 or t[2] < 0 or t[0] >= vv.len or t[1] >= vv.len or
             t[2] >= vv.len: continue
          # (eye space turns the other way round: this points out of the face)
          let fnrm = cross(vv[t[2]] - vv[t[0]], vv[t[1]] - vv[t[0]])
          for k in 0 .. 2: smoothN[t[k]] = smoothN[t[k]] + fnrm
      shades.setLen(m.verts.len)
      for k in 0 ..< m.verts.len:
        let n = if given:
                  let wn = apply(rot, Vec3(x: m.normals[k].x / max(1e-6'f32, abs(m.scale.x)),
                                           y: m.normals[k].y / max(1e-6'f32, abs(m.scale.y)),
                                           z: m.normals[k].z / max(1e-6'f32, abs(m.scale.z))))
                  Vec3(x: dot(wn, b.right), y: dot(wn, b.up), z: dot(wn, b.fwd))
                else: smoothN[k]
        # (eye space normals point at the eye with z < 0)
        shades[k] = shadeOf(n, ambient, m.twoSided)
    let edgeColor = pack(mixColor(m.color, color(0, 0, 0), 0.6), 1)
    # outlines: only where the surface folds (not the diagonals of flat faces)
    var fold: Table[int64, tuple[n: Vec3; count: int]]
    let outline = m.edges and not scene.wireframe
    if outline:
      for t in m.tris:
        if t[0] < 0 or t[1] < 0 or t[2] < 0 or t[0] >= vv.len or t[1] >= vv.len or
           t[2] >= vv.len: continue
        let fn = unit(cross(vv[t[1]] - vv[t[0]], vv[t[2]] - vv[t[0]]))
        for k in 0 .. 2:
          let a = t[k]
          let b2 = t[(k + 1) mod 3]
          let key = (min(a, b2).int64 shl 32) or max(a, b2).int64
          let e = fold.getOrDefault(key, (Vec3(), 0))
          let keep = if e.count == 0: fn
                     elif dot(e.n, fn) > 0.999: e.n      # (flat across: no edge)
                     else: Vec3()
          fold[key] = (keep, e.count + 1)
    for ti, t in m.tris:
      if t[0] < 0 or t[1] < 0 or t[2] < 0 or t[0] >= vv.len or t[1] >= vv.len or
         t[2] >= vv.len: continue
      let p0 = vv[t[0]]
      let p1 = vv[t[1]]
      let p2 = vv[t[2]]
      if not (finite(p0) and finite(p1) and finite(p2)): continue
      if p0.z < ctx.near and p1.z < ctx.near and p2.z < ctx.near: continue
      # (eye space is left-handed: a face turned to the eye has dot(n, p0) > 0;
      # the normal lit is the one pointing at the eye)
      var n = cross(p1 - p0, p2 - p0)
      let facing = dot(n, p0)
      if facing > 0: n = n * -1'f32
      elif not m.twoSided and not scene.wireframe: continue
      let col = if m.colors.len == m.tris.len: m.colors[ti] else: m.color
      let s = shadeOf(n, ambient, false)
      poly.setLen(0)
      for k in 0 .. 2:
        let sk = if smooth: shades[t[k]] else: s
        poly.add ([p0, p1, p2][k], sk)
      clipNear(ctx, poly, clipped)
      if clipped.len < 3: continue
      if not scene.wireframe:
        for k in 1 ..< clipped.len - 1:
          fillTri(ctx, clipped[0], clipped[k], clipped[k + 1], col, smooth)
      if scene.wireframe:
        for k in 0 ..< clipped.len:
          drawLine(ctx, clipped[k], clipped[(k + 1) mod clipped.len], pack(m.color, 1), 0.004)
      elif outline and clipped.len == 3 and p0.z >= ctx.near and p1.z >= ctx.near and
           p2.z >= ctx.near:
        for k in 0 .. 2:
          let a = t[k]
          let b2 = t[(k + 1) mod 3]
          let e = fold.getOrDefault((min(a, b2).int64 shl 32) or max(a, b2).int64, (Vec3(), 0))
          if e.count < 2 or (e.n.x == 0 and e.n.y == 0 and e.n.z == 0):
            drawLine(ctx, clipped[k], clipped[(k + 1) mod 3], edgeColor, 0.004)
    ctx.view[mi] = move vv
  # lines
  for l in scene.lines:
    var a = toView(b, l.a)
    var c = toView(b, l.b)
    if not (finite(a) and finite(c)): continue
    if a.z < ctx.near and c.z < ctx.near: continue
    if a.z < ctx.near: a = a + (c - a) * ((ctx.near - a.z) / (c.z - a.z))
    elif c.z < ctx.near: c = c + (a - c) * ((ctx.near - c.z) / (a.z - c.z))
    drawLine(ctx, project(ctx, a, 1), project(ctx, c, 1), pack(l.color, 1), 0.002)
  # where the labels go
  ctx.labels.setLen(scene.labels.len)
  for k, lb in scene.labels:
    let p = toView(b, lb.at)
    if finite(p) and p.z >= ctx.near:
      let s = project(ctx, p, 1)
      ctx.labels[k] = (s.x, s.y, finite(s.x) and finite(s.y))
    else: ctx.labels[k] = (0'f32, 0'f32, false)

proc render3d*(scene: Scene3; cam: Camera3; w, h: int; background = Color()): Bitmap =
  ## The scene seen by `cam`, `w` x `h` pixels (to save with `encodePng`),
  ## on `background` (else the scene's). Labels are not in it.
  let w = clamp(w, 1, 16384)
  let h = clamp(h, 1, 16384)
  result = newBitmap(w, h)
  var ctx = RenderCtx(w: w, h: h)
  ctx.px = cast[ptr UncheckedArray[uint32]](addr result.px[0])
  ctx.z = newSeq[float32](w * h)
  renderInto(ctx, scene, cam, if background.a != 0: background else: scene.background)
  result.changed()

# ---- picking ----------------------------------------------------------------------------------------

proc pickAt(ctx: RenderCtx; scene: Scene3; sx, sy: float32): tuple[mesh, tri: int] =
  ## The mesh and triangle seen at the screen point `sx`, `sy` (device
  ## pixels) of the last picture; -1 for none.
  result = (-1, -1)
  if ctx.focal <= 0: return
  let dir = unit(Vec3(x: (sx - ctx.w.float32 * 0.5'f32) / ctx.focal,
                      y: -(sy - ctx.h.float32 * 0.5'f32) / ctx.focal, z: 1))
  var best = Inf.float32
  for mi, m in scene.meshes:
    if mi >= ctx.view.len or not m.visible: continue
    let vv = ctx.view[mi]
    if vv.len != m.verts.len or vv.len == 0: continue
    let (c, r) = ctx.spheres[mi]
    if r < 0: continue
    # the ray misses the sphere around the mesh: not this one
    let tc = dot(c, dir)
    let d2 = dot(c, c) - tc * tc
    if d2 > r * r * 1.0001'f32 + 1e-6'f32 or tc + r < ctx.near: continue
    for ti, t in m.tris:
      if t[0] < 0 or t[1] < 0 or t[2] < 0 or t[0] >= vv.len or t[1] >= vv.len or
         t[2] >= vv.len: continue
      let v0 = vv[t[0]]
      let e1 = vv[t[1]] - v0
      let e2 = vv[t[2]] - v0
      let pv = cross(dir, e2)
      let det = dot(e1, pv)
      if abs(det) < 1e-12'f32: continue
      let inv = 1'f32 / det
      let tv = Vec3() - v0
      let u = dot(tv, pv) * inv
      if u < 0 or u > 1: continue
      let qv = cross(tv, e1)
      let v = dot(dir, qv) * inv
      if v < 0 or u + v > 1: continue
      let dist = dot(e2, qv) * inv
      if dist >= ctx.near and dist < best:
        best = dist
        result = (mi, ti)

# ---- the widget ----------------------------------------------------------------------------------

type ViewCache = ref object
  bmp: Bitmap
  ctx: RenderCtx
  hash: uint64
  usedAt: int
  hoverAt: tuple[x, y: int; hash: uint64]
  hover: tuple[mesh, tri: int]
  press: tuple[x, y: int; yaw, pitch: float32; target: Vec3; pan, moved: bool; at: int]

var
  caches: Table[Id, ViewCache]
  renderCount = 0

proc renders*(): int = renderCount
  ## How many pictures the 3D views drew so far (each is drawn only when
  ## something changed).

proc mixH(h: var uint64; x: uint64) {.inline.} =
  h = (h xor x) * 0x9E3779B97F4A7C15'u64
  h = h xor (h shr 29)
proc mixF(h: var uint64; f: float32) {.inline.} = mixH(h, uint64(cast[uint32](f)))
proc mixV(h: var uint64; v: Vec3) {.inline.} =
  mixF(h, v.x)
  mixF(h, v.y)
  mixF(h, v.z)
proc mixC(h: var uint64; c: Color) {.inline.} =
  mixH(h, uint64(c.r) or (uint64(c.g) shl 8) or (uint64(c.b) shl 16) or (uint64(c.a) shl 24))

proc sceneHash(scene: Scene3; cam: Camera3; w, h: int): uint64 =
  ## What the picture depends on (cheap: not the points themselves, which
  ## `sceneChanged` stands for).
  result = 0x51ED270B'u64
  mixH(result, uint64(scene.version))
  mixH(result, uint64(w) or (uint64(h) shl 32))
  mixH(result, uint64(scene.meshes.len))
  for m in scene.meshes:
    mixH(result, uint64(m.verts.len) or (uint64(m.tris.len) shl 32))
    mixH(result, if m.verts.len > 0: cast[uint64](unsafeAddr m.verts[0]) else: 0)
    mixH(result, if m.tris.len > 0: cast[uint64](unsafeAddr m.tris[0]) else: 0)
    mixH(result, uint64(m.colors.len))
    mixV(result, m.pos)
    mixV(result, m.rot)
    mixV(result, m.scale)
    mixC(result, m.color)
    mixH(result, uint64(ord(m.visible)) or uint64(ord(m.smooth)) shl 1 or
         uint64(ord(m.twoSided)) shl 2 or uint64(ord(m.edges)) shl 3)
  mixH(result, uint64(scene.lines.len))
  mixH(result, if scene.lines.len > 0: cast[uint64](unsafeAddr scene.lines[0]) else: 0)
  mixH(result, uint64(scene.labels.len))
  for l in scene.labels: mixV(result, l.at)
  mixC(result, scene.background)
  mixF(result, scene.ambient)
  mixH(result, uint64(ord(scene.wireframe)))
  mixV(result, cam.target)
  mixF(result, cam.yaw)
  mixF(result, cam.pitch)
  mixF(result, cam.distance)
  mixF(result, cam.fov)
  mixC(result, th.field)
  mixC(result, th.face)

proc cornerButton(hit: Hit; r: Rect; glyph: string; tip: string) =
  buttonFace(r, hit.down, rounded = false, bevel = 1, hot = hovered(r))
  let o = if hit.down: 1 else: 0
  if isPixelIcon(glyph):
    let k = max(16, min(r.w, r.h) - dp(4)) div 16 * 16
    pixelIconAt(rect(r.x + (r.w - k) div 2 + o, r.y + (r.h - k) div 2 + o, k, k), glyph)
  else:
    let tw = textWidth(glyph, true)
    text(r.x + (r.w - tw) div 2 + o, r.y + (r.h - FontH) div 2 + o, glyph, th.text, true)
  ui.lastRect = r
  tooltip(tip)

proc view3d*(scene: var Scene3; cam: var Camera3; height = -1; w = 0; key = "";
             controls = true): View3DEvent {.discardable.} =
  ## The scene seen by `cam`, `height` pixels high (-1: the room left).
  ## Drag to turn it, Shift or Ctrl + drag (or a finger held a moment,
  ## then moved) to move it, the wheel to zoom; with the focus: arrows turn,
  ## + / - zoom, Home goes back to the first view. `controls`: zoom and home
  ## buttons in the corner (handy for fingers). A click reports the mesh
  ## under it (`picked`), the mouse resting over one `hovered`.
  result.picked = -1
  result.pickedTri = -1
  result.hovered = -1
  result.hoveredTri = -1
  let r = place(if w > 0: w else: 0, if height < 0: remainingH() else: max(dp(40), height),
                fill = w <= 0)
  let id = idOf("view3d:" & key)
  var c = caches.getOrDefault(id, nil)
  if c == nil:
    c = ViewCache()
    caches[id] = c
  c.usedAt = ui.now
  let inner = inset(r, 2)
  # the corner buttons (they take their presses before the view does)
  let bs = if fingers(): CtrlH else: dp(20)
  var btns: array[3, Rect]
  var bhits: array[3, Hit]
  if controls and inner.w > bs * 4 and inner.h > bs * 2:
    for k in 0 .. 2:
      btns[k] = rect(inner.x + inner.w - (3 - k) * (bs + dp(2)), inner.y + dp(3), bs, bs)
      bhits[k] = interact(id + uint32(k + 1), btns[k], focusable = false)
  var hit = interact(id, inner)
  let before = (cam.target, cam.yaw, cam.pitch, cam.distance)
  # the mouse, fingers, the keyboard
  if canInput():
    if hit.down and ui.pressed:
      ui.dragsActive = true          # (a finger turns the scene, not the page)
      c.press = (ui.mx, ui.my, cam.yaw, cam.pitch, cam.target,
                 ShiftPressed in ui.mods or CtrlPressed in ui.mods, false, ui.now)
    if ui.active == id and ui.mouseDown:
      let dx = ui.mx - c.press.x
      let dy = ui.my - c.press.y
      if not c.press.moved and abs(dx) + abs(dy) > dp(4):
        c.press.moved = true
        # a finger held still for a moment, then moved: it moves the scene
        if finger() and ui.now - c.press.at > 450: c.press.pan = true
      if not c.press.moved and finger() and not c.press.pan:
        wakeIn(max(1, 460 - (ui.now - c.press.at)))
      if c.press.moved:
        if c.press.pan:
          let k = 2 * cam.distance * tan(clamp(cam.fov, 5, 170) * PI.float32 / 360) /
                  max(1, inner.h).float32
          let bs = basis(Camera3(target: c.press.target, yaw: cam.yaw, pitch: cam.pitch,
                                 distance: cam.distance, fov: cam.fov))
          cam.target = c.press.target - bs.right * (dx.float32 * k) + bs.up * (dy.float32 * k)
        else:
          cam.yaw = c.press.yaw - dx.float32 * 0.5'f32
          cam.pitch = clamp(c.press.pitch + dy.float32 * 0.5'f32, -89, 89)
    if ui.wheel != 0 and not ui.wheelUsed and mouseIn(inner):
      cam.distance = cam.distance * pow(0.88'f32, ui.wheel.float32)
      ui.wheelUsed = true
    if hit.focused:
      case ui.key
      of KeyLeft: cam.yaw += 7.5; ui.keyUsed = true
      of KeyRight: cam.yaw -= 7.5; ui.keyUsed = true
      of KeyUp: cam.pitch = min(89, cam.pitch + 7.5); ui.keyUsed = true
      of KeyDown: cam.pitch = max(-89, cam.pitch - 7.5); ui.keyUsed = true
      of KeyPlus, KeyEqual: cam.distance *= 0.8; ui.keyUsed = true
      of KeyMinus: cam.distance *= 1.25; ui.keyUsed = true
      of KeyHome: resetView(cam); ui.keyUsed = true
      else:
        if ui.typed == "+": cam.distance *= 0.8
        elif ui.typed == "-": cam.distance *= 1.25
  if btns[0].w > 0:
    if bhits[0].clicked: cam.distance *= 0.8
    if bhits[1].clicked: cam.distance *= 1.25
    if bhits[2].clicked: resetView(cam)
  if not (cam.distance == cam.distance): cam.distance = 1
  cam.distance = clamp(cam.distance, 1e-3, 1e7)
  if cam.yaw > 360 or cam.yaw < -360: cam.yaw = cam.yaw mod 360'f32
  # the picture: drawn again only when something changed
  let dw = max(1, inner.w * pxScale)
  let dh = max(1, inner.h * pxScale)
  let hsh = sceneHash(scene, cam, dw, dh)
  if c.bmp == nil or c.bmp.w != dw or c.bmp.h != dh or c.hash != hsh:
    if c.bmp == nil or c.bmp.w != dw or c.bmp.h != dh:
      c.bmp = newBitmap(dw, dh)
      c.ctx.z = newSeq[float32](dw * dh)
    c.ctx.w = dw
    c.ctx.h = dh
    c.ctx.px = cast[ptr UncheckedArray[uint32]](addr c.bmp.px[0])
    renderInto(c.ctx, scene, cam, scene.background)
    c.bmp.changed()
    c.hash = hsh
    inc renderCount
  # draw
  fill(r, th.face)
  sunken(r)
  box(inset(r, 1), th.edge)
  drawBitmap(inner, c.bmp)
  pushClip(inner)
  for k, lb in scene.labels:
    if k < c.ctx.labels.len and c.ctx.labels[k].ok:
      let x = int(c.ctx.labels[k].x / pxScale.float32)
      let y = int(c.ctx.labels[k].y / pxScale.float32)
      let tw = textWidth(lb.text, lb.bold)
      let tx = inner.x + x - tw div 2
      let ty = inner.y + y - FontH div 2
      # a halo in the background's color keeps it legible over the bars
      for (ox, oy) in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
        text(tx + ox, ty + oy, lb.text, th.field, lb.bold)
      text(tx, ty, lb.text, if lb.color.a != 0: lb.color else: th.text, lb.bold)
  popClip()
  if btns[0].w > 0:
    cornerButton(bhits[0], btns[0], "+", "Closer (+)")
    cornerButton(bhits[1], btns[1], "-", "Farther (-)")
    cornerButton(bhits[2], btns[2], retroOr(pxHome, nfHome), "The first view (Home)")
  if hit.focused: focusDots(inset(r, 3))
  # picking: a click that did not turn the scene; the mesh under the mouse
  let mx = (ui.mx - inner.x) * pxScale + pxScale div 2
  let my = (ui.my - inner.y) * pxScale + pxScale div 2
  if hit.clicked and not c.press.moved and canInput():
    let p = pickAt(c.ctx, scene, mx.float32, my.float32)
    result.clicked = true
    result.picked = p.mesh
    result.pickedTri = p.tri
    if ui.clicks >= 2 and p.mesh >= 0:
      result.activated = true
      markDouble(id)
  if canHover() and not ui.mouseDown and hover(inner):
    if c.hoverAt != (ui.mx, ui.my, c.hash):
      c.hoverAt = (ui.mx, ui.my, c.hash)
      c.hover = pickAt(c.ctx, scene, mx.float32, my.float32)
    result.hovered = c.hover.mesh
    result.hoveredTri = c.hover.tri
    if c.hover.mesh >= 0 and c.hover.mesh < scene.meshes.len and not ui.mouseDown:
      tooltip(scene.meshes[c.hover.mesh].name)
  result.cameraChanged = before != (cam.target, cam.yaw, cam.pitch, cam.distance)
  if result.cameraChanged: ui.redraw = true
  # pictures of views not shown for a while are let go
  if caches.len > 1:
    var gone: seq[Id]
    for k, v in caches:
      if ui.now - v.usedAt > 30_000: gone.add k
    for k in gone: caches.del k
  ui.lastId = id
  ui.lastRect = r
