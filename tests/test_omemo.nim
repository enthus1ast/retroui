## Tests of retroui/omemo: the cryptography against the RFCs' vectors
## (X25519, Ed25519, HKDF), XEdDSA (the identity's X25519 key and its
## Ed25519 signatures), AES-GCM, and two devices talking through the store
## as the server would carry it -- a session begun from a bundle, answers,
## messages out of order, one twice, a changed one, a device it was not for,
## and the store read back from its file.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

include ../src/retroui/omemo

proc unhex(s: string): string =
  for i in countup(0, s.len - 1, 2): result.add char(parseHexInt(s[i .. i + 1]))

proc hex(s: string): string =
  for c in s: result.add toHex(ord(c), 2).toLowerAscii

if not omemoAvailable():
  echo "test_omemo: skipped (no libcrypto 1.1.1 or later here)"
  quit 0

block rfc7748:
  let a = unhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
  doAssert hex(x25519Pub(a)) == "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"
  let bPub = unhex("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
  doAssert hex(x25519(a, bPub)) == "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"

block rfc8032:
  let seed = unhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
  doAssert hex(ed25519Pub(seed)) == "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  let sig = ed25519Sign(seed, "")
  doAssert hex(sig) == "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
  doAssert ed25519Verify(ed25519Pub(seed), "", sig)
  doAssert not ed25519Verify(ed25519Pub(seed), "x", sig)

block rfc5869:
  let okm = hkdf(repeat('\x0b', 22), unhex("000102030405060708090a0b0c"), unhex("f0f1f2f3f4f5f6f7f8f9"), 42)
  doAssert hex(okm) == "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"

block xeddsa:
  # the X25519 key of the identity is the Ed25519 key's (y from u), and its
  # signatures check with the X25519 key alone -- for keys of both signs
  var signs: array[2, int]
  for i in 0 ..< 40:
    let id = identityOf(randomBytes(32))
    var ed = id.edPub
    inc signs[int(byte(ed[31]) shr 7)]
    ed[31] = char(byte(ed[31]) and 0x7f)
    doAssert montToEd(id.pub) == ed, "y from u"
    let s = id.xedSign("a signed key " & $i)
    doAssert xedVerify(id.pub, "a signed key " & $i, s)
    doAssert not xedVerify(id.pub, "another " & $i, s)
    var bad = s
    bad[5] = char(byte(bad[5]) xor 1)
    doAssert not xedVerify(id.pub, "a signed key " & $i, bad)
  doAssert signs[0] > 0 and signs[1] > 0, "keys of both signs tried"

block gcm:
  let k = randomBytes(16)
  let iv = randomBytes(12)
  let (ct, tag) = aesGcmSeal(k, iv, "Hello, مرحبا")
  doAssert aesGcmOpen(k, iv, ct, tag) == "Hello, مرحبا"
  var bad = ct
  bad[0] = char(byte(bad[0]) xor 1)
  doAssertRaises(ValueError): discard aesGcmOpen(k, iv, bad, tag)

block files:
  # a file as the apps send it in an encrypted talk (aesgcm://)
  let data = "a voice message's bytes " & randomBytes(1000)
  let (up, secret) = encryptFile(data)
  doAssert up.len == data.len + 16 and secret.len == 88
  let u = aesgcmUrl("https://up.example.org/x/v.m4a", secret)
  doAssert u.isAesgcm and u.startsWith("aesgcm://up.example.org/x/v.m4a#")
  doAssert fetchUrlOf(u) == "https://up.example.org/x/v.m4a"
  doAssert decryptFile(u, up) == data
  var bad = up
  bad[3] = char(byte(bad[3]) xor 1)
  doAssertRaises(ValueError): discard decryptFile(u, bad)
  # one made with a 16-byte IV (older apps)
  let key = randomBytes(32)
  let iv = randomBytes(16)
  let (ct, tag) = aesGcmSeal(key, iv, "old style")
  var hexs = ""
  for c in iv & key: hexs.add toHex(ord(c), 2)
  doAssert decryptFile("aesgcm://h/f#" & hexs, ct & tag) == "old style"

block protobuf:
  var s = ""
  s.pbInt(2, 300)
  s.pbBytes(4, "abc")
  let f = pbFields(s)
  doAssert f.pbNum(2) == 300 and f[4] == "abc"
  doAssertRaises(ValueError): discard pbFields("\x22\x10ab")

# ---- two devices -----------------------------------------------------------------------------------

let dir = getTempDir() / "retro-omemo-test"
removeDir(dir)
var alice = omemoOpen(dir / "a", "alice@example.org")
var bob = omemoOpen(dir / "b", "bob@example.org/Phone")
doAssert bob.account == "bob@example.org"
doAssert alice.deviceId != bob.deviceId and alice.deviceId > 0
doAssert alice.preKeys.len == PreKeys
doAssert alice.omemoFingerprint.len == 32 * 2 + 7

proc bundleFrom(o: OmemoStore): Bundle =
  ## (what the server would give from the bundle `o` published)
  result = Bundle(identity: o.identity.pub, signed: o.signed.pub, signature: o.signedSig, signedId: o.signedId)
  for id, kp in o.preKeys: result.preKeys.add (id, kp.pub)

proc msgOf(fromJid, enc: string; carbon = false): XmppEvent =
  XmppEvent(kind: xeMessage, jid: fromJid, carbon: carbon,
            raw: "<message from='" & fromJid & "/x' type='chat'>" & enc & "<body>" & Fallback & "</body></message>")

proc devicesOf(o: OmemoStore; jid: string; ids: seq[int]) =
  for id in ids: o.deviceOf(jid, id).active = true

block talk:
  alice.devicesOf("bob@example.org", @[bob.deviceId])
  alice.bundles[key("bob@example.org", bob.deviceId)] = bundleFrom(bob)
  let pkBefore = bob.preKeys.len
  # alice begins: a PreKey message
  let e1 = alice.encryptFor("bob@example.org", "Hi Bob, it is Alice.")
  doAssert e1.len > 0 and "prekey='true'" in e1
  let (ok1, t1, why1) = bob.omemoDecrypt(msgOf("alice@example.org", e1))
  doAssert ok1, why1
  doAssert t1 == "Hi Bob, it is Alice."
  doAssert bob.republish and bob.preKeys.len == pkBefore, "the one-time key used, a new one made"
  # alice again before bob answers: still a PreKey message, the same session for bob
  let e2 = alice.encryptFor("bob@example.org", "Still there?")
  doAssert "prekey='true'" in e2
  let (ok2, t2, _) = bob.omemoDecrypt(msgOf("alice@example.org", e2))
  doAssert ok2 and t2 == "Still there?"
  # bob answers (alice's device known to him by now)
  bob.devicesOf("alice@example.org", @[alice.deviceId])
  doAssert bob.devices["alice@example.org"][0].identity == alice.identity.pub
  let r1 = bob.encryptFor("alice@example.org", "Yes! وصلت.")
  doAssert r1.len > 0 and "prekey" notin r1
  let (ok3, t3, why3) = alice.omemoDecrypt(msgOf("bob@example.org", r1))
  doAssert ok3, why3
  doAssert t3 == "Yes! وصلت."
  # now alice's are plain messages
  let m1 = alice.encryptFor("bob@example.org", "one")
  let m2 = alice.encryptFor("bob@example.org", "two")
  let m3 = alice.encryptFor("bob@example.org", "three")
  doAssert "prekey" notin m1
  # out of order: three, then one, then two
  for (m, want) in [(m3, "three"), (m1, "one"), (m2, "two")]:
    let (ok, t, why) = bob.omemoDecrypt(msgOf("alice@example.org", m))
    doAssert ok and t == want, want & ": " & why
  # the same message again: no
  let (okDup, _, _) = bob.omemoDecrypt(msgOf("alice@example.org", m2))
  doAssert not okDup, "a message read twice"
  # a changed message: no
  var bad = m1.replace("<payload>", "<payload>AAAA")
  let (okBad, _, _) = bob.omemoDecrypt(msgOf("alice@example.org", bad))
  doAssert not okBad
  # turns: each side ratchets on
  for i in 0 ..< 6:
    let a = alice.encryptFor("bob@example.org", "a" & $i)
    let (oa, ta, wa) = bob.omemoDecrypt(msgOf("alice@example.org", a))
    doAssert oa and ta == "a" & $i, wa
    let b = bob.encryptFor("alice@example.org", "b" & $i)
    let (ob, tb, wb) = alice.omemoDecrypt(msgOf("bob@example.org", b))
    doAssert ob and tb == "b" & $i, wb

block newSignedKey:
  # a month on: a new signed key; a session begun with the one before still opens
  var erin = omemoOpen(dir / "e", "erin@example.org")
  alice.devicesOf("erin@example.org", @[erin.deviceId])
  alice.bundles[key("erin@example.org", erin.deviceId)] = bundleFrom(erin)
  let before = erin.signedId
  erin.signedAt = epochTime() - 31 * 86400.0
  erin.omemoStart()
  doAssert erin.signedId == before + 1 and erin.oldSignedId == before
  let e = alice.encryptFor("erin@example.org", "begun with the old key")
  let (ok, t, why) = erin.omemoDecrypt(msgOf("alice@example.org", e))
  doAssert ok and t == "begun with the old key", why

block notForThisDevice:
  var carol = omemoOpen(dir / "c", "carol@example.org")
  let e = alice.encryptFor("bob@example.org", "for bob only")
  let (ok, _, why) = carol.omemoDecrypt(msgOf("alice@example.org", e))
  doAssert not ok and "not encrypted for this device" in why

block keptInItsFile:
  # both read back from their files: the sessions go on
  bob = omemoOpen(dir / "b", "bob@example.org")
  alice = omemoOpen(dir / "a", "alice@example.org")
  let e = alice.encryptFor("bob@example.org", "after a restart")
  let (ok, t, why) = bob.omemoDecrypt(msgOf("alice@example.org", e))
  doAssert ok and t == "after a restart", why
  let r = bob.encryptFor("alice@example.org", "here too")
  let (ok2, t2, why2) = alice.omemoDecrypt(msgOf("bob@example.org", r))
  doAssert ok2 and t2 == "here too", why2
  when defined(posix):
    doAssert getFilePermissions(alice.path) == {fpUserRead, fpUserWrite}, "the keys are yours alone"

block trust:
  # a verified device: the others of that person no longer get messages
  var bob2 = omemoOpen(dir / "b2", "bob@example.org")
  alice.devicesOf("bob@example.org", @[bob.deviceId, bob2.deviceId])
  alice.bundles[key("bob@example.org", bob2.deviceId)] = bundleFrom(bob2)
  let both = alice.encryptFor("bob@example.org", "to both")
  doAssert ("rid='" & $bob.deviceId & "'") in both and ("rid='" & $bob2.deviceId & "'") in both
  alice.omemoTrust("bob@example.org", bob.deviceId, tVerified)
  let one = alice.encryptFor("bob@example.org", "to the verified one")
  doAssert ("rid='" & $bob.deviceId & "'") in one and ("rid='" & $bob2.deviceId & "'") notin one
  alice.omemoTrust("bob@example.org", bob.deviceId, tDistrusted)
  doAssert alice.encryptFor("bob@example.org", "to none") == "" or
           ("rid='" & $bob.deviceId & "'") notin alice.encryptFor("bob@example.org", "to none")

block badSignature:
  # a bundle whose signed key is not signed by its identity: no session
  var dave = omemoOpen(dir / "d", "dave@example.org")
  var b = bundleFrom(dave)
  b.signed = newKeyPair().pub
  alice.devicesOf("dave@example.org", @[dave.deviceId])
  alice.bundles[key("dave@example.org", dave.deviceId)] = b
  doAssert alice.encryptFor("dave@example.org", "x") == ""

removeDir(dir)
echo "test_omemo: ok"
