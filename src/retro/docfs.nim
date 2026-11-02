## Folders other apps share through Android's documents providers --
## Termux's home above all -- as if they were folders on disk.
##
## Android keeps every app's own files from the others. An app that wants
## to share them offers a documents provider (Termux does, for its home);
## another app asks the user once (`askDocAccess`: the system's folder
## picker), and is then given the folder for good. Termux names its
## documents by their paths ("/data/data/com.termux/files/home/notes.txt"),
## so they appear here under those paths: `listFolder`, the file jobs
## (copy, move, delete, zip), renaming and new folders work on them through
## the `v...` procs below, which fall back to the ordinary file procs for
## everything else -- on every other platform, that is all there is.

import std/[os, strutils, times, locks, hashes]
import uirelays/services

type
  DocRoot* = object
    tree*: string            ## the content:// address of the folder granted
    base*: string            ## its document id: the path it is shown under
  DocEntry* = object
    name*, path*: string
    isDir*: bool
    size*: int64
    modified*: Time

const
  DirMime = "vnd.android.document/directory"
  ## Apps whose files can be had through their documents provider: the
  ## folder they keep them in, the provider, the document to start in.
  knownProviders* = [
    (folder: "/data/data/com.termux/files", authority: "com.termux.documents",
     start: "/data/data/com.termux/files/home", app: "Termux", package: "com.termux")]

var
  rootsLock: Lock
  roots: seq[DocRoot]
  rootsLoaded: bool

initLock(rootsLock)

proc failed(r: string): bool {.inline.} = r == "\0"

proc refreshDocRoots*() {.gcsafe.} =
  ## Reads again which folders of other apps this app was given.
  let r = systemCall("trees", "")
  var found: seq[DocRoot]
  if not r.failed:
    for line in r.splitLines:
      let p = line.split('\t')
      # only providers that name their documents by paths
      if p.len >= 2 and p[1].startsWith("/"):
        found.add DocRoot(tree: p[0], base: p[1].strip(leading = false, chars = {'/'}))
  {.cast(gcsafe).}:
    withLock rootsLock:
      roots = found
      rootsLoaded = true

proc docRoots*(): seq[DocRoot] {.gcsafe.} =
  ## The folders of other apps this app was given.
  {.cast(gcsafe).}:
    if not rootsLoaded: refreshDocRoots()
    withLock rootsLock: result = roots

proc rootOf(path: string): DocRoot {.gcsafe.} =
  ## The granted folder `path` is in (`tree` "" when none).
  if path.len == 0 or path[0] != '/': return
  for r in docRoots():
    if (path == r.base or path.startsWith(r.base & "/")) and r.base.len > result.base.len:
      result = r

proc isDocPath*(path: string): bool {.gcsafe.} =
  ## `path` is in a folder of another app reached through its provider.
  rootOf(path).tree.len > 0

proc providerFor*(path: string): tuple[authority, start, app, package: string] =
  ## The provider that can give access to `path`, when it is in a known
  ## app's folder ("" when none).
  for p in knownProviders:
    if path == p.folder or path.startsWith(p.folder & "/"):
      return (p.authority, p.start, p.app, p.package)

proc needsDocAccess*(path: string): bool {.gcsafe.} =
  ## `path` is in the folder of another app (installed) that this app may
  ## not read by itself and that the user has not given it yet. (Inside
  ## Termux, its own files are simply files: false.)
  let p = providerFor(path)
  p.authority.len > 0 and not isDocPath(path) and not dirExists(path) and
    systemCall("installed", p.package) == "1"

proc askDocAccess*(path: string): bool {.discardable.} =
  ## Opens the system's folder picker at the provider of `path` (the user
  ## picks the folder and allows it); `refreshDocRoots` afterwards. False
  ## where this cannot be done.
  let p = providerFor(path)
  if p.authority.len == 0: return false
  not systemCall("treeAsk", p.authority & "\t" & p.start).failed

proc call(name: string; root: DocRoot; args: varargs[string]): string {.gcsafe.} =
  var a = root.tree
  for x in args: a.add '\t' & x
  systemCall(name, a)

# ---- reading --------------------------------------------------------------------------

proc docList*(dir: string): seq[DocEntry] {.gcsafe.} =
  ## The documents in the folder `dir`. Raises `OSError` when it fails.
  let root = rootOf(dir)
  let r = call("list", root, dir)
  if root.tree.len == 0 or r.failed:
    raise newException(OSError, "cannot read " & dir)
  for line in r.splitLines:
    let p = line.split('\t')
    if p.len < 6: continue
    result.add DocEntry(path: p[0], name: p[1], isDir: p[2] == DirMime,
                        size: (try: parseBiggestInt(p[3]) except ValueError: 0),
                        modified: fromUnix((try: parseBiggestInt(p[4]) except ValueError: 0) div 1000))

proc docStat*(path: string): tuple[exists, isDir: bool; size: int64; modified: Time] {.gcsafe.} =
  ## Whether the document is there, whether it is a folder, its size and
  ## when it was last changed (all empty when it cannot be asked).
  let root = rootOf(path)
  if root.tree.len == 0: return
  let r = call("stat", root, path)
  if r.failed: return
  let p = r.split('\t')
  if p.len < 4: return
  (true, p[1] == DirMime, (try: parseBiggestInt(p[2]) except ValueError: 0'i64),
   fromUnix((try: parseBiggestInt(p[3]) except ValueError: 0) div 1000))

proc docOpen*(path: string; mode: FileMode): File {.gcsafe.} =
  ## The document as an open file (`fmRead`, `fmWrite`: emptied first).
  ## Raises `IOError` when it cannot be opened.
  let root = rootOf(path)
  let m = if mode == fmRead: "r" else: "wt"
  let r = call("open", root, path, m)
  var fd = -1
  if not r.failed:
    try: fd = parseInt(r) except ValueError: discard
  if fd < 0 or not open(result, FileHandle(fd), mode):
    raise newException(IOError, "cannot open " & path.extractFilename)

# ---- the v... procs: documents, or the files on disk ------------------------------------

proc vIsDir*(p: string): bool {.gcsafe.} =
  ## A folder (not a link to one).
  if isDocPath(p): docStat(p).isDir else: dirExists(p) and not symlinkExists(p)

proc vExists*(p: string): bool {.gcsafe.} =
  ## A file or folder (or a link) is at `p`.
  if isDocPath(p): docStat(p).exists
  else: fileExists(p) or dirExists(p) or symlinkExists(p)

proc vSize*(p: string): int64 {.gcsafe.} =
  ## The size of the file in bytes (0 when it cannot be read).
  if isDocPath(p): docStat(p).size
  else: (try: getFileSize(p) except OSError: 0)

proc vModTime*(p: string): Time {.gcsafe.} =
  ## When the file was last changed (an empty `Time` when it cannot be read).
  if isDocPath(p): docStat(p).modified
  else: (try: getLastModificationTime(p) except OSError: Time())

proc vWalk*(dir: string): seq[tuple[kind: PathComponent; path: string]] {.gcsafe.} =
  ## What `walkDir` gives, for documents too. Raises `OSError`.
  if isDocPath(dir):
    for e in docList(dir):
      let k = if e.isDir: pcDir else: pcFile
      result.add (k, e.path)
  else:
    for kind, p in walkDir(dir): result.add (kind, p)

proc vCreate(parent, name: string; dir: bool): string =
  let root = rootOf(parent)
  let mime = if dir: DirMime else: "application/octet-stream"
  let r = call("create", root, parent, mime, name)
  if r.failed or r.len == 0:
    raise newException(OSError, "cannot make " & name)
  r

proc vMkdir*(p: string) =
  ## Makes the folder `p` (and the ones above it, on disk).
  if isDocPath(p.parentDir):
    if not vIsDir(p): discard vCreate(p.parentDir, p.extractFilename, true)
  else: createDir(p)

proc vOpen*(p: string; mode: FileMode): File =
  ## The file `p` opened (`fmWrite`: made if it is not there). Raises `IOError`.
  if isDocPath(p.parentDir) or isDocPath(p):
    if mode != fmRead and not docStat(p).exists:
      discard vCreate(p.parentDir, p.extractFilename, false)
    return docOpen(p, mode)
  if not open(result, p, mode):
    raise newException(IOError, "cannot open " & p.extractFilename)

proc vReadFile*(p: string): string =
  ## The whole file as a string. Raises `IOError`.
  if not isDocPath(p): return readFile(p)
  var f = vOpen(p, fmRead)
  defer: f.close()
  f.readAll()

proc vWriteFile*(p, data: string) =
  ## Writes `data` as the whole file (made if it is not there). Raises
  ## `IOError`.
  if not isDocPath(p.parentDir):
    writeFile(p, data)
    return
  var f = vOpen(p, fmWrite)
  defer: f.close()
  f.write(data)

proc vRemoveFile*(p: string) =
  ## Deletes the file. Raises `OSError`.
  if isDocPath(p):
    if call("delete", rootOf(p), p).failed:
      raise newException(OSError, "cannot delete " & p.extractFilename)
  else: removeFile(p)

proc vRemoveDir*(p: string) =
  ## Deletes the folder and what is in it. Raises `OSError`.
  if isDocPath(p): vRemoveFile(p)        # (providers delete what is inside too)
  else: removeDir(p)

proc vCopyFile*(src, dst: string) {.gcsafe.} =
  ## Copies a file, between documents and files on disk in any direction.
  var f = vOpen(src, fmRead)
  defer: f.close()
  var g = vOpen(dst, fmWrite)
  defer: g.close()
  var buf = newString(1 shl 20)
  while true:
    let n = f.readBuffer(addr buf[0], buf.len)
    if n > 0 and g.writeBuffer(addr buf[0], n) != n:
      raise newException(IOError, "the disk is full")
    if n < buf.len: break

proc copyTree(s, d: string) =
  ## `s` (a file or a folder with all in it) copied to the path `d`.
  if vIsDir(s):
    vMkdir(d)
    for (kind, p) in vWalk(s): copyTree(p, d / p.extractFilename)
  else: vCopyFile(s, d)

proc vRename*(p, newName: string): string =
  ## Gives `p` the name `newName`; the new path. (A provider that cannot
  ## rename -- Termux's -- gets a copy under the new name, and the old one
  ## deleted.)
  if isDocPath(p):
    let r = call("rename", rootOf(p), p, newName)
    if not r.failed and r.len > 0: return r
    let t = p.parentDir / newName
    if vExists(t): raise newException(OSError, newName & " already exists")
    copyTree(p, t)
    if vIsDir(p): vRemoveDir(p) else: vRemoveFile(p)
    return t
  let t = p.parentDir / newName
  if dirExists(p) and not symlinkExists(p): moveDir(p, t) else: moveFile(p, t)
  t

proc vMove*(src, dst: string) =
  ## Moves `src` to the path `dst`. Within one folder of another app: its
  ## provider moves it; across, or between it and the disk: copied, then
  ## deleted.
  let a = isDocPath(src)
  let b = isDocPath(dst.parentDir)
  if not a and not b:
    if dirExists(src) and not symlinkExists(src): moveDir(src, dst) else: moveFile(src, dst)
    return
  if a and b and rootOf(src).tree == rootOf(dst.parentDir).tree:
    if src.parentDir == dst.parentDir:
      discard vRename(src, dst.extractFilename)
      return
    let r = call("move", rootOf(src), src, src.parentDir, dst.parentDir)
    if not r.failed and r.len > 0:           # (else: copied below)
      if r.extractFilename != dst.extractFilename: discard vRename(r, dst.extractFilename)
      return
  # across (or a provider that cannot move): copied, then the original deleted
  copyTree(src, dst)
  if vIsDir(src): vRemoveDir(src) else: vRemoveFile(src)

proc localCopy*(p: string; cacheDir: string; maxBytes = 256 shl 20): string =
  ## `p` itself when it is on disk; for a document, a copy of it in
  ## `cacheDir` (made again when the document changed) that other code and
  ## other apps can open; "" when it is bigger than `maxBytes` or cannot be
  ## read.
  if not isDocPath(p): return p
  let st = docStat(p)
  if not st.exists or st.isDir or st.size > maxBytes: return ""
  let dir = cacheDir / $(hash(p) and 0x7FFFFFFF)
  let local = dir / p.extractFilename
  try:
    if fileExists(local) and getFileSize(local) == st.size and
       getLastModificationTime(local) == st.modified: return local
    createDir(dir)
    vCopyFile(p, local)
    setLastModificationTime(local, st.modified)
    local
  except CatchableError:
    ""
