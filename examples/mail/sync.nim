## Retro Mail's sync thread: it keeps the store in step with the servers
## (new mail, changes made elsewhere), sends what waits in the queue
## (changes made here, mail to send), fetches bodies and attachments when
## the window asks, and keeps the sign-in tokens fresh. The window talks to
## it through two channels and never waits for the network.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[json, strutils, times, tables, os, hashes, sets]
import retro/[db, http, oauth, secrets, mime]
import api, store, graph, gmail

const secretApp* = "RetroMail"

type
  SyncCmdKind* = enum
    scWake        ## changes were queued: send them now
    scSyncNow     ## Send and Receive (F5)
    scBody        ## fetch message `id`'s body
    scAttachment  ## fetch attachment `id`'s bytes
    scSearch      ## search the servers for `text`
    scAccounts    ## accounts were added or removed
    scSettings    ## `count`: minutes between checks
    scQuit
  SyncCmd* = object
    kind*: SyncCmdKind
    id*, count*: int
    text*: string
  SyncEventKind* = enum
    seChanged     ## the store changed: read it again
    seStatus      ## `text`: what it is doing ("" when done)
    seError       ## `text` went wrong (for `id`'s account)
    seSignIn      ## account `id` must sign in again
    seBody        ## message `id`'s body is here (or failed)
    seAttachment  ## attachment `id`'s bytes are here (`text`: an error)
    seNewMail     ## `count` new messages; `text` the newest's sender and subject
    seSearch      ## the server search is done: `ids`
    seSent        ## a message went (`text` its subject)
  SyncEvent* = object
    kind*: SyncEventKind
    id*, count*: int
    text*: string
    ids*: seq[int]
  SyncLink* = object
    cmds*: Channel[SyncCmd]
    events*: Channel[SyncEvent]
    dbPath*: string

proc tokenKey*(account: int): string = "acct-" & $account
proc secretKey*(account: int): string = "acct-" & $account & "-secret"

proc providerFor*(acc: Account; clientSecret = ""): OAuthProvider {.gcsafe.} =
  ## The sign-in service of an account (addresses changeable for tests).
  case acc.kind
  of akGraph:
    let tenant = if acc.tenant.len > 0: acc.tenant else: "common"
    result = microsoftProvider(acc.clientId, tenant, graphScopes)
    let base = getEnv("RETRO_MAIL_MSLOGIN")
    if base.len > 0:
      result.authUrl = base & "/" & tenant & "/oauth2/v2.0/authorize"
      result.tokenUrl = base & "/" & tenant & "/oauth2/v2.0/token"
  of akGmail:
    let secret = if clientSecret.len > 0: clientSecret
                 else: loadSecret(secretApp, secretKey(acc.id))
    result = googleProvider(acc.clientId, secret, gmailScopes)
    result.authUrl = gAuthUrl()
    result.tokenUrl = gTokenUrl()

proc plainOf*(html: string): string =
  ## Rough text of HTML, for the search index.
  var inTag = false
  var skip = false
  var i = 0
  while i < html.len:
    let c = html[i]
    if c == '<':
      let rest = html.substr(i, i + 8).toLowerAscii
      if rest.startsWith("<style") or rest.startsWith("<script") or rest.startsWith("<head"): skip = true
      elif rest.startsWith("</style") or rest.startsWith("</script") or rest.startsWith("</head"): skip = false
      if rest.startsWith("<br") or rest.startsWith("<p") or rest.startsWith("<div") or
         rest.startsWith("<tr") or rest.startsWith("<li"):
        result.add '\n'
      inTag = true
    elif c == '>': inTag = false
    elif not inTag and not skip: result.add c
    inc i
  result = result.multiReplace(("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                               ("&quot;", "\""), ("&#39;", "'"))

proc textToHtml*(text: string): string =
  ## A plain-text mail as simple HTML: paragraphs, line breaks, links.
  proc esc(s: string): string = s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"))
  proc linkify(s: string): string =
    var i = 0
    while i < s.len:
      let k = s.find("http", i)
      if k < 0 or not (s.continuesWith("http://", k) or s.continuesWith("https://", k)):
        result.add s[i .. ^1]
        break
      result.add s[i ..< k]
      var e = k
      while e < s.len and s[e] notin {' ', '\t', '\n', '\r', '<', '>', '"'}: inc e
      let u = s[k ..< e]
      result.add "<a href=\"" & u & "\">" & u & "</a>"
      i = e
  result = "<div>"
  for para in text.replace("\r\n", "\n").split("\n\n"):
    var lines: seq[string]
    for l in para.split('\n'):
      let q = l.startsWith(">")
      lines.add (if q: "<span style=\"color:#555\">" & linkify(esc(l)) & "</span>" else: linkify(esc(l)))
    result.add "<p>" & lines.join("<br>") & "</p>"
  result.add "</div>"

# ---- the thread ------------------------------------------------------------------------

type
  Worker = object
    link: ptr SyncLink
    db: Db
    tokens: Table[int, OAuthTokens]
    lastFull: Table[int, float]
    lastFolders: Table[int, float]
    lastCal: Table[int, float]
    interval: float
    newest: Table[int, float]       ## per account: the newest inbox mail seen
    later: seq[SyncCmd]             ## commands put off while syncing

proc send(w: var Worker; ev: SyncEvent) = w.link.events.send(ev)
proc status(w: var Worker; s: string) = w.send(SyncEvent(kind: seStatus, text: s))

proc token(w: var Worker; acc: Account): string =
  ## A fresh access token, or "" (then the account has to sign in again).
  if not w.tokens.hasKey(acc.id):
    let s = loadSecret(secretApp, tokenKey(acc.id))
    if s.len == 0:
      w.db.setAccountState(acc.id, "signin")
      w.send(SyncEvent(kind: seSignIn, id: acc.id))
      return ""
    try: w.tokens[acc.id] = toTokens(parseJson(s))
    except CatchableError:
      w.send(SyncEvent(kind: seSignIn, id: acc.id))
      return ""
  var t = w.tokens[acc.id]
  let before = t.accessToken
  let err = providerFor(acc).ensureFresh(t)
  if err.len > 0:
    if t.accessToken.len == 0 or "invalid_grant" in err or "expired" in err.toLowerAscii or
       "revoked" in err.toLowerAscii:
      w.db.setAccountState(acc.id, "signin")
      w.send(SyncEvent(kind: seSignIn, id: acc.id, text: err))
      w.tokens.del acc.id
      return ""
    w.db.setAccountState(acc.id, err)
    return ""
  if t.accessToken != before:
    discard saveSecret(secretApp, tokenKey(acc.id), $(%t))
  w.tokens[acc.id] = t
  t.accessToken

proc forget(w: var Worker; acc: int) =
  ## The token was refused: refresh it before the next call.
  if w.tokens.hasKey(acc):
    var t = w.tokens[acc]
    t.expiresAt = 0
    w.tokens[acc] = t

proc pending(w: var Worker): seq[SyncCmd] =
  result = move w.later
  while true:
    let (ok, c) = w.link.cmds.tryRecv()
    if not ok: break
    result.add c

# ---- bodies and attachments ------------------------------------------------------------

proc fetchBody(w: var Worker; id: int) =
  let m = w.db.message(id)
  if m.id == 0: return
  let acc = w.db.account(m.account)
  let tok = w.token(acc)
  if tok.len == 0:
    w.send(SyncEvent(kind: seBody, id: id, text: "sign in to read it"))
    return
  try:
    case acc.kind
    of akGraph:
      let b = graphBody(tok, m.remoteId)
      w.db.transaction:
        w.db.setBody(id, b.html, plainOf(b.html))
        w.db.setDetails(id, b.toList, b.ccList, b.msgId, m.inReplyTo, m.refs)
        for a in b.atts:
          discard w.db.addAttachment(id, a.remoteId, a.name, a.mime, a.size, a.cid, a.inline,
                                     a.data, a.hasData)
    of akGmail:
      let b = gmailBody(tok, m.remoteId)
      let html = if b.html.len > 0: b.html else: textToHtml(b.text)
      let text = if b.text.len > 0: b.text else: plainOf(b.html)
      w.db.transaction:
        w.db.setBody(id, html, text)
        w.db.setDetails(id, b.toList, b.ccList, "", m.inReplyTo, m.refs)
        for a in b.atts:
          discard w.db.addAttachment(id, a.remoteId, a.name, a.mime, a.size, a.cid, a.inline,
                                     a.data, a.hasData)
    w.send(SyncEvent(kind: seBody, id: id))
  except ApiError as e:
    if e.status == 401: w.forget(acc.id)
    if e.status == 404: w.db.setBodyState(id, 3)
    w.send(SyncEvent(kind: seBody, id: id, text: e.msg))
  except CatchableError as e:
    w.send(SyncEvent(kind: seBody, id: id, text: e.msg))

proc fetchAttachment(w: var Worker; id: int) =
  let r = w.db.one("SELECT message, remote_id FROM atts WHERE id = ?", id)
  if r.len == 0: return
  let m = w.db.message(int r[0].num)
  let acc = w.db.account(m.account)
  let tok = w.token(acc)
  if tok.len == 0:
    w.send(SyncEvent(kind: seAttachment, id: id, text: "sign in first"))
    return
  try:
    let data = case acc.kind
               of akGraph: graphAttachment(tok, m.remoteId, r[1].str)
               of akGmail: gmailAttachment(tok, m.remoteId, r[1].str)
    w.db.setAttachmentData(id, data)
    w.send(SyncEvent(kind: seAttachment, id: id))
  except CatchableError as e:
    w.send(SyncEvent(kind: seAttachment, id: id, text: e.msg))

# ---- the queue of changes ----------------------------------------------------------------

const gmailColors = ["#4a86e8", "#16a766", "#cc3a21", "#ffad47", "#a479e2", "#2da2bb",
                     "#e07798", "#666666", "#fad165", "#3c78d8"]
const graphPresets = [("#e81123", "preset0"), ("#ff8c00", "preset1"), ("#8b4513", "preset2"),
                      ("#ffd700", "preset3"), ("#00a300", "preset4"), ("#008080", "preset5"),
                      ("#808000", "preset6"), ("#0063b1", "preset7"), ("#7a3ba0", "preset8"),
                      ("#c30052", "preset9"), ("#5d8aa8", "preset10"), ("#36454f", "preset11"),
                      ("#808080", "preset12"), ("#404040", "preset13"), ("#000000", "preset14")]

proc presetColor*(preset: string): string =
  ## An Outlook category's color.
  for (c, p) in graphPresets:
    if p == preset: return c
  case preset
  of "preset15": "#8b0000"
  of "preset16": "#cc5500"
  of "preset17": "#654321"
  of "preset18": "#b8860b"
  of "preset19": "#006400"
  of "preset20": "#004d4d"
  of "preset21": "#556b2f"
  of "preset22": "#00008b"
  of "preset23": "#4b0082"
  of "preset24": "#800020"
  else: ""

proc hexDist(a, b: string): int =
  if a.len < 7 or b.len < 7: return 1 shl 20
  for k in [1, 3, 5]:
    let x = try: fromHex[int](a[k .. k + 1]) except ValueError: 0
    let y = try: fromHex[int](b[k .. k + 1]) except ValueError: 0
    result += (x - y) * (x - y)

proc nearestPreset(color: string): string =
  result = "preset7"
  var best = 1 shl 30
  for (c, p) in graphPresets:
    let d = hexDist(color.toLowerAscii, c)
    if d < best:
      best = d
      result = p

proc nearestGmail(color: string): string =
  result = gmailColors[0]
  var best = 1 shl 30
  for c in gmailColors:
    let d = hexDist(color.toLowerAscii, c)
    if d < best:
      best = d
      result = c

proc gmailLabelIds(w: var Worker; acc: Account; tok: string; names: seq[string]): seq[string] =
  for n in names:
    var t = w.db.tagOf(acc.id, n)
    if t.remoteId.len == 0:
      let id = gmailCreateLabel(tok, n, nearestGmail(t.color))
      w.db.upsertTag(acc.id, n, t.color, id)
      t.remoteId = id
    result.add t.remoteId

proc gmailFolderLabels(role: string): tuple[add, remove: seq[string]] =
  case role
  of "inbox": (@["INBOX"], @["SPAM", "TRASH"])
  of "junk": (@["SPAM"], @["INBOX"])
  of "archive": (@[], @["INBOX", "SPAM"])
  else: (@[], @[])

proc runAction(w: var Worker; acc: Account; tok: string; a: Action) =
  let d = a.data
  let id = d{"id"}.getInt
  var m = if id > 0: w.db.message(id) else: Msg()
  let remote = if m.remoteId.len > 0: m.remoteId else: d{"remote"}.getStr
  case a.kind
  of "read":
    let unread = d{"unread"}.getBool
    case acc.kind
    of akGraph: graphPatch(tok, remote, %*{"isRead": not unread})
    of akGmail:
      if unread: gmailModify(tok, remote, ["UNREAD"], [])
      else: gmailModify(tok, remote, [], ["UNREAD"])
  of "flag":
    let on = d{"flagged"}.getBool
    case acc.kind
    of akGraph: graphPatch(tok, remote, %*{"flag": {"flagStatus": (if on: "flagged" else: "notFlagged")}})
    of akGmail:
      if on: gmailModify(tok, remote, ["STARRED"], [])
      else: gmailModify(tok, remote, [], ["STARRED"])
  of "tags":
    var names: seq[string]
    for t in d{"tags"}.getElems: names.add t.getStr
    case acc.kind
    of akGraph:
      for n in names:
        let t = w.db.tagOf(acc.id, n)
        if t.remoteId.len == 0:
          graphAddCategory(tok, n, nearestPreset(t.color))
          w.db.upsertTag(acc.id, n, t.color, n)
      graphPatch(tok, remote, %*{"categories": names})
    of akGmail:
      var removed: seq[string]
      for t in d{"removed"}.getElems: removed.add t.getStr
      let addIds = w.gmailLabelIds(acc, tok, names)
      var remIds: seq[string]
      for n in removed:
        let t = w.db.tagOf(acc.id, n)
        if t.remoteId.len > 0: remIds.add t.remoteId
      gmailModify(tok, remote, addIds, remIds)
  of "move":
    let dest = w.db.folder(d{"folder"}.getInt)
    case acc.kind
    of akGraph:
      if dest.role == "trash" and m.folder > 0 and w.db.folder(m.folder).role == "trash":
        graphDeleteForever(tok, remote)
        if id > 0: w.db.deleteMessage(id)
      else:
        let newId = graphMove(tok, remote, dest.remoteId)
        if newId.len > 0 and id > 0:
          w.db.exec("UPDATE messages SET remote_id = ? WHERE id = ?", newId, id)
    of akGmail:
      if dest.role == "trash": gmailTrash(tok, remote)
      else:
        if m.folder > 0 and w.db.folder(m.folder).role == "trash": gmailUntrash(tok, remote)
        let (add, rem) = gmailFolderLabels(dest.role)
        if add.len + rem.len > 0: gmailModify(tok, remote, add, rem)
  of "newtag":
    let name = d{"name"}.getStr
    let color = d{"color"}.getStr
    case acc.kind
    of akGraph:
      graphAddCategory(tok, name, nearestPreset(color))
      w.db.upsertTag(acc.id, name, color, name)
    of akGmail:
      let lid = gmailCreateLabel(tok, name, nearestGmail(color))
      w.db.upsertTag(acc.id, name, color, lid)
  of "send":
    case acc.kind
    of akGraph: graphSend(tok, d)
    of akGmail:
      let raw = buildRaw(d, MailAddress(name: acc.name, email: acc.email))
      gmailSend(tok, raw, d{"threadId"}.getStr)
    for at in d{"attachments"}.getElems:
      if at{"copy"}.getBool:
        try: removeFile(at{"path"}.getStr) except OSError: discard
    for r in d{"to"}.getElems & d{"cc"}.getElems:
      w.db.noteContact(r{"email"}.getStr, r{"name"}.getStr, epochTime())
    w.send(SyncEvent(kind: seSent, text: d{"subject"}.getStr))
  else: discard

proc runActions(w: var Worker; acc: Account): bool =
  ## Sends the account's queued changes; true when something was done.
  let due = w.db.dueActions(acc.id)
  if due.len == 0: return
  let tok = w.token(acc)
  if tok.len == 0: return
  for a in due:
    if a.kind == "send": w.status("Sending \"" & a.data{"subject"}.getStr & "\"...")
    try:
      w.runAction(acc, tok, a)
      w.db.doneAction(a.id)
      result = true
    except ApiError as e:
      if e.status == 401:
        w.forget(acc.id)
        w.db.retryAction(a.id, 5)
        break
      elif e.status == 0 or e.status == 429 or e.status >= 500 or e.status == 408:
        let wait = if e.retryAfter > 0: e.retryAfter else: min(600.0, 10.0 * float(1 shl min(a.tries, 6)))
        w.db.retryAction(a.id, wait)
        if e.status == 0: break           # (offline: the rest waits too)
      else:
        w.db.failAction(a.id, e.msg)
        w.send(SyncEvent(kind: seError, id: acc.id, text: e.msg))
    except CatchableError as e:
      w.db.failAction(a.id, e.msg)
      w.send(SyncEvent(kind: seError, id: acc.id, text: e.msg))
  w.status("")

# ---- syncing ---------------------------------------------------------------------------

proc noteNew(w: var Worker; acc: Account; m: Msg; folderRole: string; count: var int;
             latest: var string) =
  if folderRole != "inbox" or not m.unread or m.mine: return
  let seen = w.newest.getOrDefault(acc.id, -1.0)
  if seen < 0: return                    # (the first sync: nothing is "new")
  if m.date > seen:
    inc count
    latest = (if m.fromName.len > 0: m.fromName else: m.fromEmail) & ": " & m.subject

proc markNewest(w: var Worker; acc: Account) =
  let v = w.db.value("SELECT max(date) FROM messages m JOIN folders f ON f.id = m.folder " &
                     "WHERE m.account = ? AND f.role = 'inbox'", acc.id)
  w.newest[acc.id] = (if v.isNull: -1.0 else: v.flt)

proc syncGraph(w: var Worker; acc: Account; tok: string; count: var int; latest: var string) =
  let me = acc.email
  if epochTime() - w.lastFolders.getOrDefault(acc.id, 0) > 1800:
    w.status("Checking folders of " & acc.email & "...")
    let fs = graphFolders(tok)
    var keep: HashSet[string]
    w.db.transaction:
      for f in fs:
        keep.incl f.remoteId
        discard w.db.upsertFolder(acc.id, f.remoteId, f.name, f.role, f.parent, f.unread, f.total)
      for f in w.db.folders(acc.id):
        if f.remoteId notin keep:
          for r in w.db.all("SELECT id FROM messages WHERE folder = ?", f.id):
            w.db.deleteMessage(int r[0].num)
          w.db.exec("DELETE FROM folders WHERE id = ?", f.id)
    try:
      let cats = graphCategories(tok)
      w.db.transaction:
        for c in cats: w.db.upsertTag(acc.id, c.name, presetColor(c.color), c.name)
    except ApiError: discard
    w.lastFolders[acc.id] = epochTime()
  for f in w.db.folders(acc.id):
    if f.role == "outbox": continue
    var delta = f.delta
    for round in 0 ..< 20:
      w.status("Downloading " & f.name & " of " & acc.email & "...")
      var res: tuple[items: seq[GraphItem]; next: string; done: bool]
      try:
        res = graphDelta(tok, f.remoteId, delta, acc.syncDays, acc.id, me)
      except ApiError as e:
        if e.status in [400, 404, 410]:
          w.db.setFolderDelta(f.id, "")        # (an expired delta: start again next time)
          break
        raise
      w.db.transaction:
        for it in res.items:
          if it.removed:
            w.db.deleteByRemote(acc.id, it.msg.remoteId)
            continue
          var m = it.msg
          let fr = if it.folderRemote.len > 0: w.db.folderByRemote(acc.id, it.folderRemote) else: f
          m.folder = if fr.id > 0: fr.id else: f.id
          w.noteNew(acc, m, (if fr.id > 0: fr.role else: f.role), count, latest)
          discard w.db.upsertMessage(m)
          w.db.noteContact(m.fromEmail, m.fromName, m.date)
        w.db.setFolderDelta(f.id, res.next)
      if res.items.len > 0: w.send(SyncEvent(kind: seChanged))
      if res.done or res.next.len == 0: break
      delta = res.next
      for c in w.pending():          # (the window may want a body meanwhile)
        case c.kind
        of scBody: w.fetchBody(c.id)
        of scAttachment: w.fetchAttachment(c.id)
        of scQuit:
          w.later.add c
          return
        else: w.later.add c
  w.db.recount(acc.id)

proc syncGmail(w: var Worker; acc: Account; tok: string; count: var int; latest: var string) =
  var names = initTable[string, string]()
  if epochTime() - w.lastFolders.getOrDefault(acc.id, 0) > 1800 or acc.history.len == 0:
    w.status("Checking labels of " & acc.email & "...")
    let labels = gmailLabels(tok)
    w.db.transaction:
      for (rid, name, role) in systemFolders:
        discard w.db.upsertFolder(acc.id, rid, name, role, "")
      for l in labels:
        if l.kind == "user":
          w.db.upsertTag(acc.id, l.name, l.color, l.id)
    w.lastFolders[acc.id] = epochTime()
  for t in w.db.tags(acc.id):
    if t.remoteId.len > 0: names[t.remoteId] = t.name
  proc store(w: var Worker; metas: seq[JsonNode]; count: var int; latest: var string) =
    w.db.transaction:
      for j in metas:
        let (m0, fr) = parseMeta(j, acc.id, acc.email, names)
        var m = m0
        let f = w.db.folderByRemote(acc.id, fr)
        m.folder = f.id
        w.noteNew(acc, m, f.role, count, latest)
        discard w.db.upsertMessage(m)
        w.db.noteContact(m.fromEmail, m.fromName, m.date)
  if acc.history.len == 0:
    w.status("Listing the mail of " & acc.email & "...")
    let (_, hist) = gmailProfile(tok)
    let ids = gmailListIds(tok, "newer_than:" & $max(acc.syncDays, 1) & "d", 20000)
    var i = 0
    while i < ids.len:
      w.status("Downloading " & acc.email & ": " & $i & " of " & $ids.len & "...")
      let chunk = ids[i ..< min(i + 200, ids.len)]
      w.store(gmailMetadata(tok, chunk), count, latest)
      w.send(SyncEvent(kind: seChanged))
      i += 200
      for c in w.pending():
        case c.kind
        of scBody: w.fetchBody(c.id)
        of scAttachment: w.fetchAttachment(c.id)
        of scQuit:
          w.later.add c
          return
        else: w.later.add c
    w.db.setHistory(acc.id, hist)
  else:
    var ch: tuple[changed, deleted: seq[string]; latest: string]
    try:
      ch = gmailHistory(tok, acc.history)
    except ApiError as e:
      if e.status == 404:
        w.db.setHistory(acc.id, "")
        return
      raise
    if ch.deleted.len > 0:
      w.db.transaction:
        for d in ch.deleted: w.db.deleteByRemote(acc.id, d)
    if ch.changed.len > 0:
      w.status("Downloading " & $ch.changed.len & " changes of " & acc.email & "...")
      let metas = gmailMetadata(tok, ch.changed)
      w.store(metas, count, latest)
      # messages history reported but gone (deleted for good meanwhile)
      var got: HashSet[string]
      for j in metas: got.incl j{"id"}.getStr
      w.db.transaction:
        for id in ch.changed:
          if id notin got: w.db.deleteByRemote(acc.id, id)
    w.db.setHistory(acc.id, ch.latest)
    if ch.changed.len + ch.deleted.len > 0: w.send(SyncEvent(kind: seChanged))
  w.db.recount(acc.id)

proc syncCalendar(w: var Worker; acc: Account; tok: string) =
  let fromT = epochTime() - 31 * 86400
  let toT = epochTime() + 92 * 86400
  let evs = case acc.kind
            of akGraph: graphCalendar(tok, fromT, toT, acc.id)
            of akGmail: gmailCalendar(tok, fromT, toT, acc.id)
  w.db.transaction:
    w.db.clearEvents(acc.id, fromT, toT)
    for e in evs: w.db.upsertEvent(e)
  w.lastCal[acc.id] = epochTime()

proc prefetch(w: var Worker; acc: Account; n = 25) =
  ## Bodies of the newest messages, so they open at once (and offline).
  for r in w.db.all("SELECT id FROM messages WHERE account = ? AND body_state = 0 " &
                    "ORDER BY date DESC LIMIT ?", acc.id, n):
    if w.link.cmds.peek() > 0: break
    w.fetchBody(int r[0].num)

proc syncAccount(w: var Worker; acc: Account) =
  for attempt in 0 .. 1:
    let tok = w.token(acc)
    if tok.len == 0: return
    var count = 0
    var latest = ""
    try:
      if acc.state.len > 0: w.db.setAccountState(acc.id, "")
      if not w.newest.hasKey(acc.id): w.markNewest(acc)
      case acc.kind
      of akGraph: w.syncGraph(acc, tok, count, latest)
      of akGmail: w.syncGmail(w.db.account(acc.id), tok, count, latest)
      w.markNewest(acc)
      if epochTime() - w.lastCal.getOrDefault(acc.id, 0) > 900:
        try: w.syncCalendar(acc, tok)
        except ApiError: discard         # (no calendar permission: mail still works)
      w.prefetch(acc)
      w.lastFull[acc.id] = epochTime()
      if count > 0: w.send(SyncEvent(kind: seNewMail, id: acc.id, count: count, text: latest))
      w.send(SyncEvent(kind: seChanged))
      return
    except ApiError as e:
      if e.status == 401 and attempt == 0:
        w.forget(acc.id)                 # (refused: a fresh token, once more)
        continue
      w.db.setAccountState(acc.id, e.msg)
      w.send(SyncEvent(kind: seError, id: acc.id, text: e.msg))
    except CatchableError as e:
      w.db.setAccountState(acc.id, e.msg)
      w.send(SyncEvent(kind: seError, id: acc.id, text: e.msg))
    w.send(SyncEvent(kind: seChanged))
    return

proc search(w: var Worker; q: string) =
  var ids: seq[int]
  for acc in w.db.accounts():
    let tok = w.token(acc)
    if tok.len == 0: continue
    try:
      case acc.kind
      of akGraph:
        for it in graphSearch(tok, q, acc.id, acc.email):
          var m = it.msg
          let f = w.db.folderByRemote(acc.id, it.folderRemote)
          if f.id == 0: continue
          m.folder = f.id
          ids.add w.db.upsertMessage(m)
      of akGmail:
        var names = initTable[string, string]()
        for t in w.db.tags(acc.id):
          if t.remoteId.len > 0: names[t.remoteId] = t.name
        let found = gmailListIds(tok, q, 100)
        for j in gmailMetadata(tok, found):
          let (m0, fr) = parseMeta(j, acc.id, acc.email, names)
          var m = m0
          m.folder = w.db.folderByRemote(acc.id, fr).id
          ids.add w.db.upsertMessage(m)
    except CatchableError as e:
      w.send(SyncEvent(kind: seError, id: acc.id, text: e.msg))
  w.send(SyncEvent(kind: seSearch, ids: ids, text: q))

proc syncMain*(link: ptr SyncLink) {.thread.} =
  ## The sync thread's body.
  {.gcsafe.}:
    var w = Worker(link: link, interval: 60)
    try:
      w.db = openStore(link.dbPath)
    except CatchableError as e:
      link.events.send(SyncEvent(kind: seError, text: "the store: " & e.msg))
      return
    var force = true
    var running = true
    var lastActions = 0.0
    while running:
      var wantSync = force
      force = false
      for c in w.pending():
        case c.kind
        of scQuit: running = false
        of scSyncNow, scAccounts:
          wantSync = true
          if c.kind == scAccounts: w.tokens.clear()
          for k in w.lastFolders.mvalues: k = 0
          for k in w.lastCal.mvalues: k = 0
        of scWake: lastActions = 0
        of scBody: w.fetchBody(c.id)
        of scAttachment: w.fetchAttachment(c.id)
        of scSearch: w.search(c.text)
        of scSettings: w.interval = float(max(1, c.count) * 60)
      if not running: break
      let accs = w.db.accounts()
      # changes made here go out first (every few seconds while there are some)
      if epochTime() - lastActions > 3:
        var did = false
        for a in accs:
          if w.runActions(a): did = true
        if did: w.send(SyncEvent(kind: seChanged))
        lastActions = epochTime()
      for a in accs:
        if wantSync or epochTime() - w.lastFull.getOrDefault(a.id, 0) > w.interval:
          w.syncAccount(a)
          w.status("")
          if w.link.cmds.peek() > 0: break
      # sleep a little, waking for commands
      for i in 0 ..< 10:
        if w.link.cmds.peek() > 0: break
        sleep(100)
    w.db.close()
