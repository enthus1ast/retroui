## Where HR Book keeps its data: one file, sealed with the PIN (retroui/vault),
## written safely (a new file, then moved over the old one), with the last
## copies kept; backups that open on another tablet; and comparing a backup
## with what is here, to merge the two.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[json, os, times, tables, strutils, algorithm, sets]
import retroui/vault
import model

type
  Store* = object
    dir*: string
    key*: VaultKey
    opened*: bool
    dirty*: bool
    lastSave*: float
    lastCopy*: float

  BackupInfo* = object
    savedAt*: float
    device*: string
    employees*, hotels*, templates*: int

  EmpDiff* = object
    bak*, cur*: int            ## indexes (-1: not on that side)
    kind*: string              ## "new", "newer", "older", "removed", "same"
    fields*: seq[string]       ## the fields that differ

  Diff* = object
    info*: BackupInfo
    emps*: seq[EmpDiff]
    newCount*, newerCount*, olderCount*, removedCount*, sameCount*, onlyHere*: int
    hotelsChanged*, fieldsNew*, templatesNew*, groupsNew*: int

const
  DataName = "hrbook.data"
  Copies = 3

proc dataFile*(dir: string): string = dir / DataName

proc hasData*(dir: string): bool = fileExists(dataFile(dir))

proc writeSafely(path, data: string) =
  let tmp = path & ".part"
  writeFile(tmp, data)
  moveFile(tmp, path)

proc keepCopy(s: var Store) =
  ## The file as it was, kept as hrbook.data.1 .. .3 (at most every 10
  ## minutes): a way back from a mistake that was saved.
  let p = dataFile(s.dir)
  if not fileExists(p) or nowT() - s.lastCopy < 600: return
  for i in countdown(Copies - 1, 1):
    let a = p & "." & $i
    if fileExists(a): copyFile(a, p & "." & $(i + 1))
  copyFile(p, p & ".1")
  s.lastCopy = nowT()

proc save*(s: var Store; b: var Book) =
  ## Writes the book (sealed with the PIN's key).
  if not s.opened: return
  b.savedAt = nowT()
  let sealed = s.key.seal($b.toJson)
  createDir(s.dir)
  s.keepCopy()
  writeSafely(dataFile(s.dir), sealed)
  s.dirty = false
  s.lastSave = nowT()

proc create*(dir, pin: string; b: var Book): Store =
  ## A new data file for `b`, sealed with `pin`.
  result = Store(dir: dir, key: newVaultKey(pin), opened: true)
  result.save(b)

proc open*(dir, pin: string): (Store, Book) =
  ## Opens the data file with `pin`; `VaultError` when the PIN is wrong.
  let sealed = readFile(dataFile(dir))
  let key = vaultKeyFor(sealed, pin)
  let text = key.unseal(sealed)
  var j: JsonNode
  try: j = parseJson(text)
  except JsonParsingError, ValueError:
    raise newException(VaultError, "the data file is damaged")
  (Store(dir: dir, key: key, opened: true, lastSave: nowT()), fromJson(j))

proc close*(s: var Store) =
  s.key.wipe()
  s.opened = false

proc changePin*(s: var Store; b: var Book; newPin: string) =
  s.key = newVaultKey(newPin)
  s.save(b)

# ---- backups ------------------------------------------------------------------------------------

proc backupName*(): string =
  "HR Book " & now().format("yyyy-MM-dd HHmm") & ".hrbook"

proc writeBackup*(s: Store; b: Book; path: string) =
  ## The whole book in one file, sealed with the same PIN (it opens on
  ## another tablet with it).
  var copy = b
  copy.savedAt = nowT()
  createDir(path.parentDir)
  writeSafely(path, s.key.seal($copy.toJson))

proc readBackup*(path, pin: string): Book =
  let sealed = readFile(path)
  if not isSealed(sealed): raise newException(VaultError, path.extractFilename & " is not an HR Book backup")
  let text = vaultKeyFor(sealed, pin).unseal(sealed)
  try: result = fromJson(parseJson(text))
  except JsonParsingError, ValueError:
    raise newException(VaultError, "the backup is damaged")

# ---- comparing and merging ----------------------------------------------------------------------

proc empKey(e: Employee): string =
  ## A person's identity across tablets: the employee number (and hotel),
  ## for people added on two tablets separately.
  let n = e.get("empNo").strip.toUpperAscii
  if n.len > 0: n else: ""

proc diffFields(a, b: Employee): seq[string] =
  var keys = initHashSet[string]()
  for k in a.v.keys: keys.incl k
  for k in b.v.keys: keys.incl k
  for k in keys:
    if a.v.getOrDefault(k) != b.v.getOrDefault(k): result.add k
  if a.groups.sorted != b.groups.sorted: result.add "groups"
  result.sort()

proc findMatch(cur: Book; e: Employee): int =
  for i, c in cur.employees:
    if c.id == e.id: return i
  let k = empKey(e)
  if k.len > 0:
    for i, c in cur.employees:
      if empKey(c) == k and c.get("hotel") == e.get("hotel"): return i
  -1

proc compare*(cur, bak: Book): Diff =
  ## What the backup `bak` has that is not here, or is different.
  result.info = BackupInfo(savedAt: bak.savedAt, device: bak.device,
                           employees: bak.employees.len, hotels: bak.hotels.len,
                           templates: bak.templates.len)
  var seen = initHashSet[int]()
  for bi, e in bak.employees:
    let ci = findMatch(cur, e)
    var d = EmpDiff(bak: bi, cur: ci)
    if ci < 0:
      if e.deleted: continue
      d.kind = "new"
      inc result.newCount
    else:
      seen.incl ci
      let c = cur.employees[ci]
      d.fields = diffFields(c, e)
      if e.deleted and not c.deleted:
        if e.modified >= c.modified:
          d.kind = "removed"
          inc result.removedCount
        else:
          d.kind = "older"
          inc result.olderCount
      elif d.fields.len == 0 and e.deleted == c.deleted:
        d.kind = "same"
        inc result.sameCount
      elif e.modified > c.modified:
        d.kind = "newer"
        inc result.newerCount
      else:
        d.kind = "older"
        inc result.olderCount
    result.emps.add d
  for i, c in cur.employees:
    if i notin seen and not c.deleted: inc result.onlyHere
  for h in bak.hotels:
    let i = cur.hotelIndex(h.id)
    if i < 0 or h.modified > cur.hotels[i].modified: inc result.hotelsChanged
  for f in bak.fields:
    if not cur.hasField(f.key): inc result.fieldsNew
  for t in bak.templates:
    var found = false
    for c in cur.templates:
      if c.id == t.id: found = true
    if not found and not t.deleted: inc result.templatesNew
  for g in bak.groups:
    var found = false
    for c in cur.groups:
      if c.id == g.id: found = true
    if not found: inc result.groupsNew

proc merge*(cur: var Book; bak: Book; d: Diff; takeOlder: seq[bool] = @[]) =
  ## The backup merged in: new people added, and for each person in both
  ## the newer of the two kept (`takeOlder[i]`: take the backup's even when
  ## it is older). Hotels, fields, groups and letters: the newer of each;
  ## lists: everything in either.
  for i, x in d.emps:
    let e = bak.employees[x.bak]
    case x.kind
    of "new": cur.employees.add e
    of "newer", "removed":
      var keep = e
      keep.id = cur.employees[x.cur].id
      cur.employees[x.cur] = keep
    of "older":
      if i < takeOlder.len and takeOlder[i]:
        var keep = e
        keep.id = cur.employees[x.cur].id
        keep.modified = nowT()
        cur.employees[x.cur] = keep
    else: discard
  for h in bak.hotels:
    let i = cur.hotelIndex(h.id)
    if i < 0: cur.hotels.add h
    elif h.modified > cur.hotels[i].modified: cur.hotels[i] = h
  for f in bak.fields:
    var found = false
    for c in cur.fields.mitems:
      if c.key == f.key:
        found = true
        if f.modified > c.modified: c = f
    if not found: cur.fields.add f
  for k, l in bak.lists:
    var mine = cur.lists.getOrDefault(k)
    for x in l:
      if x notin mine: mine.add x
    cur.lists[k] = mine
  for k, v in bak.arabic:
    if not cur.arabic.hasKey(k): cur.arabic[k] = v
  for g in bak.groups:
    var found = false
    for c in cur.groups.mitems:
      if c.id == g.id:
        found = true
        if g.modified > c.modified: c = g
    if not found: cur.groups.add g
  for t in bak.templates:
    var found = false
    for c in cur.templates.mitems:
      if c.id == t.id:
        found = true
        if t.modified > c.modified: c = t
    if not found: cur.templates.add t
  var issuedKeys = initHashSet[string]()
  for i in cur.issued: issuedKeys.incl i.refNo & "|" & $i.at
  for i in bak.issued:
    if (i.refNo & "|" & $i.at) notin issuedKeys: cur.issued.add i
  cur.issued.sort(proc (a, b: Issued): int = cmp(a.at, b.at))
  for l in bak.layouts:
    var found = false
    for c in cur.layouts.mitems:
      if c.headers == l.headers:
        found = true
        if l.modified > c.modified: c = l
    if not found: cur.layouts.add l

proc replaceWith*(cur: var Book; bak: Book) =
  ## Everything as in the backup (this tablet keeps its own name).
  let dev = cur.device
  cur = bak
  cur.device = dev
