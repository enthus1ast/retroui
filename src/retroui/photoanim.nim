## Frame animation, as Photoshop's Timeline does it: frames that each keep
## which layers show, how opaque they are and where, and how long the frame
## is shown; frames made from layers, tweened between two, played, made
## into layers; an animated GIF or WebP opened as layers and frames, and
## the frames composited for saving one.
##
## ```nim
## d.framesFromLayers()             # a frame for each layer
## d.showFrame(2)
## for (px, delay) in d.animationFrames(): ...   # each frame composited
## ```

import std/tables
import gfx, photo

var boxCache: Table[(pointer, int), Rect]   # (a layer and its `ver`: where its content is)

proc boxOf(d: Doc; L: Layer): Rect =
  if L.group or L.adjust.kind.len > 0: return rect(0, 0, 0, 0)
  let k = (cast[pointer](L), L.ver)
  if k in boxCache: return boxCache[k]
  if boxCache.len > 4096: boxCache.clear()
  result = d.layerBox(L)
  boxCache[k] = result

proc captureFrame*(d: Doc; delay = 100; positions = true): AnimFrame =
  ## The layers as they are now, as a frame shown `delay` milliseconds.
  result = AnimFrame(delay: delay)
  for L in d.layers:
    var fl = FrameLayer(uid: L.uidOf, visible: L.visible, opacity: L.opacity)
    if positions:
      let b = d.boxOf(L)
      fl.dx = b.x
      fl.dy = b.y
    result.layers.add fl

proc stateIn(f: AnimFrame; uid: int; found: var bool): FrameLayer =
  for fl in f.layers:
    if fl.uid == uid:
      found = true
      return fl
  found = false

proc animated*(d: Doc): bool {.inline.} = d.frames.len > 0
  ## It has an animation (frames in the Timeline).

proc syncFrame*(d: Doc) =
  ## The frame shown takes what was changed in the layers since (shown or
  ## not, opacity, moved): as Photoshop's frames follow the Layers panel.
  if d.frames.len == 0: return
  let k = clamp(d.frameCur, 0, d.frames.high)
  d.frames[k] = d.captureFrame(d.frames[k].delay)

proc showFrame*(d: Doc; k: int) =
  ## Frame `k` shown: its layers shown or not, at their opacity, where
  ## they were (layers made since: shown as they are). Not undoable (as
  ## picking a frame in Photoshop).
  if k < 0 or k >= d.frames.len: return
  let wasModified = d.modified          # (a frame looked at: not a change to save)
  let from0 = d.frames[clamp(d.frameCur, 0, d.frames.high)]
  let f = d.frames[k]
  for fl in f.layers:
    let L = d.layerOfUid(fl.uid)
    if L == nil: continue
    L.visible = fl.visible
    L.opacity = fl.opacity
    var found = false
    let was = from0.stateIn(fl.uid, found)
    if not found or was.dx != fl.dx or was.dy != fl.dy:
      let b = d.boxOf(L)
      if b.w > 0 and (b.x != fl.dx or b.y != fl.dy) and not L.background:
        d.shiftLayers(@[L], fl.dx - b.x, fl.dy - b.y)
  d.frameCur = k
  d.markAll()
  d.modified = wasModified

proc ensureFrames*(d: Doc) =
  ## A first frame (the layers as they are) when there is none.
  if d.frames.len == 0:
    d.frames.add d.captureFrame()
    d.frameCur = 0

proc addFrame*(d: Doc) =
  ## Duplicates the frame shown (Timeline: New Frame); the copy shown.
  d.ensureFrames()
  d.syncFrame()
  let k = d.frameCur
  d.frames.insert(d.frames[k], k + 1)
  d.frameCur = k + 1

proc deleteFrame*(d: Doc; k: int) =
  ## Takes frame `k` away (the last one: the animation ends, the layers as
  ## they are).
  if k < 0 or k >= d.frames.len: return
  d.frames.delete(k)
  if d.frames.len == 0:
    d.frameCur = 0
    return
  let n = clamp(d.frameCur - (if k <= d.frameCur and d.frameCur > 0: 1 else: 0), 0, d.frames.high)
  d.frameCur = clamp(k, 0, d.frames.high)
  d.showFrame(n)

proc moveFrame*(d: Doc; a, b: int) =
  ## Frame `a` put where `b` is.
  if a < 0 or b < 0 or a >= d.frames.len or b >= d.frames.len or a == b: return
  let f = d.frames[a]
  d.frames.delete(a)
  d.frames.insert(f, b)
  if d.frameCur == a: d.frameCur = b

proc framesFromLayers*(d: Doc; delay = 100) =
  ## Make Frames From Layers: a frame for each layer (bottom first), that
  ## layer shown -- and the Background, when there is one, under each.
  var bg: Layer
  var picked: seq[Layer]
  for L in d.layers:
    if L.group: continue
    if L.background: bg = L
    elif L.adjust.kind.len == 0: picked.add L
  if picked.len == 0: return
  d.frames.setLen(0)
  for P in picked:
    var f = AnimFrame(delay: delay)
    for L in d.layers:
      let b = d.boxOf(L)
      f.layers.add FrameLayer(uid: L.uidOf, visible: L == P or L == bg or L.group or L.adjust.kind.len > 0,
                              opacity: L.opacity, dx: b.x, dy: b.y)
    d.frames.add f
  d.frameCur = 0
  d.showFrame(0)

proc tweenFrames*(d: Doc; a, b: int; n: int) =
  ## Tween: `n` frames put between frames `a` and `b`, each layer's opacity
  ## and place going from one to the other.
  if a < 0 or b < 0 or a >= d.frames.len or b >= d.frames.len or n <= 0: return
  let fa = d.frames[a]
  let fb = d.frames[b]
  var made: seq[AnimFrame]
  for k in 1 .. n:
    let t = k / (n + 1)
    var f = AnimFrame(delay: fa.delay)
    for la in fa.layers:
      var found = false
      let lb = fb.stateIn(la.uid, found)
      if not found:
        f.layers.add la
        continue
      let oa = if la.visible: la.opacity else: 0
      let ob = if lb.visible: lb.opacity else: 0
      let op = int(oa.float + (ob - oa).float * t + 0.5)
      f.layers.add FrameLayer(uid: la.uid, visible: op > 0, opacity: max(op, 1),
                              dx: int(la.dx.float + (lb.dx - la.dx).float * t + 0.5),
                              dy: int(la.dy.float + (lb.dy - la.dy).float * t + 0.5))
    made.add f
  let at = min(a, b) + 1
  for k in countdown(made.high, 0):
    d.frames.insert(if a < b: made[k] else: made[made.high - k], at)

proc frameComposite*(d: Doc; k: int): seq[uint32] =
  ## Frame `k` as it looks (the image composited), the frame shown kept.
  if d.frames.len == 0:
    d.updateComposite()
    return d.compCopy
  let was = d.frameCur
  d.syncFrame()
  d.showFrame(k)
  d.updateComposite()
  result = d.compCopy
  d.showFrame(was)

proc animationFrames*(d: Doc): seq[tuple[px: seq[uint32]; delay: int]] =
  ## Every frame composited, with how long it is shown (no frames: the
  ## image, once).
  if d.frames.len == 0:
    d.updateComposite()
    return @[(d.compCopy, 0)]
  let was = d.frameCur
  d.syncFrame()
  for k in 0 ..< d.frames.len:
    d.showFrame(k)
    d.updateComposite()
    result.add (d.compCopy, d.frames[k].delay)
  d.showFrame(was)

proc flattenFramesIntoLayers*(d: Doc) =
  ## Flatten Frames Into Layers: each frame composited into a layer of its
  ## own (on top), named for it. Undoable in a step (`touchLayers` first).
  let shots = d.animationFrames()
  for k, (px, delay) in shots:
    let L = d.addLayer("Frame " & $(k + 1))
    L.px = px
    inc L.ver
  d.markAll()

proc docFromFrames*(w, h: int; frames: seq[tuple[px: seq[uint32]; delay: int]]; name = "Untitled";
                    loop = 0): Doc =
  ## An animation opened (an animated GIF, WebP): a layer for each frame
  ## and a frame showing each.
  result = newDoc(w, h, 0, name = name)
  if frames.len == 0: return
  result.layer.px = frames[0].px
  result.layer.name = "Frame 1"
  inc result.layer.ver
  for k in 1 ..< frames.len:
    let L = result.addLayer("Frame " & $(k + 1))
    L.px = frames[k].px
    inc L.ver
  for k in 0 ..< frames.len:
    var f = AnimFrame(delay: max(10, frames[k].delay))
    for i, L in result.layers:
      f.layers.add FrameLayer(uid: L.uidOf, visible: i == k, opacity: 100)
    result.frames.add f
  result.animLoop = loop
  result.frameCur = 0
  result.showFrame(0)
  result.modified = false
