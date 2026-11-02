## Videos written and read back (retro/media): `beginVideo`, `addFrame`,
## `finish` make an MP4 of a made-up animation (each picture carrying its
## number in black and white squares); `videoInfo`, `videoFrameAt` and
## `videoFrames` read it back -- the right picture for each time, close to
## what was written. The calls to Android's side are checked with a fake
## one. Without an encoder here (no ffmpeg), the writing part is skipped.

import std/[os, strutils, math]
import retro/[gfx, media, mediagst]
import retro/uirelays/services

const
  W = 322                          # (odd: written 322 x 182)
  H = 181
  Fps = 24.0
  Count = 48
  Bits = 6                         # the picture's number, in squares along the top

proc picture(k: int): Bitmap =
  ## Picture `k`: colours that change across it and with k, a white square
  ## going across, its number in `Bits` squares (white = 1).
  result = newBitmap(W, H, 0xFF000000'u32)
  for y in 0 ..< H:
    for x in 0 ..< W:
      let r = (x * 255 div W + k * 3) and 255
      let g = y * 255 div H
      let b = (128 + 100 * sin(float(x + y + k * 4) / 30)).int
      result.px[y * W + x] = 0xFF000000'u32 or uint32(r shl 16) or uint32(g shl 8) or uint32(b)
  let sx = 20 + k * 5
  for y in 120 ..< 150:
    for x in sx ..< sx + 30: result.px[y * W + x] = 0xFFFFFFFF'u32
  for i in 0 ..< Bits:
    let on = ((k shr (Bits - 1 - i)) and 1) == 1
    for y in 4 ..< 24:
      for x in 4 + i * 26 ..< 24 + i * 26:
        result.px[y * W + x] = if on: 0xFFFFFFFF'u32 else: 0xFF000000'u32
  result.opaque = true

proc numberOf(b: Bitmap): int =
  ## The number a picture read back carries.
  for i in 0 ..< Bits:
    var sum = 0
    for y in 8 ..< 20:
      for x in 8 + i * 26 ..< 20 + i * 26: sum += int((b.px[y * b.w + x] shr 8) and 255)
    result = result * 2 + ord(sum div 144 > 128)

proc meanError(a, b: Bitmap): float =
  ## The mean difference of the colours (0..255), over `a`'s size.
  var s = 0
  for y in 0 ..< a.h:
    for x in 0 ..< a.w:
      let p = a.px[y * a.w + x]
      let q = b.px[y * b.w + x]
      s += abs(int((p shr 16) and 255) - int((q shr 16) and 255)) +
           abs(int((p shr 8) and 255) - int((q shr 8) and 255)) + abs(int(p and 255) - int(q and 255))
  s / (a.w * a.h * 3)

# ---- Android's side, faked: what goes over and what comes back -------------------------------------

var calls: seq[string]
var yuvSizes: seq[int]
var firstY: int
let fakeVideo = getTempDir() / "retro-videoenc-fake.mp4"
systemRelays.call = proc (name, arg: string): string {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    calls.add name
    let a = arg.split('\t')
    case name
    of "media.encAvailable": "1"
    of "media.encBegin":
      doAssert a.len == 7 and a[1] == fakeVideo and a[2] == "322" and a[3] == "182" and
               a[4].startsWith("24.") and a[6] == "601", arg
      "1\t322\t182\tc2.fake.avc.encoder"
    of "media.encFrame":
      let d = readFile(a[1])
      yuvSizes.add d.len
      if yuvSizes.len == 1: firstY = ord(d[0])
      doAssert parseInt(a[2]) == int((yuvSizes.len - 1).float * 1_000_000 / 24 + 0.5), arg
      "1"
    of "media.encEnd":
      writeFile(fakeVideo, "made by the fake encoder")
      "1"
    of "media.info": "640\t360\t6000\t29.97\t0"
    of "media.frameRaw":
      # a 3 x 2 picture: BGRA, the first pixel red
      var d = newString(3 * 2 * 4)
      for i in 0 ..< 6:
        d[i * 4] = char(0); d[i * 4 + 1] = char(0); d[i * 4 + 2] = char(if i == 0: 255 else: 0)
        d[i * 4 + 3] = char(255)
      writeFile(a[1], d)
      "1\t3\t2"
    else: "\0"

block android:
  mediaThroughSystem = true
  doAssert videoEncodeAvailable()
  let v = beginVideo(fakeVideo, W, H, Fps)
  doAssert v.error == "" and v.width == 322 and v.height == 182 and v.codec == "MediaCodec c2.fake.avc.encoder"
  let red = newBitmap(W, H, 0xFFFF0000'u32)
  for k in 0 ..< 3: doAssert v.addFrame(red)
  doAssert v.finish() and v.frames == 3, v.error
  doAssert yuvSizes == @[322 * 182 * 3 div 2, 322 * 182 * 3 div 2, 322 * 182 * 3 div 2]
  doAssert firstY in 80 .. 82, $firstY     # red's Y (BT.601, limited range): 81
  let info = videoInfo("/sdcard/clip.mp4")
  doAssert info.width == 640 and info.height == 360 and info.durationMs == 6000 and
           abs(info.fps - 29.97) < 1e-9 and info.frames == 180
  let b = videoFrameAt("/sdcard/clip.mp4", 1234, 100)
  doAssert b != nil and b.w == 3 and b.h == 2 and b.px[0] == 0xFFFF0000'u32 and b.px[1] == 0xFF000000'u32
  doAssert "media.frameRaw" in calls
  mediaThroughSystem = false
  removeFile(fakeVideo)

# ---- the real thing, where this machine can write videos -----------------------------------------------

if not videoEncodeAvailable():
  echo "videoenc: no video encoder here (no ffmpeg): writing and reading back skipped"
  echo "videoenc tests passed"
  quit 0

let dir = getTempDir() / "retro-videoenc"
createDir(dir)

proc writeVideo(path: string): VideoWriter =
  result = beginVideo(path, W, H, Fps)
  doAssert result.error == "", result.error
  doAssert result.width == 322 and result.height == 182
  for k in 0 ..< Count: doAssert result.addFrame(picture(k)), result.error
  doAssert result.finish(), result.error
  doAssert result.frames == Count and fileExists(path) and getFileSize(path) > 1000

proc readBack(path: string; tools: openArray[VideoTool]; maxErr: float) =
  for tool in tools:
    videoTool = tool
    let info = videoInfo(path)
    doAssert info.width == 322 and info.height == 182, $tool & " " & $info
    doAssert info.durationMs in 1950 .. 2050, $info
    if info.fps > 0:                     # (ffprobe knows it; GStreamer here does not)
      doAssert abs(info.fps - Fps) < 0.01 and info.frames == Count, $info
    # the picture shown at each time: 0 .. 41 ms the first, 42 .. 83 the second...
    var worst = 0.0
    for ms in [0, 41, 42, 500, 1000, 1001, 1958, 1959, 2500, 375, 10, 1600, 1650]:
      let b = videoFrameAt(path, ms)
      doAssert b != nil, $tool & " at " & $ms
      doAssert b.w == 322 and b.h == 182
      let k = min(Count - 1, int(floor(ms.float * Fps / 1000 + 1e-9)))
      doAssert numberOf(b) == k, $tool & " at " & $ms & " ms: picture " & $numberOf(b) & ", not " & $k
      worst = max(worst, meanError(picture(k), b))
    doAssert worst < maxErr, $tool & ": mean error " & $worst
    # every picture in turn, every third, then back and forth (scrubbing): each the right one
    var order: seq[int]
    for k in 0 ..< Count: order.add k
    for k in countup(0, Count - 1, 3): order.add k
    for k in [40, 12, 13, 30, 29, 47, 0, 46, 1]: order.add k
    for k in order:
      let b = videoFrameAt(path, int(k.float * 1000 / Fps + 20))
      doAssert b != nil and numberOf(b) == k, $tool & ": picture " & $k
    # made smaller on the way
    let small = videoFrameAt(path, 700, maxSide = 100)
    doAssert small != nil and max(small.w, small.h) <= 100 and small.w >= 99
    let all = videoFrames(path, everyMs = 250)
    doAssert all.len == 9, $all.len
    for (b, ms) in all: doAssert numberOf(b) == min(Count - 1, int(ms.float * Fps / 1000)), $ms
    closeVideoReader()
    echo "  read back with ", tool, ": mean colour error ", worst.formatFloat(ffDecimal, 2)

var tools: seq[VideoTool]
if gstAvailable(): tools.add vtGStreamer
if ffmpegExe().len > 0: tools.add vtFfmpeg

block h264:
  let path = dir / "anim.mp4"
  let v = writeVideo(path)
  echo "videoenc: ", v.codec, ", ", getFileSize(path), " bytes"
  readBack(path, tools, 4.0)

block fallbackEncoder:
  if ffmpegExe().len > 0:
    let keep = videoEncoders
    videoEncoders = @["mpeg4"]
    let path = dir / "anim-mpeg4.mp4"
    let v = writeVideo(path)
    doAssert v.codec == "mpeg4"
    readBack(path, tools, 6.0)
    videoEncoders = keep

block errors:
  let v = beginVideo(dir / "none.mp4", 0, 10, 25)
  doAssert v.error.len > 0 and not v.addFrame(newBitmap(1, 1)) and not v.finish()
  let e = beginVideo(dir / "empty.mp4", 64, 64, 25)
  doAssert e.error == ""
  doAssert not e.finish() and e.error.len > 0                     # no pictures
  # a picture of another size: centred, the rest black
  let o = beginVideo(dir / "other.mp4", 64, 48, 10)
  for k in 0 ..< 5: doAssert o.addFrame(newBitmap(20, 10, 0xFFFFFFFF'u32))
  doAssert o.finish(), o.error
  videoTool = vtAuto
  let b = videoFrameAt(dir / "other.mp4", 0)
  doAssert b != nil and b.w == 64 and b.h == 48
  doAssert (b.px[24 * 64 + 32] and 255) > 200 and (b.px[2 * 64 + 2] and 255) < 40
  closeVideoReader()

removeDir(dir)
echo "videoenc tests passed"
