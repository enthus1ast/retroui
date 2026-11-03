## Retro Mail's Local Folders, as Outlook Express had them: mail kept on
## this computer only -- what is imported from Outlook Express (.dbx,
## .mbx), mbox files and saved messages (.eml) -- and mail written out to
## an mbox file. The import runs on a thread of its own and says how far
## it has come.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[json, strutils, hashes, times]
import retro/[db, mime, mailimport]
import store

const localClient* = "local"     ## (the client id that marks the Local Folders account)

proc isLocal*(acc: Account): bool = acc.clientId == localClient
  ## The Local Folders account: nothing of it is on a server.

proc localAccount*(db: Db): int =
  ## The Local Folders account (made the first time).
  let v = db.value("SELECT id FROM accounts WHERE client_id = ?", localClient)
  if not v.isNull: return int v.num
  db.addAccount(akGraph, "Local Folders", "", localClient, "", 0)

proc localFolder*(db: Db; account: int; path: string): int =
  ## The local folder `path` ("Projects/Retro": inside Projects), made with
  ## its parents when missing.
  var parent = ""
  var id = 0
  var sofar = ""
  for part in path.split('/'):
    let name = part.strip
    if name.len == 0: continue
    sofar = if sofar.len > 0: sofar & "/" & name else: name
    let role = if sofar == "Deleted Items": "trash" else: ""
    id = db.upsertFolder(account, "local:" & sofar, name, role, parent)
    parent = "local:" & sofar
  if id == 0: id = db.upsertFolder(account, "local:Imported", "Imported", "", "")
  id

proc storeRaw*(db: Db; account, folder: int; raw: string; read, flagged: bool; date: float): int =
  ## One message (its RFC 5322 source) kept in a local folder; its id.
  let root = parseMime(raw)
  var m = Msg(account: account, folder: folder)
  m.msgId = root.header("Message-ID").strip
  m.remoteId = "local:" & (if m.msgId.len > 0: m.msgId else: $hash(raw))
  m.subject = root.decodedHeader("Subject")
  let froms = parseAddresses(root.header("From"))
  if froms.len > 0:
    m.fromName = froms[0].name
    m.fromEmail = froms[0].email
  m.toList = root.decodedHeader("To")
  m.ccList = root.decodedHeader("Cc")
  m.inReplyTo = root.header("In-Reply-To").strip
  m.refs = root.header("References").strip
  # a thread: the first message it answers (as the References say), else itself
  let first = m.refs.splitWhitespace()
  m.thread = if first.len > 0: first[0] elif m.inReplyTo.len > 0: m.inReplyTo
             elif m.msgId.len > 0: m.msgId else: m.remoteId
  m.date = if date > 0: date else: parseMailDate(root.header("Date"))
  m.unread = not read
  m.flagged = flagged
  m.focused = true
  m.size = raw.len
  let (html, text) = bodies(root)
  let atts = attachments(root)
  for a in atts:
    if not a.inline: m.hasAtt = true
  let plain = if text.len > 0: text else: html
  var snip = ""
  var inTag = false
  for c in plain:
    if c == '<': inTag = true
    elif c == '>': inTag = false
    elif not inTag:
      snip.add(if c in {'\r', '\n', '\t'}: ' ' else: c)
      if snip.len > 400: break
  m.snippet = snip.splitWhitespace().join(" ")
  result = db.upsertMessage(m)
  db.setBody(result, html, text)
  for i, a in atts:
    discard db.addAttachment(result, "a" & $i, a.filename, a.contentType, a.data.len, a.contentId,
                             a.inline, a.data, true)

type
  ImportLink* = object
    path*, dbPath*: string
    stop*: bool                       ## set by the window: stop now
    progress*: Channel[string]        ## {"done", "total", "count"}, then {"end": count} or {"error"}

proc importMain*(link: ptr ImportLink) {.thread.} =
  ## Imports everything at `link.path` into Local Folders.
  {.gcsafe.}:
    var count = 0
    try:
      let db = openStore(link.dbPath)
      let acc = db.localAccount()
      var lastSaid = 0.0
      let report = proc (done, total: int): bool =
        if epochTime() - lastSaid > 0.25:
          lastSaid = epochTime()
          link.progress.send($(%*{"done": done, "total": total, "count": count}))
        not link.stop
      var batch = 0
      db.exec("BEGIN")
      for im in importMail(link.path, report):
        if link.stop: break
        let folder = db.localFolder(acc, if im.folder.len > 0: im.folder else: "Imported")
        try:
          discard db.storeRaw(acc, folder, im.raw, im.read, im.flagged, im.date)
          inc count
        except CatchableError: discard      # (one message it cannot read: the others go on)
        inc batch
        if batch >= 200:
          db.exec("COMMIT")
          db.exec("BEGIN")
          batch = 0
      db.exec("COMMIT")
      db.recount(acc)
      db.close()
      link.progress.send($(%*{"end": count}))
    except CatchableError as e:
      link.progress.send($(%*{"error": e.msg, "end": count}))

proc rawOf*(db: Db; m: Msg; me: MailAddress): string =
  ## A message kept here written out again (for an mbox file): its headers,
  ## its text and HTML, its attachments.
  let full = db.message(m.id)
  var o = OutMail(subject: full.subject, text: full.text, html: full.html, date: full.date,
                  messageId: full.msgId, inReplyTo: full.inReplyTo, references: full.refs)
  let froms = parseAddresses(full.fromName & " <" & full.fromEmail & ">")
  o.fromAddr = if froms.len > 0: froms[0] else: me
  o.to = parseAddresses(full.toList)
  o.cc = parseAddresses(full.ccList)
  for a in db.attachments(full.id):
    let data = db.attachmentData(a.id)
    if data.len > 0:
      o.attachments.add MailAttachment(filename: a.name, contentType: a.mime, contentId: a.cid,
                                       data: data, inline: a.inline)
  buildMail(o)
