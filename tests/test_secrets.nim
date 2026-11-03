## Tests of retro/secrets: round trips, missing names, overwriting,
## deleting, odd names and bytes, files that were changed or moved, and
## threads at once -- in a folder of their own (RETRO_SECRETS_DIR): the
## encrypted files on Linux, DPAPI on Windows:
##
## .. code-block:: sh
##   nim c -r --hints:off tests/test_secrets.nim
##   nim c --hints:off -d:mingw --cpu:amd64 -o:/tmp/test_secrets.exe tests/test_secrets.nim
##   WINEDEBUG=-all wine /tmp/test_secrets.exe

import std/[os, strutils, typedthreads]
import retro/secrets

let root = getTempDir() / "retro-secrets-test"
removeDir(root)
putEnv("RETRO_SECRETS_DIR", root)

const app = "Retro Test"
let folder = root / app

block missing:
  doAssert loadSecret(app, "nobody") == ""
  doAssert loadSecret("Another App", "nobody") == ""
  deleteSecret(app, "nobody")                       # (nothing to delete: no harm)
  doAssert not saveSecret(app, "", "x") and not saveSecret("", "x", "x")
  doAssert loadSecret(app, "") == ""

block roundTrip:
  let token = """{"accessToken":"eyJ0eXAiOiJKV1Qi.abc","refreshToken":"0.AXk-x","expiresAt":1.0}"""
  doAssert saveSecret(app, "account 1", token)
  doAssert loadSecret(app, "account 1") == token
  doAssert saveSecret(app, "account 2", "second")
  doAssert loadSecret(app, "account 2") == "second" and loadSecret(app, "account 1") == token
  # the file does not show what it keeps
  var shown = false
  for kind, p in walkDir(folder):
    if token in readFile(p) or "second" in readFile(p): shown = true
  doAssert not shown

block overwrite:
  doAssert saveSecret(app, "account 1", "newer")
  doAssert loadSecret(app, "account 1") == "newer"
  doAssert saveSecret(app, "account 1", "")
  doAssert loadSecret(app, "account 1") == ""
  doAssert saveSecret(app, "account 1", "newest")
  doAssert loadSecret(app, "account 1") == "newest"

block oddValues:
  var all = ""
  for i in 0 .. 255: all.add char(i)
  doAssert saveSecret(app, "bytes", all & "\0" & all)
  doAssert loadSecret(app, "bytes") == all & "\0" & all
  let big = "x".repeat(100_000)
  doAssert saveSecret(app, "big", big) and loadSecret(app, "big") == big

block oddNames:
  let names = ["user@example.com", "a/b\\c", "..", ".", "ü شيء", "a:b*c?d", "x".repeat(60),
                "ش".repeat(100), "ش".repeat(100) & "!"]       # (the long ones: cut, and told apart)
  for name in names:
    doAssert saveSecret(app, name, "v " & name), name
  for name in names:
    doAssert loadSecret(app, name) == "v " & name, name
  for kind, p in walkDir(root):                       # nothing outside the folder
    doAssert p == folder, p

block delete:
  doAssert saveSecret(app, "gone", "soon")
  deleteSecret(app, "gone")
  doAssert loadSecret(app, "gone") == ""
  deleteSecret(app, "gone")
  doAssert loadSecret(app, "account 2") == "second"

block changedOrMoved:
  doAssert saveSecret(app, "first", "one")
  doAssert saveSecret(app, "other", "two")
  let first = folder / "first.secret"
  let other = folder / "other.secret"
  doAssert fileExists(first) and fileExists(other)
  # a file put in the place of another name does not open as it
  copyFile(first, other)
  doAssert loadSecret(app, "other") == ""
  doAssert saveSecret(app, "other", "two")
  # a changed byte: nothing comes out
  var data = readFile(first)
  data[^2] = char(ord(data[^2]) xor 1)
  writeFile(first, data)
  doAssert loadSecret(app, "first") == ""
  doAssert saveSecret(app, "first", "one") and loadSecret(app, "first") == "one"
  # another app (its own key, or entropy) cannot open it
  createDir(root / "Other")
  copyFile(first, root / "Other" / "first.secret")
  when not defined(windows):
    doAssert saveSecret("Other", "own", "x")          # (makes its key)
  doAssert loadSecret("Other", "first") == ""

when not defined(windows):
  block permissions:
    doAssert getFilePermissions(folder) == {fpUserRead, fpUserWrite, fpUserExec}
    doAssert getFilePermissions(folder / "key") == {fpUserRead, fpUserWrite}
    doAssert getFilePermissions(folder / "first.secret") == {fpUserRead, fpUserWrite}
    doAssert getFileSize(folder / "key") == 32
    # without its key nothing opens
    let key = readFile(folder / "key")
    removeFile(folder / "key")
    doAssert loadSecret(app, "first") == ""
    writeFile(folder / "key", key)
    doAssert loadSecret(app, "first") == "one"

var threadOk: array[4, bool]

proc worker(n: int) {.thread.} =
  var ok = true
  for i in 0 ..< 25:
    let name = "thread " & $n & " " & $(i mod 3)
    let value = "value " & $n & " " & $i
    ok = ok and saveSecret(app, name, value) and loadSecret(app, name) == value
  threadOk[n] = ok

block threads:
  var ts: array[4, Thread[int]]
  for i in 0 ..< 4: createThread(ts[i], worker, i)
  joinThreads(ts)
  for i in 0 ..< 4: doAssert threadOk[i], "thread " & $i
  doAssert loadSecret(app, "thread 2 0") == "value 2 24"

removeDir(root)
echo "secrets: ok"
