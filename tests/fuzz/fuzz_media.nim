## Feeds damaged and random WAV and GIF files to `decodeWav` and `loadGif`,
## and mixes what they accept: nothing may fail other than with
## `ValueError`, nothing may hang (each round is timed).
##
##   nim c -r -d:release --stackTrace:on --lineTrace:on tests/fuzz/fuzz_media.nim 20000

import std/[os, random, strutils, monotimes, times]
import retroui/[gfx, mediaaudio, mediagif]

let dir = currentSourcePath().parentDir.parentDir / "data" / "media"
let rounds = if paramCount() >= 1: parseInt(paramStr(1)) else: 20000
var r = initRand(20261027)

proc u32(v: int): string =
  for k in 0 .. 3: result.add char((v shr (8 * k)) and 255)
proc u16(v: int): string =
  for k in 0 .. 1: result.add char((v shr (8 * k)) and 255)

proc randomWav(): string =
  ## A WAV file with fields that are mostly right.
  let tag = [1, 3, 0xFFFE, 2, 1, 1][r.rand(5)]
  let chans = [1, 2, 2, 4, 0, 33, 6][r.rand(6)]
  let bits = [8, 16, 24, 32, 64, 12, 0][r.rand(6)]
  let rate = [8000, 44100, 48000, 0, 999, 800000, 22050][r.rand(6)]
  let ba = max(0, chans * bits div 8) + [0, 0, 0, 1, -1][r.rand(4)]
  var fmt = u16(tag) & u16(chans) & u32(rate) & u32(rate * max(ba, 0)) & u16(ba) & u16(bits)
  if tag == 0xFFFE: fmt.add u16(22) & u16(bits) & u32(0) & u16([1, 3, 7][r.rand(2)]) & "x".repeat(14)
  var data = newString(r.rand(400))
  for c in data.mitems: c = char(r.rand(255))
  let dlen = [data.len, data.len + r.rand(1000), max(0, data.len - 3), -1][r.rand(3)]
  result = "RIFF" & u32(4 + 8 + fmt.len + 8 + data.len) & "WAVE" & "fmt " & u32(fmt.len) & fmt &
           "data" & u32(dlen) & data

var seeds = @[encodeWav(makeTone(440, 30)), encodeWav(joinSounds([makeTone(300, 5)])), randomWav()]
var gifSeeds: seq[string]
for f in ["rgb.gif", "pattern.gif"]: gifSeeds.add readFile(dir / f)

proc mutate(s: string; pool: seq[string]): string =
  result = s
  for _ in 0 .. r.rand(8):
    if result.len == 0: result.add char(r.rand(255))
    case r.rand(8)
    of 0, 1, 2: result[r.rand(result.high)] = char(r.rand(255))
    of 3: result[r.rand(result.high)] = char([0, 1, 0xFF, 0x7F, 0x80, 0x2C, 0x21, 0x3B][r.rand(7)])
    of 4:
      let a = r.rand(result.high)
      result.delete(a .. min(result.high, a + r.rand(30)))
    of 5:
      let b = pool[r.rand(pool.high)]
      let a = r.rand(b.high)
      result.insert(b[a .. min(b.high, a + r.rand(100))], r.rand(result.len))
    of 6: result.setLen(r.rand(result.len))
    of 7:
      var junk = newString(r.rand(40))
      for c in junk.mitems: c = char(r.rand(255))
      result.insert(junk, r.rand(result.len))
    else:
      # a size field said differently
      if result.len >= 8:
        let at = r.rand(result.len - 4)
        let v = [0, 1, 0xFFFF, 0x7FFFFFFF, -1, r.rand(100000)][r.rand(5)]
        for k in 0 .. 3: result[at + k] = char((v shr (8 * k)) and 255)

var wavOk, wavBad, gifOk, gifBad = 0
var slowest = 0.0
var buf = newSeq[int16](512)
for i in 1 .. rounds:
  let wavIn = if r.rand(3) == 0: randomWav() else: mutate(seeds[r.rand(seeds.high)], seeds)
  let t0 = getMonoTime()
  try:
    let s = decodeWav(wavIn)
    inc wavOk
    if s.frames > 0 and s.frames < 200_000:
      let v = mixSound(s, 1.0, r.rand(1) == 0, start = false)
      mixTo(buf)
      unmix(v)
      doAssert decodeWav(encodeWav(s)).frames == s.frames
  except ValueError:
    inc wavBad
  let gifIn = mutate(gifSeeds[r.rand(gifSeeds.high)], gifSeeds)
  try:
    let frames = loadGif(gifIn)
    inc gifOk
    for f in frames:
      doAssert f.image != nil and f.image.px.len == f.image.w * f.image.h and f.delayMs > 0
  except ValueError:
    inc gifBad
  let ms = (getMonoTime() - t0).inMicroseconds.float / 1000
  slowest = max(slowest, ms)
  doAssert ms < 2000, "round " & $i & " took " & $ms & " ms"
  if i mod 5000 == 0: echo "round ", i
echo "media fuzz passed: wav ", wavOk, " read, ", wavBad, " refused; gif ", gifOk, " read, ",
     gifBad, " refused; slowest round ", formatFloat(slowest, ffDecimal, 1), " ms"
