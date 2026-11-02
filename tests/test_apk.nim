## Unit checks of the APK builder's own SHA-256, CRC-32 and PNG writer.

import std/strutils
import ../src/retroapk {.all.}
import retro/appicon

proc hex(b: Bytes): string =
  for x in b: result.add x.toHex(2).toLowerAscii

doAssert hex(sha256(@[])) ==
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
doAssert hex(sha256("abc".toBytes)) ==
  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
var long = newSeq[byte](1_000_000)
for i in 0 ..< long.len: long[i] = byte('a')
doAssert hex(sha256(long)) ==
  "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
doAssert crc32("123456789".toBytes) == 0xCBF43926'u32
let icon = iconPng(192)
doAssert icon[1 .. 3] == "PNG".toBytes and icon.len < 10_000, "a small PNG"

# deflate round trip, through a small inflater for fixed-Huffman blocks
proc inflateFixed(z: Bytes): Bytes =
  var pos = 0
  proc bit(): int =
    result = int(z[pos shr 3] shr (pos and 7)) and 1
    inc pos
  proc bits(n: int): int =
    for i in 0 ..< n: result = result or (bit() shl i)
  proc huff(n: int): int =
    for i in 0 ..< n: result = (result shl 1) or bit()
  const lenBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35,
                   43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
  const lenExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
                    4, 4, 4, 4, 5, 5, 5, 5, 0]
  const distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                    257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193,
                    12289, 16385, 24577]
  const distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8,
                     9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
  doAssert bit() == 1 and bits(2) == 1, "one fixed-Huffman block"
  while true:
    var c = huff(7)
    if c <= 0x17: c += 256
    else:
      c = (c shl 1) or bit()
      if c in 0x30 .. 0xBF: c -= 0x30
      elif c in 0xC0 .. 0xC7: c = c - 0xC0 + 280
      else: c = ((c shl 1) or bit()) - 0x190 + 144
    if c < 256: result.add byte(c)
    elif c == 256: break
    else:
      let li = c - 257
      let length = lenBase[li] + bits(lenExtra[li])
      let di = huff(5)
      let dist = distBase[di] + bits(distExtra[di])
      for k in 0 ..< length: result.add result[result.len - dist]

var sample: Bytes
for i in 0 ..< 70_000: sample.add byte((i * 7 + i div 300) mod 251)
sample.add "the quick brown fox jumps over the lazy dog, the quick brown fox".toBytes
for data in [sample, @[], "a".toBytes, readFile("tests/test_apk.nim").toBytes]:
  doAssert inflateFixed(deflate(data)) == data, "deflate round trip"
echo "apk tool tests passed"
