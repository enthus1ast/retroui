## Thumbnails kept on disk: the small pictures of files that are slow to
## make (camera raw photos, videos, PDFs, Photoshop documents, big JPEGs)
## are written to a cache folder the first time and read from there after
## -- a folder of photos opens at once the second time, also after the
## program was closed.
##
## `useThumbCache` turns it on (`retroui/background` then uses it for every
## picture asked for at thumbnail size, on its worker threads); a file's
## thumbnails are told apart by its path, size and time, so a changed file
## gets new ones. The folder is kept under its limit (the least recently
## used go first) by the worker that writes past it.
##
## .. code-block:: nim
##   useThumbCache(thumbCacheFolder("Retro Files"), 96 * 1024 * 1024)

import std/[os, times, strutils, algorithm, locks]
import uirelays/target   # (androidApp: an APK, not a program in Termux)
import gfx, imaging, jpeg
when androidApp or defined(ios):
  import uirelays/services     # (a phone's app's folder: `cacheFolder`)

const
  thumbMaxSide* = 512
    ## Pictures asked for up to this size (pixels, the longer side) are
    ## kept; larger ones (a preview pane, a viewer) are not.
  slowKinds = [".dng", ".nef", ".nrw", ".arw", ".srf", ".sr2", ".cr2", ".cr3", ".crw", ".orf",
               ".rw2", ".pef", ".raf", ".3fr", ".erf", ".kdc", ".mrw", ".srw", ".x3f", ".iiq",
               ".rwl", ".psd", ".psb", ".rpd", ".rp3", ".pdf", ".ai", ".svg", ".heic", ".heif",
               ".avif", ".jxl", ".tif", ".tiff", ".exr", ".hdr", ".webp", ".mp4", ".m4v", ".mov",
               ".mkv", ".webm", ".avi", ".3gp", ".mpg", ".mpeg", ".wmv", ".flv", ".ts"]

var
  lock: Lock
  root: string                 # guarded by lock ("" : off)
  limit: int64                 # guarded by lock
  bytes = -1'i64               # guarded by lock (-1: not counted yet)
  trimming = false             # guarded by lock

initLock(lock)

proc cacheFolder*(app: string): string =
  ## The system's folder for `app`'s caches -- what can be made again, and
  ## may be emptied (Android does when the storage runs short): Windows'
  ## LocalAppData, ~/Library/Caches, XDG's cache folder (~/.cache); on a
  ## phone the app's own. Not made here.
  when androidApp:
    dataDir(app).parentDir / "cache"
  elif defined(ios):
    dataDir(app) / "Caches"
  else:
    let name = app.multiReplace(("/", "_"), ("\\", "_"), (":", "_"))
    when defined(windows): getEnv("LOCALAPPDATA", getHomeDir() / "AppData" / "Local") / name
    elif defined(macosx): getHomeDir() / "Library" / "Caches" / name
    else: (let x = getEnv("XDG_CACHE_HOME"); if x.len > 0: x else: getHomeDir() / ".cache") / name

proc thumbCacheFolder*(app: string): string =
  ## Where `app` keeps its thumbnails: in its folder for caches
  ## (`cacheFolder`).
  cacheFolder(app) / (when defined(windows) or defined(macosx): "Thumbnails" else: "thumbnails")

proc useThumbCache*(folder: string; maxBytes = 96'i64 * 1024 * 1024) =
  ## Keep thumbnails in `folder`, no more than `maxBytes` of them; "" turns
  ## the cache off.
  withLock lock:
    {.cast(gcsafe).}:
      root = folder
      limit = max(1'i64 * 1024 * 1024, maxBytes)
      bytes = -1
  if folder.len > 0:
    try: createDir(folder) except OSError, IOError: discard

proc thumbCacheOn*(): bool =
  ## Thumbnails are kept on disk.
  withLock lock:
    {.cast(gcsafe).}: result = root.len > 0

proc rootNow(): string =
  withLock lock:
    {.cast(gcsafe).}: result = root

proc fnv(s: string; h: uint64): uint64 =
  result = h
  for c in s:
    result = (result xor uint64(ord(c))) * 0x100000001b3'u64

proc thumbName(path: string; side: int; info: FileInfo): string =
  ## The cache's name for `path`'s thumbnail of `side` pixels.
  let key = path & "\0" & $info.size & "\0" & $info.lastWriteTime.toUnix &
            "." & $info.lastWriteTime.nanosecond
  let a = fnv(key, 0xcbf29ce484222325'u64)
  let b = fnv(key, 0x84222325cbf29ce4'u64)
  let hex = a.toHex(16).toLowerAscii & b.toHex(8).toLowerAscii
  hex[0 .. 1] / hex[2 .. ^1] & "-" & $side

proc worthKeeping*(path: string; size: int64 = -1): bool =
  ## A file whose thumbnail is slow to make: a kind that takes long to
  ## decode, or a picture larger than 256 KB.
  let dot = path.rfind('.')
  if dot >= 0 and path[dot .. ^1].toLowerAscii in slowKinds: return true
  var s = size
  if s < 0:
    try: s = getFileSize(path) except OSError, IOError: return false
  s >= 256 * 1024

proc cachedThumb*(path: string; side: int): Bitmap =
  ## `path`'s thumbnail of `side` pixels from the cache, nil when it has
  ## none (any thread).
  let r = rootNow()
  if r.len == 0: return nil
  try:
    let info = getFileInfo(path)
    let base = r / thumbName(path, side, info)
    for ext in [".jpg", ".png"]:
      let f = base & ext
      if fileExists(f):
        let data = readFile(f)
        result = if ext == ".jpg": decodeJpeg(data) else: decodePng(data)
        if result != nil and result.w > 0:
          try: setLastModificationTime(f, getTime())   # (used: kept longer)
          except OSError: discard
          return
        result = nil
  except CatchableError, Defect:
    result = nil

proc folderSize(dir: string; limitFiles = 200_000): int64 =
  var n = 0
  try:
    for f in walkDirRec(dir):
      inc n
      if n > limitFiles: break
      try: result += getFileSize(f) except OSError: discard
  except OSError: discard

proc trimTo(dir: string; target: int64): int64 =
  ## Deletes the least recently used thumbnails until the folder holds no
  ## more than `target` bytes; returns what it holds then.
  var files: seq[tuple[t: int64; size: int64; path: string]]
  var total = 0'i64
  try:
    for f in walkDirRec(dir):
      if files.len >= 200_000: break
      try:
        let i = getFileInfo(f)
        files.add (i.lastWriteTime.toUnix, i.size, f)
        total += i.size
      except OSError: discard
  except OSError: discard
  if total <= target: return total
  files.sort(proc (a, b: (int64, int64, string)): int = cmp(a[0], b[0]))
  for (t, size, f) in files:
    if total <= target: break
    try:
      removeFile(f)
      total -= size
    except OSError: discard
  total

proc keepThumb*(path: string; side: int; b: Bitmap) =
  ## Writes `path`'s thumbnail `b` (of `side` pixels) to the cache (any
  ## thread): a JPEG when it is opaque, else a PNG. The folder is trimmed
  ## when it grows past its limit.
  let r = rootNow()
  if r.len == 0 or b == nil or b.w <= 0 or b.h <= 0: return
  try:
    let info = getFileInfo(path)
    let base = r / thumbName(path, side, info)
    var opaque = true
    for p in b.px:
      if (p shr 24) != 255:
        opaque = false
        break
    let data = if opaque: encodeJpeg(b, 84, chroma420 = true) else: encodePng(b, level = 2)
    let f = base & (if opaque: ".jpg" else: ".png")
    createDir(f.parentDir)
    let tmp = f & ".part" & $getThreadId()
    writeFile(tmp, data)
    moveFile(tmp, f)                        # (whole, or not at all)
    var trim = false
    var target = 0'i64
    withLock lock:
      {.cast(gcsafe).}:
        if bytes >= 0: bytes += data.len
        if not trimming and (bytes < 0 or bytes > limit):
          trimming = true
          trim = true
          target = limit * 3 div 4
    if trim:
      # (one worker counts -- the first time -- and trims; the others go on)
      var now = folderSize(r)
      if now > target * 4 div 3: now = trimTo(r, target)
      withLock lock:
        {.cast(gcsafe).}:
          bytes = now
          trimming = false
  except CatchableError, Defect:
    discard

proc thumbCacheBytes*(): int64 =
  ## What the cache folder holds (bytes; it is walked: not every frame).
  let r = rootNow()
  if r.len == 0: 0'i64 else: folderSize(r)

proc clearThumbCache*() =
  ## Deletes every thumbnail kept.
  let r = rootNow()
  if r.len == 0: return
  try:
    for kind, p in walkDir(r):
      if kind in {pcDir, pcLinkToDir}: removeDir(p)
      else: removeFile(p)
  except OSError: discard
  withLock lock:
    bytes = 0
