## Another app's files through its documents provider (Termux's home on
## Android) -- with a fake provider that keeps the documents in a scratch
## folder, answering as Android's Storage Access Framework would (and, like
## Termux's provider, unable to rename or move).

import std/[os, strutils, posix, times, algorithm]
import retro
import retro/[files, zip, imaging, gfx]
import retro/uirelays/[input, services]
import harness

const
  Home = "/data/data/com.termux/files/home"
  DirMime = "vnd.android.document/directory"

let disk = getTempDir() / "retro-docfs-provider"   # the provider's files
let root = getTempDir() / "retro-docfs-local"      # this app's own files
for d in [disk, root]:
  removeDir(d)
  createDir(d)
createDir(disk / "sub")
writeFile(disk / "notes.txt", "hello")
writeFile(disk / "sub" / "inner.txt", "inside")

var granted = false
var asked = 0

proc real(id: string): string =
  ## Where the document `id` (a path under Home) is kept.
  if id == Home: disk
  elif id.startsWith(Home & "/"): disk / id[Home.len + 1 .. ^1]
  else: ""

proc row(id, p: string): string =
  let dir = dirExists(p)
  id & "\t" & p.extractFilename & "\t" & (if dir: DirMime else: "text/plain") & "\t" &
    $(if dir: 0'i64 else: getFileSize(p)) & "\t" &
    $(getLastModificationTime(p).toUnix * 1000)

systemRelays.call = proc (name, arg: string): string {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    let a = arg.split('\t')
    case name
    of "installed": return (if a[0] == "com.termux": "1" else: "0")
    of "treeAsk":
      inc asked
      granted = true                       # (the user allows it)
      return ""
    of "trees":
      return (if granted: "content://com.termux.documents/tree/home\t" & Home & "\n" else: "")
    else: discard
    if not granted or a.len < 2: return "\0"
    let p = real(a[1])
    if p.len == 0: return "\0"
    case name
    of "list":
      if not dirExists(p): return "\0"
      var lines: seq[string]
      for kind, q in walkDir(p):
        lines.add row(a[1] & "/" & q.extractFilename, q) & "\t0"
      lines.join("\n")
    of "stat":
      if not (fileExists(p) or dirExists(p)): return "\0"
      let r = row(a[1], p).split('\t')
      r[1 .. ^1].join("\t")
    of "open":
      let flags = if a[2] == "r": O_RDONLY else: O_WRONLY or O_CREAT or O_TRUNC
      let fd = posix.open(p.cstring, flags, 0o644)
      if fd < 0: "\0" else: $fd
    of "create":
      let id = a[1] & "/" & a[3]
      if a[2] == DirMime: createDir(real(id)) else: writeFile(real(id), "")
      id
    of "delete":
      if dirExists(p): removeDir(p) elif fileExists(p): removeFile(p) else: return "\0"
      "1"
    else: "\0"                             # rename, move: not offered

proc finish(j: FileJob) =
  while j.state == jsRunning: j.run(5)

proc names(dir: string): seq[string] =
  for kind, p in walkDir(dir): result.add p.extractFilename
  result.sort()

fakeDriver()
startApp("docfs", W, H)

block notGivenYet:
  doAssert needsDocAccess(Home), "Termux's home needs the user's yes"
  doAssert not isDocPath(Home)
  doAssert not needsDocAccess(root), "the app's own files do not"
  doAssert providerFor(Home / "x").app == "Termux"

block askThenList:
  let m = newFolderModel(Home)
  view = proc () = discard fileList(m, fvDetails)
  run(2)
  doAssert m.needsAccess and m.dir == Home and m.items.len == 0
  doAssert m.accessApp == "Termux"
  if existsEnv("DOCFS_SHOT"):                # (a look at the offer)
    let b = newBitmap(W, H)
    for i in 0 ..< W * H: b.px[i] = pixels[i] or 0xFF000000'u32
    writeFile(getEnv("DOCFS_SHOT"), encodePng(b))
  key(KeyEnter)                            # "Allow access" is the default button
  run(2)
  doAssert asked == 1, "the folder picker was asked for"
  # looked at again until it is given; then listed (on a worker thread)
  var guard = 0
  while (m.needsAccess or m.items.len == 0) and guard < 400:
    run()
    os.sleep(5)
    inc guard
  doAssert not m.needsAccess and isDocPath(Home)
  var got: seq[string]
  for it in m.items: got.add it.name
  got.sort()
  doAssert got == @["notes.txt", "sub"], $got
  doAssert vIsDir(Home / "sub") and not vIsDir(Home / "notes.txt")
  doAssert vExists(Home / "notes.txt") and not vExists(Home / "nope")
  doAssert vSize(Home / "notes.txt") == 5
  doAssert subFolders(Home) == @[Home / "sub"]
  view = proc () = discard            # (`m` ends with this block)

block readWrite:
  doAssert vReadFile(Home / "notes.txt") == "hello"
  vWriteFile(Home / "new.txt", "made here")
  doAssert readFile(disk / "new.txt") == "made here"
  vWriteFile(Home / "new.txt", "again")
  doAssert readFile(disk / "new.txt") == "again", "written over, not added to"
  vMkdir(Home / "made")
  doAssert dirExists(disk / "made")
  # a copy this app (and other code) can open, made again when it changed
  let c = localCopy(Home / "notes.txt", root / "cache")
  doAssert c.len > 0 and c.startsWith(root) and readFile(c) == "hello"
  doAssert localCopy(root / "x.txt", root / "cache") == root / "x.txt",
    "files on disk are themselves"

block renameWithoutTheProvider:
  # Termux's provider cannot rename: a copy under the new name, the old deleted
  let p = vRename(Home / "new.txt", "renamed.txt")
  doAssert p == Home / "renamed.txt"
  doAssert readFile(disk / "renamed.txt") == "again" and not fileExists(disk / "new.txt")
  let d = vRename(Home / "made", "folder")
  doAssert d == Home / "folder" and dirExists(disk / "folder") and not dirExists(disk / "made")

block jobs:
  # into the other app's folder, from this app's files
  writeFile(root / "local.txt", "local")
  createDir(root / "tree" / "deep")
  writeFile(root / "tree" / "deep" / "x.txt", "xx")
  let cp = newJob(jkCopy, [root / "local.txt", root / "tree"], Home)
  cp.finish()
  doAssert cp.state == jsDone and cp.errors.len == 0, $cp.errors
  doAssert readFile(disk / "local.txt") == "local"
  doAssert readFile(disk / "tree" / "deep" / "x.txt") == "xx"
  # a taken name asks, as on disk
  let again = newJob(jkCopy, [root / "local.txt"], Home)
  again.finish()
  doAssert again.state == jsAsking and again.conflict == "local.txt"
  again.resolve(cfKeepBoth)
  again.finish()
  doAssert fileExists(disk / "local (2).txt")
  # moved within it (the provider cannot: copied and deleted)
  let mv = newJob(jkMove, [Home / "renamed.txt"], Home / "sub")
  mv.finish()
  doAssert mv.state == jsDone and mv.errors.len == 0, $mv.errors
  doAssert fileExists(disk / "sub" / "renamed.txt") and not fileExists(disk / "renamed.txt")
  # out of it, to this app's files
  createDir(root / "out")
  let outJob = newJob(jkCopy, [Home / "sub"], root / "out")
  outJob.finish()
  doAssert outJob.errors.len == 0, $outJob.errors
  doAssert names(root / "out" / "sub") == @["inner.txt", "renamed.txt"]
  doAssert readFile(root / "out" / "sub" / "inner.txt") == "inside"
  # moved out: copied, then deleted there
  let mo = newJob(jkMove, [Home / "local (2).txt"], root / "out")
  mo.finish()
  doAssert fileExists(root / "out" / "local (2).txt") and not fileExists(disk / "local (2).txt")
  # zipped from it, unzipped into it
  let z = newJob(jkZip, [Home / "sub"], root / "sub.zip")
  z.finish()
  doAssert z.errors.len == 0, $z.errors
  var entries: seq[string]
  for e in zipEntries(root / "sub.zip"): entries.add e.name
  doAssert "sub/inner.txt" in entries, $entries
  let u = newJob(jkUnzip, [root / "sub.zip"], Home / "folder")
  u.finish()
  doAssert u.errors.len == 0, $u.errors
  doAssert readFile(disk / "folder" / "sub" / "inner.txt") == "inside"
  # deleted (for good: there is no trash there)
  let del = newJob(jkDelete, [Home / "tree", Home / "local.txt"])
  del.finish()
  doAssert del.errors.len == 0, $del.errors
  doAssert not dirExists(disk / "tree") and not fileExists(disk / "local.txt")

block undoACopy:
  writeFile(root / "undo.txt", "u")
  let cp = newJob(jkCopy, [root / "undo.txt"], Home)
  cp.finish()
  doAssert fileExists(disk / "undo.txt")
  remember(cp)
  let r = undo()
  doAssert r.error.len == 0, r.error
  doAssert not fileExists(disk / "undo.txt"), "a copy undone is deleted there"

block filesOfTheModel:
  # new folders and renames from the file list's model
  let m = newFolderModel(Home)
  view = proc () = discard fileList(m, fvDetails)
  var guard = 0
  while m.items.len == 0 and guard < 400:
    run()
    os.sleep(5)
    inc guard
  doAssert makeFolder(m, "Projects").len == 0
  doAssert dirExists(disk / "Projects")
  doAssert m.rename(Home / "Projects", "Work").len == 0
  doAssert dirExists(disk / "Work") and not dirExists(disk / "Projects")
  view = proc () = discard

removeDir(disk)
removeDir(root)
echo "docfs tests passed"
