## Bringing old mail in and taking it out (retro/mailimport): Outlook Express
## 5/6 stores and Outlook Express 4 mailboxes made here as the formats lay
## them out (tests/data/mailimport keeps a copy: `-d:writeSamples` writes
## it), mbox round trips, .eml files, folders of all of them, and damaged
## files -- cut short, looping block chains and trees, wrong sizes, random
## mutations -- that must not crash or hang.

import std/[os, strutils, times, random, monotimes, algorithm, tables]
import retro/[mailimport, mime]

const data = currentSourcePath().parentDir / "data" / "mailimport"
let tmp = getTempDir() / "retro-mailimport-" & $getCurrentProcessId()
removeDir(tmp)
createDir(tmp)

proc utcTime(y, mo, d, h, mi, s: int): float =
  float(dateTime(y, Month(mo), MonthdayRange(d), HourRange(h), MinuteRange(mi), SecondRange(s),
                 zone = utc()).toTime.toUnix)

proc crlf(s: string): string = s.replace("\r\n", "\n").replace("\n", "\r\n")

# ---- Outlook Express files, as they are laid out ---------------------------------------------

proc put16(s: var string; i: int; v: int64) =
  for k in 0 .. 1: s[i + k] = char((v shr (8 * k)) and 0xFF)
proc put32(s: var string; i: int; v: int64) =
  for k in 0 .. 3: s[i + k] = char((v shr (8 * k)) and 0xFF)
proc add32(s: var string; v: int64) =
  for k in 0 .. 3: s.add char((v shr (8 * k)) and 0xFF)
proc le32(v: int64): string = add32(result, v)
proc le64(v: int64): string =
  add32(result, v and 0xFFFFFFFF'i64)
  add32(result, v shr 32)
proc pad(s: var string; n: int) =
  while s.len mod n != 0: s.add '\0'
proc rd32(s: string; i: int): int64 =
  int64(ord(s[i])) or (int64(ord(s[i+1])) shl 8) or (int64(ord(s[i+2])) shl 16) or
    (int64(ord(s[i+3])) shl 24)

const
  DbxHead = 0x24BC
  OeMagic = "\xCF\xAD\x12\xFE\xC5\xFD\x74\x6F\x66\xE3\xD1\x11\x9A\x4E\x00\xC0\x4F\xD7\x30\xBC"

proc fileTime(t: float): int64 = int64(t) * 10_000_000 + 116444736000000000'i64

type Attr = tuple[id: int, direct: bool, value: int64, data: string]

proc dbxStart(kind: char; infoLen: int): string =
  ## A file header (and the file info after it).
  result = newString(DbxHead)
  for i, c in OeMagic: result[i] = c
  result[4] = kind
  result.put32(0x1C, infoLen)
  result.add newString(infoLen)

proc infoObject(f: var string; attrs: seq[Attr]): int64 =
  ## Appends an info object: itself, the length of its body, the number of
  ## entries; the entries (id, and a value or where in the data it is); the data.
  result = f.len
  var entries, area: string
  for a in attrs:
    if a.direct: entries.add32((a.value shl 8) or int64(a.id or 0x80))
    else:
      entries.add32((int64(area.len) shl 8) or int64(a.id))
      area.add a.data
  var body = entries & area
  body.pad(4)
  f.add32(result)
  f.add32(body.len)
  f.add char(body.len and 0xFF)
  f.add char((body.len shr 8) and 0xFF)
  f.add char(attrs.len)
  f.add '\x01'
  f.add body

proc treeNode(f: var string; values: seq[int64]; cap: int; parent: int64): int64 =
  ## Appends the index tree of `values`, at most `cap` in a node: its root.
  if values.len == 0: return 0
  let at = f.len
  f.add newString(0x27C)
  var entries: seq[(int64, int64, int)]
  var left = 0'i64
  var leftCount = 0
  if values.len <= cap:
    for v in values: entries.add (v, 0'i64, 0)
  else:
    let rest = values.len - cap
    var sizes = newSeq[int](cap + 1)
    for k in 0 ..< rest: inc sizes[k mod (cap + 1)]
    var i = 0
    let c0 = values[i ..< i + sizes[0]]
    i += sizes[0]
    left = treeNode(f, c0, cap, at)
    leftCount = c0.len
    for e in 1 .. cap:
      let v = values[i]
      inc i
      let c = values[i ..< i + sizes[e]]
      i += sizes[e]
      entries.add (v, treeNode(f, c, cap, at), c.len)
  f.put32(at, at)
  f.put32(at + 8, left)
  f.put32(at + 12, parent)
  f.put32(at + 16, int64(entries.len) shl 8)
  f.put32(at + 20, leftCount)
  for k, (v, c, n) in entries:
    f.put32(at + 24 + 12 * k, v)
    f.put32(at + 28 + 12 * k, c)
    f.put32(at + 32 + 12 * k, n)
  int64(at)

proc messageBlocks(f: var string; raw: string; backwards = false): int64 =
  ## Appends `raw` as a chain of blocks (itself, 0x200, the length used, the
  ## next one; 0x200 bytes of data): the first one. `backwards`: the chain
  ## runs from the last block in the file to the first.
  let n = max(1, (raw.len + 0x1FF) div 0x200)
  var pos: seq[int]
  for k in 0 ..< n: pos.add f.len + k * 0x210
  if backwards: pos.reverse
  f.add newString(n * 0x210)
  for k in 0 ..< n:
    let at = pos[k]
    let a = k * 0x200
    let len = min(0x200, raw.len - a)
    f.put32(at, at)
    f.put32(at + 4, 0x200)
    f.put16(at + 8, len)
    f.put32(at + 12, if k + 1 < n: pos[k + 1] else: 0)
    for j in 0 ..< len: f[at + 16 + j] = raw[a + j]
  int64(pos[0])

type OeMsg = object
  raw: string
  flags: int64
  received: float

proc makeDbx(folderName: string; msgs: seq[OeMsg]; cap = 0x33; indirectAddress = false): string =
  ## An Outlook Express 5/6 folder: its messages' blocks, their info objects
  ## (index, flags, times, where the message is, subject) and the index tree.
  result = dbxStart('\xC5', 0x618)
  for i, c in folderName: result[DbxHead + 0x105 + i] = c
  var infos: seq[int64]
  for k, m in msgs:
    let blocks = messageBlocks(result, m.raw, backwards = k mod 2 == 1)
    var attrs: seq[Attr] = @[(0, true, int64(k + 1), "")]
    if m.flags < 1 shl 24: attrs.add (1, true, m.flags, "")
    else: attrs.add (1, false, 0'i64, le32(m.flags))
    attrs.add (2, false, 0'i64, le64(fileTime(m.received - 60)))
    if indirectAddress: attrs.add (4, false, 0'i64, le32(blocks))
    else: attrs.add (4, true, blocks, "")
    attrs.add (8, false, 0'i64, parseMime(m.raw).header("Subject") & "\0")
    if m.received > 0: attrs.add (0x12, false, 0'i64, le64(fileTime(m.received)))
    infos.add infoObject(result, attrs)
  let root = treeNode(result, infos, cap, 0)
  result.put32(0xC4, msgs.len)
  result.put32(0xE4, root)

type OeFolder = object
  id, parent: int64
  name, file, account: string
  special: int

proc makeFoldersDbx(folders: seq[OeFolder]): string =
  ## Folders.dbx: an info object for each folder (id, parent, name, file,
  ## account, special folder) and the index tree.
  result = dbxStart('\xC6', 0x108)
  var infos: seq[int64]
  for fo in folders:
    var attrs: seq[Attr]
    if fo.id != 0: attrs.add (0, true, fo.id, "")
    if fo.parent < 0: attrs.add (1, false, 0'i64, le32(0xFFFFFFFF'i64))
    elif fo.parent != 0: attrs.add (1, true, fo.parent, "")
    attrs.add (2, false, 0'i64, fo.name & "\0")
    if fo.file.len > 0: attrs.add (3, false, 0'i64, fo.file & "\0")
    if fo.account.len > 0: attrs.add (5, false, 0'i64, fo.account & "\0")
    attrs.add (6, true, 1'i64, "")
    if fo.special > 0: attrs.add (9, true, int64(fo.special), "")
    attrs.add (0x0A, true, 3'i64, "")
    infos.add infoObject(result, attrs)
  let root = treeNode(result, infos, 0x33, 0)
  result.put32(0xC4, folders.len)
  result.put32(0xE4, root)

proc makeMbx(raws: seq[string]): tuple[mbx: string, recs: seq[(int, int)]] =
  ## An Outlook Express 4 mailbox: "JMF6", the count, then a record for
  ## each message (a marker, its number, the record's size, the text's).
  var f = "JMF6"
  f.add32(0x00010003)
  f.add32(raws.len)
  f.add32(raws.len + 1)
  f.add32(0)
  f.add newString(0x54 - f.len)
  for k, r in raws:
    let at = f.len
    let rec = (16 + r.len + 3) and not 3
    f.add32(0x7F007F00)
    f.add32(k + 1)
    f.add32(rec)
    f.add32(r.len)
    f.add r
    f.pad(4)
    result.recs.add (at, rec)
  f.put32(16, f.len)
  result.mbx = f

proc makeIdx(recs: seq[(int, int)]; deleted: seq[bool]): string =
  ## The .idx beside it: "JMF9", the count; for each message its flags (1:
  ## deleted), number, where the entry is, its length, and the record's place and size.
  result = "JMF9"
  result.add32(0x00010004)
  result.add32(recs.len)
  result.add32(0)
  result.add32(1)
  result.add32(0x00010010)
  result.add newString(80 - result.len)
  for k, (at, rec) in recs:
    let e = result.len
    result.add newString(220)
    result.put32(e, if deleted[k]: 1 else: 0)
    result.put32(e + 8, k + 1)
    result.put32(e + 12, e)
    result.put32(e + 16, 220)
    result.put32(e + 20, at)
    result.put32(e + 24, rec)
  result.put32(12, result.len)

# ---- the messages ------------------------------------------------------------------------------

let welcome = crlf"""From: "Retro Mail" <hello@retro.example>
To: "Sultan Al Isaiee" <sultan@hotel.example>
Subject: Welcome to Retro Mail
Date: Mon, 3 Nov 2025 09:00:00 +0400
Message-ID: <welcome@retro.example>
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii

Hello! Your old mail is home again.
"""

let reportText = block:
  var t = ""
  for k in 1 .. 6:
    t.add "السلام عليكم، هذا هو التقرير الشهري لقسم الموارد البشرية رقم " & $k & ".\n"
  t
let pdf = block:
  var s = "%PDF-1.4\n"
  for k in 0 .. 767: s.add char(k mod 256)
  s
let report = buildMail(OutMail(
  fromAddr: MailAddress(name: "مريم البلوشي", email: "maryam@hotel.example"),
  to: @[MailAddress(name: "Sultan Al Isaiee", email: "sultan@hotel.example")],
  subject: "التقرير الشهري – نوفمبر", text: reportText, date: utcTime(2025, 11, 3, 6, 30, 0),
  messageId: "report@hotel.example",
  attachments: @[MailAttachment(filename: "تقرير.pdf", data: pdf)]))

let arabic1256 = crlf("From: \"HR\" <hr@hotel.example>\nTo: sultan@hotel.example\n" &
  "Subject: =?windows-1256?B?" & base64UrlEncode("\xE3\xD1\xCD\xC8\xC7", pad = true) & "?=\n" &
  "Date: Tue, 4 Nov 2025 10:15:00 +0400\nMIME-Version: 1.0\n" &
  "Content-Type: text/plain; charset=windows-1256\nContent-Transfer-Encoding: quoted-printable\n\n" &
  "=E3=D1=CD=C8=C7 Sultan\n")

proc note(k: int): string =
  crlf("From: sultan@hotel.example\nTo: sultan@hotel.example\nSubject: Retro note " & $k &
       "\nDate: Wed, 5 Nov 2025 0" & $(k mod 10) & ":00:00 +0000\n\nNote number " & $k & ".\n")

let quoting = crlf"""From: ali@hotel.example
To: sultan@hotel.example
Subject: Lines that start with From
Date: Thu, 6 Nov 2025 12:00:00 +0400

From the desk of Ali.
>From the old days.
>>From further back.
From
Fromage.
"""

proc mailWith(subject, extra, body: string; date = "Fri, 7 Nov 2025 08:00:00 +0400"): string =
  "From: archive@hotel.example\nTo: sultan@hotel.example\nSubject: " & subject & "\nDate: " & date &
    "\n" & extra & "\n" & body

# ---- the samples -------------------------------------------------------------------------------

let
  tWelcome = utcTime(2025, 11, 3, 5, 1, 0)
  tReport = utcTime(2025, 11, 3, 6, 31, 0)
  tArabic = utcTime(2025, 11, 4, 6, 16, 0)
  folderAr = "\xE3\xD4\xC7\xD1\xED\xDA"                  # مشاريع in windows-1256
  inboxAr = "\xDA\xE1\xC8\xC9 \xC7\xE1\xE6\xC7\xD1\xCF"   # علبة الوارد

proc writeOe6(dir: string) =
  createDir(dir)
  writeFile(dir / "Folders.dbx", makeFoldersDbx(@[
    OeFolder(id: 0, parent: -1, name: "Outlook Express"),
    OeFolder(id: 1, parent: 0, name: "Local Folders", account: "LocalStore"),
    OeFolder(id: 4, parent: 1, name: inboxAr, file: "Inbox.dbx", special: 1),
    OeFolder(id: 5, parent: 1, name: "Outbox", special: 2),
    OeFolder(id: 6, parent: 1, name: "Sent Items", file: "Sent Items.dbx", special: 3),
    OeFolder(id: 7, parent: 1, name: "Deleted Items", special: 4),
    OeFolder(id: 10, parent: 1, name: "Projects", file: "Projects.dbx"),
    OeFolder(id: 11, parent: 10, name: "Retro", file: "Retro.dbx"),
    OeFolder(id: 12, parent: 1, name: folderAr, file: folderAr & ".dbx"),
    OeFolder(id: 20, parent: 0, name: "Hotmail", account: "00000001"),
    OeFolder(id: 21, parent: 20, name: "Inbox", file: "Inbox (1).dbx", special: 1)]))
  writeFile(dir / "Inbox.dbx", makeDbx(inboxAr, @[
    OeMsg(raw: welcome, flags: 0x01000081, received: tWelcome),
    OeMsg(raw: report, flags: 0x4021, received: tReport),
    OeMsg(raw: arabic1256, flags: 0x80081, received: tArabic)]))
  writeFile(dir / "Sent Items.dbx", makeDbx("Sent Items", @[
    OeMsg(raw: quoting, flags: 0x81, received: utcTime(2025, 11, 6, 8, 0, 0))]))
  writeFile(dir / "Projects.dbx", makeDbx("Projects", @[OeMsg(raw: note(0), flags: 0x81)],
                                          indirectAddress = true))
  var notes: seq[OeMsg]
  for k in 1 .. 7: notes.add OeMsg(raw: note(k), flags: 0x81, received: utcTime(2025, 11, 5, k, 0, 0))
  writeFile(dir / "Retro.dbx", makeDbx("Retro", notes, cap = 2))
  writeFile(dir / "مشاريع.dbx", makeDbx(folderAr, @[OeMsg(raw: note(8), flags: 0x20)]))
  writeFile(dir / "Inbox (1).dbx", makeDbx("Inbox", @[OeMsg(raw: note(9), flags: 0x80)]))
  writeFile(dir / "Old Stuff.dbx", makeDbx("Old Stuff", @[OeMsg(raw: note(10), flags: 0)]))
  var offline = makeDbx("Offline", @[OeMsg(raw: note(11))])
  for i, c in "\xCF\xAD\x12\xFE\x30\x9D\xFE\x26\x8F\x1A\xD2\x11\xAA\xBF\x00\x60": offline[i] = c
  writeFile(dir / "Offline.dbx", offline)

proc writeOe4(dir: string) =
  createDir(dir)
  let (mbx, recs) = makeMbx(@[welcome, note(20), report])
  writeFile(dir / "Inbox.mbx", mbx)
  writeFile(dir / "Inbox.idx", makeIdx(recs, @[false, true, false]))
  writeFile(dir / "Sent Items.mbx", makeMbx(@[quoting, arabic1256]).mbx)

proc writeMboxes(dir: string) =
  createDir(dir / "Archive.sbd")
  createDir(dir / "Notes.mbox")
  # Thunderbird: CRLF, mboxo quoting, X-Mozilla-Status (9: deleted)
  writeFile(dir / "Archive", crlf(
    "From - Mon Nov 03 10:00:00 2025\n" &
    mailWith("Archived one", "X-Mozilla-Status: 0001\n", "One.\n>From the start.\n") & "\n" &
    "From - Mon Nov 03 10:05:00 2025\n" &
    mailWith("Archived two", "X-Mozilla-Status: 0005\n", "Two.\n") & "\n" &
    "From - Mon Nov 03 10:06:00 2025\n" &
    mailWith("Archived deleted", "X-Mozilla-Status: 0009\n", "Gone.\n") & "\n"))
  writeFile(dir / "Archive.sbd" / "2003", "From ali@hotel.example Sat Mar  1 09:30:00 2003\n" &
    mailWith("Old times", "Status: RO\nX-Status: AF\n", "From 2003.\n", "") & "\n")
  writeFile(dir / "takeout.mbox",
    "From 1777777777777777777@xxx Wed Feb 05 20:39:02 +0000 2020\n" &
    mailWith("Takeout unread", "X-Gmail-Labels: Inbox,Unread\n", "Hi.\n") & "\n" &
    "From 1777777777777777778@xxx Wed Feb 05 20:40:02 +0000 2020\n" &
    mailWith("Takeout starred", "X-Gmail-Labels: \"Starred\",Opened\n", "Hi again.\n") & "\n")
  writeFile(dir / "Notes.mbox" / "mbox", "From MAILER-DAEMON Thu Jan  1 00:00:00 1970\n" &
    mailWith("Apple note", "", "From Apple Mail.\n") & "\n")
  writeFile(dir / "Notes.mbox" / "table_of_contents", "\x00\x01\x02\x03binary")

proc writeEmls(dir: string) =
  createDir(dir / "Saved")
  writeFile(dir / "letter.eml", report)
  writeFile(dir / "Saved" / "old.eml", "\xEF\xBB\xBFFrom hr@hotel.example Mon Nov  3 08:00:00 2025\n" &
    mailWith("Saved with a byte order mark", "", "Kept.\n"))
  writeFile(dir / "Saved" / "photo.jpg", "\xFF\xD8\xFF\xE0 not mail")
  writeFile(dir / "Saved" / "notes.txt", "Shopping: milk\nDate: today\n\nNot a message.\n")

proc writeMaildir(dir: string) =
  for d in ["cur", "new", "tmp", ".Work.Retro" / "cur", ".Work.Retro" / "new"]: createDir(dir / d)
  writeFile(dir / "cur" / "1700000000.1.host:2,FS", mailWith("Maildir seen", "", "Seen.\n"))
  writeFile(dir / "new" / "1700000001.2.host", mailWith("Maildir new", "", "New.\n"))
  writeFile(dir / "tmp" / "1700000002.3.host", mailWith("Maildir partial", "", "Half"))
  writeFile(dir / ".Work.Retro" / "cur" / "1700000003.4.host:2,RS", mailWith("Maildir work", "", "Work.\n"))

proc writeAll(dir: string) =
  writeOe6(dir / "oe6")
  writeOe4(dir / "oe4")
  writeMboxes(dir / "mbox")
  writeEmls(dir / "eml")

let samples = tmp / "samples"
writeAll(samples)
writeMaildir(tmp / "Maildir")
when defined(writeSamples):
  removeDir(data)
  writeAll(data)

# ---- checks ------------------------------------------------------------------------------------

type Seen = tuple[folder, subject, text: string, read, flagged, replied: bool, date: float,
                  files: seq[string]]

proc collect(path: string; codepage = ""): seq[Seen] =
  for m in importMail(path, codepage = codepage):
    let p = parseMime(m.raw)
    var files: seq[string]
    for a in p.attachments: files.add a.filename
    result.add (m.folder, p.decodedHeader("Subject"), p.bodies.text.strip, m.read, m.flagged,
                m.replied, m.date, files)

proc find(s: seq[Seen]; subject: string): Seen =
  for x in s:
    if x.subject == subject: return x
  doAssert false, "missing: " & subject

proc folders(s: seq[Seen]): seq[string] =
  for x in s:
    if x.folder notin result: result.add x.folder

proc checkOe6(dir: string; fromStore = true) =
  let got = collect(dir)
  var expect = @["Inbox", "Sent Items", "Projects", "Projects/Retro", "مشاريع", "Hotmail/Inbox"]
  if not fromStore: expect.add "Old Stuff"
  doAssert got.folders == expect, $got.folders
  doAssert got.len == 3 + 1 + 1 + 7 + 1 + 1 + (if fromStore: 0 else: 1), $got.len
  let w = got.find("Welcome to Retro Mail")
  doAssert w.folder == "Inbox" and w.read and not w.flagged and not w.replied
  doAssert w.date == tWelcome and w.text == "Hello! Your old mail is home again."
  let r = got.find("التقرير الشهري – نوفمبر")
  doAssert not r.read and r.flagged and not r.replied and r.date == tReport
  doAssert r.text == reportText.strip and r.files == @["تقرير.pdf"]
  let a = got.find("مرحبا")
  doAssert a.read and a.replied and not a.flagged and a.text == "مرحبا Sultan"
  let q = got.find("Lines that start with From")
  doAssert q.folder == "Sent Items" and q.text.startsWith("From the desk of Ali.\n>From the old days.")
  var notes: seq[string]
  for x in got:
    if x.folder == "Projects/Retro": notes.add x.subject
  doAssert notes == @["Retro note 1", "Retro note 2", "Retro note 3", "Retro note 4",
                      "Retro note 5", "Retro note 6", "Retro note 7"], $notes
  doAssert got.find("Retro note 4").date == utcTime(2025, 11, 5, 4, 0, 0)
  let p0 = got.find("Retro note 0")                      # (no received time: the Date header)
  doAssert p0.folder == "Projects" and p0.date == utcTime(2025, 11, 5, 0, 0, 0)
  let ar = got.find("Retro note 8")
  doAssert ar.folder == "مشاريع" and ar.flagged and not ar.read
  doAssert got.find("Retro note 9").folder == "Hotmail/Inbox"
  for x in got: doAssert x.subject != "Retro note 11"    # (Offline.dbx: not a folder of mail)

block oe6Store:
  let dir = samples / "oe6"
  checkOe6(dir, fromStore = false)
  checkOe6(dir / "Folders.dbx")
  doAssert collect(dir, codepage = "windows-1256").folders == collect(dir).folders
  # one folder of the store: named as the store names it
  let retro = collect(dir / "Retro.dbx")
  doAssert retro.len == 7 and retro.folders == @["Projects/Retro"]
  doAssert collect(dir / "Inbox.dbx").folders == @["Inbox"]
  # without its Folders.dbx: by its file's name
  let lone = tmp / "lone"
  createDir(lone)
  copyFile(dir / "Retro.dbx", lone / "Retro.dbx")
  doAssert collect(lone / "Retro.dbx").folders == @["Retro"]
  doAssert collect(lone).folders == @["Retro"]

block oe4:
  let dir = samples / "oe4"
  let got = collect(dir)
  doAssert got.folders == @["Inbox", "Sent Items"], $got.folders
  var subjects: seq[string]
  for x in got: subjects.add x.subject
  doAssert subjects == @["Welcome to Retro Mail", "التقرير الشهري – نوفمبر",
                         "Lines that start with From", "مرحبا"], $subjects
  let r = got.find("التقرير الشهري – نوفمبر")
  doAssert r.text == reportText.strip and r.files == @["تقرير.pdf"]
  doAssert r.date == utcTime(2025, 11, 3, 6, 30, 0) and not r.read
  # without the .idx: every record, the deleted one too
  let bare = tmp / "bare"
  createDir(bare)
  copyFile(dir / "Inbox.mbx", bare / "Inbox.mbx")
  let all = collect(bare / "Inbox.mbx")
  doAssert all.len == 3 and all[1].subject == "Retro note 20" and all[0].folder == "Inbox"

block mboxFiles:
  let got = collect(samples / "mbox")
  doAssert got.folders == @["Archive", "takeout", "Archive/2003", "Notes"], $got.folders
  doAssert got.len == 6
  let one = got.find("Archived one")
  doAssert one.read and not one.flagged and one.text == "One.\nFrom the start."
  let two = got.find("Archived two")
  doAssert two.read and two.flagged
  for x in got: doAssert x.subject != "Archived deleted"
  let old = got.find("Old times")
  doAssert old.read and old.flagged and old.replied and old.text == "From 2003."
  doAssert old.date == utcTime(2003, 3, 1, 9, 30, 0)     # (no Date header: the "From " line's)
  doAssert not got.find("Takeout unread").read
  let st = got.find("Takeout starred")
  doAssert st.read and st.flagged
  doAssert got.find("Apple note").folder == "Notes"
  # one file: its name
  doAssert collect(samples / "mbox" / "Archive").folders == @["Archive"]
  doAssert collect(samples / "mbox" / "Notes.mbox" / "mbox").folders == @["Notes"]
  doAssert collect(samples / "mbox" / "Notes.mbox").folders == @["Notes"]

block emls:
  let got = collect(samples / "eml")
  doAssert got.folders == @["eml", "Saved"], $got.folders
  doAssert got.len == 2
  let s = got.find("Saved with a byte order mark")
  doAssert s.text == "Kept." and s.date == utcTime(2025, 11, 7, 4, 0, 0)
  let m = readEml(samples / "eml" / "letter.eml")
  doAssert m.raw == report and m.folder == "" and m.date == utcTime(2025, 11, 3, 6, 30, 0)
  doAssert readEml(samples / "eml" / "missing.eml").raw == ""
  doAssert collect(samples / "eml" / "letter.eml").folders == @[""]
  # Maildir: cur and new are the folder, the top one the Inbox, tmp left out
  let md = collect(tmp / "Maildir")
  doAssert md.folders == @["Work/Retro", "Inbox"], $md.folders
  doAssert md.len == 3
  let seen = md.find("Maildir seen")
  doAssert seen.read and seen.flagged and not seen.replied
  doAssert not md.find("Maildir new").read
  let work = md.find("Maildir work")
  doAssert work.read and work.replied

block everything:
  # a folder of all of it: a store keeps its own names, the rest by their paths
  let got = collect(samples)
  doAssert got.folders == @["eml", "eml/Saved", "mbox/Archive", "mbox/takeout", "mbox/Archive/2003",
    "mbox/Notes", "oe4/Inbox", "oe4/Sent Items", "Inbox", "Sent Items", "Projects",
    "Projects/Retro", "مشاريع", "Hotmail/Inbox", "oe6/Old Stuff"], $got.folders
  doAssert got.len == 2 + 6 + 4 + 15
  for x in got:
    doAssert x.subject.len > 0 and x.text.len > 0, x.subject

block committedSamples:
  # (the copy in tests/data, made once: it reads the same)
  if dirExists(data):
    checkOe6(data / "oe6", fromStore = false)
    doAssert collect(data).len == collect(samples).len
    doAssert collect(data / "oe4").len == 4

block kinds:
  doAssert importKind(samples / "oe6" / "Inbox.dbx") == "dbx"
  doAssert importKind(samples / "oe6" / "Folders.dbx") == "dbx"
  doAssert importKind(samples / "oe6" / "Offline.dbx") == ""
  doAssert importKind(samples / "oe4" / "Inbox.mbx") == "mbx"
  doAssert importKind(samples / "oe4" / "Inbox.idx") == ""
  doAssert importKind(samples / "mbox" / "Archive") == "mbox"
  doAssert importKind(samples / "mbox" / "takeout.mbox") == "mbox"
  doAssert importKind(samples / "eml" / "letter.eml") == "eml"
  doAssert importKind(samples / "eml" / "Saved" / "old.eml") == "eml"   # (a "From " line, but .eml)
  doAssert importKind(samples / "eml" / "Saved" / "notes.txt") == ""
  doAssert importKind(samples / "eml" / "Saved" / "photo.jpg") == ""
  doAssert importKind(samples / "eml") == "folder"
  doAssert importKind(samples) == "folder"
  doAssert importKind(samples / "nothing-here") == ""
  # by content, not by name
  let renamed = tmp / "renamed"
  createDir(renamed / "empty")
  copyFile(samples / "oe6" / "Retro.dbx", renamed / "retro.bin")
  copyFile(samples / "oe4" / "Inbox.mbx", renamed / "inbox")
  copyFile(samples / "mbox" / "Archive", renamed / "archive.txt")
  copyFile(samples / "eml" / "letter.eml", renamed / "letter.dat")
  writeFile(renamed / "empty.eml", "")
  writeFile(renamed / "empty" / "x.jpg", "\xFF\xD8")
  doAssert importKind(renamed / "retro.bin") == "dbx"
  doAssert importKind(renamed / "inbox") == "mbx"
  doAssert importKind(renamed / "archive.txt") == "mbox"
  doAssert importKind(renamed / "letter.dat") == "eml"
  doAssert importKind(renamed / "empty.eml") == ""
  doAssert importKind(renamed / "empty") == ""
  doAssert collect(renamed / "retro.bin").len == 7
  doAssert collect(renamed / "inbox").len == 3
  doAssert oeStoreFolders().len == 0 or defined(windows)

block progress:
  var calls: seq[(int, int)]
  var n = 0
  for m in importMail(samples, proc (done, total: int): bool = (calls.add (done, total); true)):
    inc n
  doAssert n == 27 and calls.len >= n
  for k in 1 ..< calls.len:
    doAssert calls[k][0] >= calls[k - 1][0] and calls[k][1] == calls[0][1]
  doAssert calls[^1][0] == calls[^1][1] and calls[0][1] > 0
  # false stops it
  var got = 0
  var asked = 0
  for m in importMail(samples / "oe6", proc (done, total: int): bool = (inc asked; asked < 3)):
    inc got
  doAssert got == 3, $got

# ---- taking mail out ---------------------------------------------------------------------------

block mboxRoundTrip:
  let raws = @[welcome, report, quoting, "Subject: no line end\n\nFrom here, no newline",
               mailWith("LF lines", "", "From a\n>From b\n>>From c\nFrom\n"),
               crlf(mailWith("Arabic", "", "مرحبا\nFrom سلطان\n"))]
  let path = tmp / "out.mbox"
  writeMbox(path, raws)
  let text = readFile(path)
  doAssert "\r" notin text
  doAssert "\n>From the desk of Ali.\n>>From the old days.\n>>>From further back.\nFrom\nFromage.\n" in text
  doAssert "\n>From a\n>>From b\n>>>From c\n" in text and "\n>From سلطان\n" in text
  doAssert text.startsWith("From hello@retro.example Mon Nov  3 05:00:00 2025\n")
  var back: seq[string]
  for r in readMbox(path): back.add r
  doAssert back.len == raws.len
  for k, r in raws:
    var want = r.replace("\r\n", "\n")
    if not want.endsWith("\n"): want.add "\n"
    doAssert back[k] == want, $k & ": " & back[k]
  # what comes back reads as it went
  for k, m in collect(path):
    let p = parseMime(raws[k])
    doAssert m.subject == p.decodedHeader("Subject") and m.text == p.bodies.text.strip
    doAssert m.folder == "out"
  doAssert collect(path).find("التقرير الشهري – نوفمبر").files == @["تقرير.pdf"]
  # appending
  var f = open(path, fmAppend)
  addMboxMessage(f, note(30))
  f.close()
  var n = 0
  for r in readMbox(path): inc n
  doAssert n == raws.len + 1
  # mboxo with CRLF, as Thunderbird keeps them on Windows
  var arch: seq[string]
  for r in readMbox(samples / "mbox" / "Archive"): arch.add r
  doAssert arch.len == 3 and arch[0].endsWith("One.\r\nFrom the start.\r\n")
  for r in readMbox(tmp / "no-such.mbox"): doAssert false

block emlRoundTrip:
  let path = tmp / "out" / "Letters" / "report.eml"
  writeEml(path, report)
  doAssert readFile(path) == report
  let m = readEml(path)
  doAssert m.raw == report and parseMime(m.raw).decodedHeader("Subject") == "التقرير الشهري – نوفمبر"
  doAssert emlFileName(report) == "2025-11-03 التقرير الشهري – نوفمبر.eml"
  doAssert emlFileName("Subject: a/b: c?\n\n") == "a_b_ c_.eml"
  doAssert emlFileName("\n") == "(no subject).eml"
  let long = emlFileName("Subject: " & "ب".repeat(80) & "\n\n")
  doAssert long.len <= 104 and long.endsWith("ب.eml")

# ---- damaged files -----------------------------------------------------------------------------

proc count(path: string): int =
  for m in importMail(path):
    discard parseMime(m.raw)
    inc result

template timed(what: string; body: untyped) =
  let t0 = getMonoTime()
  body
  let ms = (getMonoTime() - t0).inMilliseconds
  doAssert ms < 5000, what & " took " & $ms & " ms"

let inbox = readFile(samples / "oe6" / "Inbox.dbx")
let retroDbx = readFile(samples / "oe6" / "Retro.dbx")
let dmg = tmp / "damaged"
createDir(dmg)

proc allBlocks(f: string): seq[int] =
  ## Where the message blocks of a file made here are.
  var i = DbxHead
  while i + 16 <= f.len:
    if rd32(f, i) == i and rd32(f, i + 4) == 0x200: result.add i
    inc i, 4

block truncated:
  var cut = 0
  while cut <= inbox.len:
    writeFile(dmg / "cut.dbx", inbox[0 ..< cut])
    timed("cut " & $cut): (discard count(dmg / "cut.dbx"))
    cut += (if cut < DbxHead + 64: 61 else: 37)
  writeFile(dmg / "cut.dbx", inbox[0 ..< inbox.len - 300])
  doAssert count(dmg / "cut.dbx") <= 3

block chains:
  # the report's chain: its last block points back to its first
  var f = inbox
  let blocks = allBlocks(f)
  var heads: seq[int]
  var pointed: seq[int64]
  for b in blocks: pointed.add rd32(f, b + 12)
  for b in blocks:
    if int64(b) notin pointed: heads.add b
  doAssert heads.len == 3
  var b = heads[1]
  var chain: seq[int]
  while b != 0:
    chain.add b
    b = int(rd32(f, b + 12))
  doAssert chain.len >= 3                                 # (the report is more than 512 bytes)
  f.put32(chain[^1] + 12, chain[0])
  writeFile(dmg / "loop.dbx", f)
  var got: seq[string]
  timed("loop"):
    for m in importMail(dmg / "loop.dbx"): got.add m.raw
  doAssert got.len == 3 and got[1] == report               # (each block once)
  f.put32(chain[0] + 12, chain[0])                          # a block that points at itself
  writeFile(dmg / "loop.dbx", f)
  timed("self"): doAssert count(dmg / "loop.dbx") == 3
  # a block that is not one: the message as far as it goes
  f = inbox
  f.put32(chain[1], 12345)
  writeFile(dmg / "broken.dbx", f)
  got.setLen(0)
  for m in importMail(dmg / "broken.dbx"): got.add m.raw
  doAssert got.len == 3 and got[1] == report[0 ..< 0x200]
  # a length past the block
  f = inbox
  f.put16(chain[1] + 8, 0xFFFF)
  writeFile(dmg / "long.dbx", f)
  got.setLen(0)
  for m in importMail(dmg / "long.dbx"): got.add m.raw
  doAssert got.len == 3 and got[1] == report[0 ..< 0x200]

block trees:
  # a node whose children lead back to it
  var f = retroDbx
  let root = int(rd32(f, 0xE4))
  f.put32(root + 8, root)
  f.put32(root + 28, int64(root))
  writeFile(dmg / "tree.dbx", f)
  timed("tree loop"): doAssert count(dmg / "tree.dbx") == 7   # (the lost ones found by their blocks)
  # the root pointer gone: every message found by its blocks, without flags
  f = inbox
  f.put32(0xE4, 0xFFFFFFF0'i64)
  writeFile(dmg / "noroot.dbx", f)
  var subjects: seq[string]
  for m in importMail(dmg / "noroot.dbx"):
    doAssert not m.read and m.date > 0
    subjects.add parseMime(m.raw).decodedHeader("Subject")
  doAssert subjects == @["Welcome to Retro Mail", "التقرير الشهري – نوفمبر", "مرحبا"], $subjects
  # an info object too long to be one, and one that is not where it says
  f = retroDbx
  var infos: seq[int]
  var i = DbxHead
  while i + 12 <= f.len:
    if rd32(f, i) == i and rd32(f, i + 4) in 8'i64 .. 200'i64 and ord(f[i + 10]) in 3 .. 8: infos.add i
    inc i, 4
  doAssert infos.len == 7
  f.put32(infos[0] + 4, 0x7FFFFFFF)
  f.put32(infos[1], 0)
  writeFile(dmg / "info.dbx", f)
  doAssert count(dmg / "info.dbx") == 7
  # entries that say a node holds 255 of them
  f = retroDbx
  f[root + 17] = '\xFF'
  writeFile(dmg / "entries.dbx", f)
  timed("entries"): doAssert count(dmg / "entries.dbx") <= 14

block foldersDamaged:
  let store = tmp / "store"
  copyDir(samples / "oe6", store)
  let good = readFile(store / "Folders.dbx")
  var f = good
  f.put32(0xE4, 0)                                         # no folder list: each file by its name
  writeFile(store / "Folders.dbx", f)
  doAssert collect(store).len == 15
  f = good
  # a parent loop: Projects inside Retro inside Projects
  var at = DbxHead + 0x108
  var objs: seq[int]
  while at + 12 <= f.len:
    if rd32(f, at) == at and ord(f[at + 10]) in 3 .. 10: objs.add at
    inc at, 4
  for o in objs:
    let n = ord(f[o + 10])
    for e in 0 ..< n:
      let v = rd32(f, o + 12 + 4 * e)
      if (v and 0xFF) == 0x81 and (v shr 8) == 1 and "Projects" in f[o ..< o + 80]:
        f.put32(o + 12 + 4 * e, (11'i64 shl 8) or 0x81)
  writeFile(store / "Folders.dbx", f)
  timed("parent loop"): doAssert collect(store).len == 15

block mbxDamaged:
  let (good, recs) = makeMbx(@[welcome, note(20), report])
  var f = good
  f.put32(recs[0][0] + 12, 0x7FFFFFF0)                      # a text longer than the file
  writeFile(dmg / "a.mbx", f)
  var got: seq[string]
  for m in importMail(dmg / "a.mbx"): got.add parseMime(m.raw).decodedHeader("Subject")
  doAssert got == @["Welcome to Retro Mail", "Retro note 20", "التقرير الشهري – نوفمبر"], $got
  f = good
  f.put32(recs[1][0] + 8, 0)                                # a record of no size
  f.put32(recs[1][0] + 12, 0)
  writeFile(dmg / "b.mbx", f)
  timed("zero record"): doAssert count(dmg / "b.mbx") == 3     # (its text runs to the next record)
  f = good
  f.put32(recs[1][0], 0x12345678)                           # a marker gone: found again after it
  writeFile(dmg / "c.mbx", f)
  doAssert count(dmg / "c.mbx") == 2
  # an .idx that does not agree: every record
  writeFile(dmg / "d.mbx", good)
  var idx = makeIdx(recs, @[false, true, false])
  idx.put32(80 + 220 + 12, 999)
  writeFile(dmg / "d.idx", idx)
  doAssert count(dmg / "d.mbx") == 3
  writeFile(dmg / "d.idx", makeIdx(recs, @[false, true, false]))
  doAssert count(dmg / "d.mbx") == 2
  writeFile(dmg / "e.mbx", good[0 ..< good.len - 100])
  doAssert count(dmg / "e.mbx") == 3

block mboxDamaged:
  writeFile(dmg / "bin.mbox", "From x Mon Nov  3 10:00:00 2025\n\x00\x01\x02\xFF\n\n" &
    "x".repeat(3_000_000) & "\nFrom y Mon Nov  3 10:00:00 2025\nSubject: after\n\nok\n")
  var n = 0
  for r in readMbox(dmg / "bin.mbox"): inc n
  doAssert n == 2
  writeFile(dmg / "e.eml", "\x00\x00garbage")
  doAssert readEml(dmg / "e.eml").raw == "\x00\x00garbage"

# ---- random damage -----------------------------------------------------------------------------

proc mutate(s: string; r: var Rand): string =
  result = s
  for _ in 0 .. r.rand(7):
    if result.len < 8: break
    case r.rand(6)
    of 0: result[r.rand(result.high)] = char(r.rand(255))
    of 1, 2:
      let at = r.rand(result.len div 4 - 1) * 4
      let v = [0'i64, 0xFFFFFFFF'i64, 0x7FFFFFFF, 0x200, 0x210, 0x1FC, int64(at), int64(at + 16),
               int64(r.rand(result.len)), int64(r.rand(result.len) and not 3), DbxHead,
               0x7F007F00, 1, 0x33][r.rand(13)]
      result.put32(at, v)
    of 3: result.setLen(r.rand(result.high))
    of 4:
      let a = r.rand(result.high)
      let b = r.rand(result.high)
      let n = r.rand(min(600, result.len - max(a, b)))
      for k in 0 ..< n: result[b + k] = result[a + k]
    of 5:
      let a = r.rand(result.high)
      for k in a ..< min(result.len, a + r.rand(64)): result[k] = '\0'
    else:
      let a = r.rand(result.high)
      result.insert(result[a ..< min(result.len, a + r.rand(300))], r.rand(result.high))

block fuzz:
  var r = initRand(20251103)
  let fz = tmp / "fuzz"
  copyDir(samples / "oe6", fz / "store")
  let folders = readFile(fz / "store" / "Folders.dbx")
  let (mbx, recs) = makeMbx(@[welcome, note(20), report])
  let idx = makeIdx(recs, @[false, true, false])
  let mbox = readFile(samples / "mbox" / "Archive") & readFile(samples / "mbox" / "takeout.mbox")
  let cases = [("Inbox.dbx", inbox, 400), ("Retro.dbx", retroDbx, 300), ("x.mbx", mbx, 300),
               ("x.mbox", mbox, 200), ("x.eml", report, 100)]
  let t0 = getMonoTime()
  for (name, seed, runs) in cases:
    for k in 0 ..< runs:
      let bad = mutate(seed, r)
      writeFile(fz / name, bad)
      timed(name & " #" & $k):
        discard count(fz / name)
        discard importKind(fz / name)
  writeFile(fz / "x.mbx", mbx)
  for k in 0 ..< 200:
    writeFile(fz / "x.idx", mutate(idx, r))
    timed("idx #" & $k): (discard count(fz / "x.mbx"))
  for k in 0 ..< 200:
    writeFile(fz / "store" / "Folders.dbx", mutate(folders, r))
    timed("Folders.dbx #" & $k): (discard count(fz / "store"))
  echo "fuzz: ", (getMonoTime() - t0).inMilliseconds, " ms"

removeDir(tmp)
echo "mailimport: ok"
