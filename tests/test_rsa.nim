## RSA in plain Nim (retroui/rsa): what signing an APK needs without OpenSSL.

import std/strutils
import retroui/rsa

proc hex(b: openArray[byte]): string =
  for x in b: result.add x.toHex(2).toLowerAscii

block sha:
  doAssert hex(sha256(cast[seq[byte]]("abc"))) ==
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  doAssert hex(sha256(newSeq[byte]())) ==
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  var long = newSeq[byte](1000)
  for i in 0 ..< long.len: long[i] = byte(i * 7)
  doAssert sha256(long) != sha256(long[0 .. ^2]), "every byte counts"

block keys:
  let k = newRsaKey(1024)        # (smaller: quick)
  doAssert k.n.len == 128 and k.e == @[1'u8, 0, 1]
  let data = cast[seq[byte]]("the signed part of an APK")
  let sig = k.sign(data)
  doAssert sig.len == 128 and verify(k.n, k.e, data, sig)
  var other = data
  other[0] = byte('T')
  doAssert not verify(k.n, k.e, other, sig), "another message: no"
  # PEM: written and read back the same
  let back = readRsaKey(k.pem)
  doAssert back.n == k.n and back.d == k.d and back.p == k.p and back.qinv == k.qinv
  doAssert back.sign(data) == sig, "PKCS #1 v1.5 is the same each time"
  # the certificate holds the public key, signed by it
  let cert = k.selfSignedCert("CN=test, O=retro")
  doAssert cert[0] == 0x30 and cert.len > 300
  let pub = k.publicKeyDer
  var found = false
  for i in 0 .. cert.len - pub.len:
    if cert[i ..< i + pub.len] == pub:
      found = true
      break
  doAssert found, "the public key is in the certificate"
  # damaged or encrypted keys are refused
  try:
    discard readRsaKey("-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n")
    doAssert false
  except RsaError: discard

echo "rsa tests passed"
