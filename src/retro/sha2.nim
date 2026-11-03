## SHA-256 (FIPS 180-4) and HMAC-SHA-256 (RFC 2104) in plain Nim: for
## OAuth's PKCE (`retro/oauth`), checksums and signed requests. Safe on any
## thread.
##
## .. code-block:: nim
##   echo sha256Hex("abc")     # ba7816bf...f20015ad
##   var h = initSha256()      # a piece at a time (a big file)
##   h.update("ab")
##   h.update("c")
##   let digest = h.finish()   # 32 bytes

type
  Sha256* = object
    ## A SHA-256 being worked out a piece at a time.
    h: array[8, uint32]
    buf: array[64, byte]
    used: int                 # bytes waiting in `buf`
    total: uint64             # bytes seen

  Sha256Digest* = array[32, byte]
    ## The 32 bytes of a SHA-256.

const k: array[64, uint32] = [
  0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32, 0x3956c25b'u32, 0x59f111f1'u32,
  0x923f82a4'u32, 0xab1c5ed5'u32, 0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32,
  0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32, 0xe49b69c1'u32, 0xefbe4786'u32,
  0x0fc19dc6'u32, 0x240ca1cc'u32, 0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
  0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32, 0xc6e00bf3'u32, 0xd5a79147'u32,
  0x06ca6351'u32, 0x14292967'u32, 0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32,
  0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32, 0xa2bfe8a1'u32, 0xa81a664b'u32,
  0xc24b8b70'u32, 0xc76c51a3'u32, 0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
  0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32, 0x391c0cb3'u32, 0x4ed8aa4a'u32,
  0x5b9cca4f'u32, 0x682e6ff3'u32, 0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
  0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32]

proc rotr(x: uint32; n: int): uint32 {.inline.} = (x shr n) or (x shl (32 - n))

proc compress(s: var Sha256; p: ptr UncheckedArray[byte]) =
  var w: array[64, uint32]
  for i in 0 ..< 16:
    w[i] = (uint32(p[4*i]) shl 24) or (uint32(p[4*i+1]) shl 16) or
           (uint32(p[4*i+2]) shl 8) or uint32(p[4*i+3])
  for i in 16 ..< 64:
    let s0 = rotr(w[i-15], 7) xor rotr(w[i-15], 18) xor (w[i-15] shr 3)
    let s1 = rotr(w[i-2], 17) xor rotr(w[i-2], 19) xor (w[i-2] shr 10)
    w[i] = w[i-16] + s0 + w[i-7] + s1
  var a = s.h[0]
  var b = s.h[1]
  var c = s.h[2]
  var d = s.h[3]
  var e = s.h[4]
  var f = s.h[5]
  var g = s.h[6]
  var h = s.h[7]
  for i in 0 ..< 64:
    let t1 = h + (rotr(e, 6) xor rotr(e, 11) xor rotr(e, 25)) + ((e and f) xor ((not e) and g)) +
             k[i] + w[i]
    let t2 = (rotr(a, 2) xor rotr(a, 13) xor rotr(a, 22)) + ((a and b) xor (a and c) xor (b and c))
    h = g
    g = f
    f = e
    e = d + t1
    d = c
    c = b
    b = a
    a = t1 + t2
  s.h[0] += a
  s.h[1] += b
  s.h[2] += c
  s.h[3] += d
  s.h[4] += e
  s.h[5] += f
  s.h[6] += g
  s.h[7] += h

proc initSha256*(): Sha256 =
  ## A new SHA-256, nothing hashed yet.
  result.h = [0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32,
              0x510e527f'u32, 0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32]

proc update*(s: var Sha256; data: openArray[byte]) =
  ## Hashes `data` after what came before.
  var i = 0
  s.total += uint64(data.len)
  if s.used > 0:
    while i < data.len and s.used < 64:
      s.buf[s.used] = data[i]
      inc s.used
      inc i
    if s.used < 64: return
    compress(s, cast[ptr UncheckedArray[byte]](addr s.buf[0]))
    s.used = 0
  while data.len - i >= 64:
    compress(s, cast[ptr UncheckedArray[byte]](unsafeAddr data[i]))
    i += 64
  while i < data.len:
    s.buf[s.used] = data[i]
    inc s.used
    inc i

proc update*(s: var Sha256; data: openArray[char]) =
  ## Hashes the bytes of `data` (a string) after what came before.
  if data.len > 0:
    update(s, toOpenArray(cast[ptr UncheckedArray[byte]](unsafeAddr data[0]), 0, data.len - 1))

proc finish*(s: var Sha256): Sha256Digest =
  ## The SHA-256 of all that was given (`s` is used up).
  let bits = s.total * 8
  var pad: array[72, byte]
  pad[0] = 0x80
  let padLen = (if s.used < 56: 56 - s.used else: 120 - s.used)
  for i in 0 ..< 8: pad[padLen + i] = byte((bits shr (56 - 8 * i)) and 0xFF)
  update(s, pad.toOpenArray(0, padLen + 7))
  for i in 0 ..< 8:
    result[4*i] = byte(s.h[i] shr 24)
    result[4*i+1] = byte((s.h[i] shr 16) and 0xFF)
    result[4*i+2] = byte((s.h[i] shr 8) and 0xFF)
    result[4*i+3] = byte(s.h[i] and 0xFF)

proc sha256*(data: openArray[char]): Sha256Digest =
  ## The SHA-256 of `data` (a string).
  var s = initSha256()
  s.update(data)
  s.finish()

proc sha256*(data: openArray[byte]): Sha256Digest =
  ## The SHA-256 of `data`.
  var s = initSha256()
  s.update(data)
  s.finish()

proc toBinary*(d: Sha256Digest): string =
  ## The 32 bytes as a string.
  result = newString(32)
  for i in 0 ..< 32: result[i] = char(d[i])

proc toHex*(d: Sha256Digest): string =
  ## The 32 bytes as 64 lower-case hex digits.
  const digits = "0123456789abcdef"
  result = newStringOfCap(64)
  for b in d:
    result.add digits[int(b shr 4)]
    result.add digits[int(b and 15)]

proc sha256Hex*(data: openArray[char]): string =
  ## The SHA-256 of `data` as 64 lower-case hex digits.
  sha256(data).toHex

proc hmacSha256*(key, data: openArray[char]): Sha256Digest =
  ## HMAC-SHA-256 of `data` under `key` (RFC 2104).
  var k0: array[64, byte]
  if key.len > 64:
    let d = sha256(key)
    for i in 0 ..< 32: k0[i] = d[i]
  else:
    for i in 0 ..< key.len: k0[i] = byte(key[i])
  var pad: array[64, byte]
  for i in 0 ..< 64: pad[i] = k0[i] xor 0x36
  var inner = initSha256()
  inner.update(pad)
  inner.update(data)
  let ih = inner.finish()
  for i in 0 ..< 64: pad[i] = k0[i] xor 0x5c
  var outer = initSha256()
  outer.update(pad)
  outer.update(ih)
  outer.finish()
