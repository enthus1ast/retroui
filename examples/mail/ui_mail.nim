# Retro Mail: the mail window -- Outlook bar, folder bar, folder tree,
# contacts pane, tool bar, menus, the message list with threads and tags,
# the reading pane with the whole conversation. Included by examples/mail.nim.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

proc openWizard()

var treeOpen = initTable[string, bool]()
var treeSel = "start"
var lastTreeSel = ""
var contactSel = -1
var contactNames: seq[string]
var contactMails: seq[string]
var attMenuId = 0
var saveAttOpen = false
var saveAttPath = ""
var saveAttId = 0
var openAttAfter = 0

proc goPlace(p: Place) =
  place = p
  view = vMail
  query = ""
  serverIds.setLen(0)
  selKey = ""
  selRow = -1
  listScroll = 0
  if isCompact(): phone = phList
  changed()

proc allMsgsOf(rowsSel: seq[Msg]): seq[Msg] = rowsSel

# ---- the Outlook bar ---------------------------------------------------------------------

proc outlookBar() =
  let r = place(available(), remainingH(), fill = true)
  fill(r, ui.theme.shadow)
  var y = r.y + dp(10)
  let unread = block:
    var n = 0
    for fs in foldersC.values:
      for f in fs:
        if f.role == "inbox": n += f.unread
    n
  for (v, px, name) in [(vMail, pxMail, "Mail"), (vCalendar, pxCalendar, "Calendar"),
                        (vPeople, pxUser, "People"), (vTodo, pxCheck, "To Do"),
                        (vNotes, pxNote, "Notes")]:
    let cell = rect(r.x + dp(4), y, r.w - dp(8), dp(62))
    let hit = interact(idOf("obar" & name), cell, focusable = false)
    let on = view == v or (v == vMail and view == vStart)
    if hit.clicked:
      view = v
      if v == vMail and accountsC.len > 0 and treeSel == "start":
        goPlace(Place(kind: plAllInbox))
        treeSel = "fav:inbox"
    if on:
      fill(cell, ui.theme.face)
      sunken(cell)
    elif hit.hover:
      raised(cell, 1)
    let ic = pixelIcon(px, big = true)
    image(cell.x + (cell.w - ic.w) div 2, cell.y + dp(6), ic)
    text(cell.x + (cell.w - textWidth(name)) div 2, cell.y + dp(42), name,
         if on: ui.theme.text else: rgb(255, 255, 255))
    if v == vMail and unread > 0:
      let s = $unread
      let bw = textWidth(s, style(bold = true, size = 0.8)) + dp(8)
      roundRect(rect(cell.x + cell.w - bw - dp(4), cell.y + dp(4), bw, dp(16)), float(dp(7)),
                rgb(200, 0, 0))
      text(cell.x + cell.w - bw, cell.y + dp(5), s, rgb(255, 255, 255), style(bold = true, size = 0.8))
    y += dp(70)

# ---- the folder bar ----------------------------------------------------------------------

proc folderBar(title, sub: string; tag = "") =
  let r = place(available(), dp(36), fill = true)
  fill(r, ui.theme.shadow)
  let st = style(size = 1.5, bold = true)
  var x = r.x + dp(12)
  text(x, r.y + (r.h - lineHeight(st)) div 2, fit(title, r.w div 3, st), rgb(255, 255, 255), st)
  x += min(textWidth(title, st), r.w div 3) + dp(10)
  if tag.len > 0:
    x += pillAt(x, r.y + dp(10), tag, tagColor(tag)) + dp(8)
  let sw = min(dp(340), r.x + r.w - x - dp(16))
  if r.w > dp(700):
    text(x, r.y + (r.h - lineHeight()) div 2, fit(sub, r.x + r.w - sw - x - dp(24)),
         rgb(220, 220, 220))
  if sw > dp(120):
    pushFrame(rect(r.x + r.w - sw - dp(10), r.y + (r.h - EditH) div 2, sw, 0))
    if searchBox(query, "Search: from: to: has: tag: is: before:"):
      serverIds.setLen(0)
      searching = ""
      if query.len > 0: view = vMail
      selRow = -1
      selKey = ""
      listScroll = 0
      changed()
    discard popFrame()

# ---- the folder tree ---------------------------------------------------------------------

proc branchOpen(key: string): bool = treeOpen.getOrDefault(key, true)

proc folderPic(f: Folder): Icon =
  case f.role
  of "inbox": pixelIcon(pxInbox)
  of "drafts": pixelIcon(pxDocument)
  of "sent": pixelIcon(pxMail)
  of "outbox": pixelIcon(pxForward)
  of "archive": pixelIcon(pxArchive)
  of "junk": pixelIcon(pxWarning)
  of "trash": pixelIcon(if f.total > 0: pxTrashFull else: pxTrash)
  else: pixelIcon(pxFolder)

proc folderNode(f: Folder; fs: seq[Folder]) =
  ## A folder in the tree, its sub-folders under it.
  let name = if f.unread > 0 and f.role notin ["sent", "drafts", "trash", "junk"]:
               f.name & " (" & $f.unread & ")" else: f.name
  var kids: seq[Folder]
  for k in fs:
    if k.parent == f.remoteId and k.id != f.id: kids.add k
  if kids.len == 0:
    leaf(name, pic = folderPic(f), id = "f:" & $f.id)
  else:
    var o = branchOpen("f" & $f.id)
    branch(name, o, folderPic(f), "f:" & $f.id, true):
      for k in kids: folderNode(k, fs)
    treeOpen["f" & $f.id] = o

proc folderTree() =
  tree(treeSel, -1):
    var rootOpen = branchOpen("root")
    branch(appName, rootOpen, pixelIcon(pxHome), "start", true):
      if accountsC.len > 1:
        var favOpen = branchOpen("fav")
        branch("Favorites", favOpen, pixelIcon(pxFolderStar), "fav", true):
          var ib = 0
          for fs in foldersC.values:
            for f in fs:
              if f.role == "inbox": ib += f.unread
          leaf((if ib > 0: "All Inboxes (" & $ib & ")" else: "All Inboxes"),
               pic = pixelIcon(pxInbox), id = "fav:inbox")
          leaf("Unread Mail", pic = pixelIcon(pxMail), id = "fav:unread")
          leaf("Flagged", pic = pixelIcon(pxStar), id = "fav:flagged")
          leaf("Pinned", pic = pixelIcon(pxPin), id = "fav:pinned")
          leaf("Snoozed", pic = pixelIcon(pxClock), id = "fav:snoozed")
        treeOpen["fav"] = favOpen
      for a in accountsC:
        var o = branchOpen("a" & $a.id)
        let label = if a.state == "signin": a.email & " (sign in)" else: a.email
        branch(label, o, pixelIcon(pxGlobe), "acct:" & $a.id, true):
          let fs = foldersC.getOrDefault(a.id)
          var ids: HashSet[string]
          for f in fs: ids.incl f.remoteId
          for f in fs:
            if f.parent notin ids: folderNode(f, fs)
        treeOpen["a" & $a.id] = o
      if accountsC.len == 1:
        leaf("Unread Mail", pic = pixelIcon(pxMail), id = "fav:unread")
        leaf("Flagged", pic = pixelIcon(pxStar), id = "fav:flagged")
        leaf("Pinned", pic = pixelIcon(pxPin), id = "fav:pinned")
        leaf("Snoozed", pic = pixelIcon(pxClock), id = "fav:snoozed")
      if tagsC.len > 0:
        var tOpen = branchOpen("tags")
        branch("Tags", tOpen, glyphIcon(nfTags, rgb(0, 0, 128)), "tags", true):
          for t in tagsC:
            leaf(t.name, pic = glyphIcon(nfSquare, tagColor(t.name)), id = "tag:" & t.name)
        treeOpen["tags"] = tOpen
    treeOpen["root"] = rootOpen
  if treeSel != lastTreeSel:
    lastTreeSel = treeSel
    if treeSel == "start": view = vStart
    elif treeSel.startsWith("f:"):
      goPlace(Place(kind: plFolder, folder: (try: parseInt(treeSel[2 .. ^1]) except ValueError: 0)))
    elif treeSel.startsWith("tag:"): goPlace(Place(kind: plTag, tag: treeSel[4 .. ^1]))
    elif treeSel == "fav:inbox": goPlace(Place(kind: plAllInbox))
    elif treeSel == "fav:unread": goPlace(Place(kind: plUnread))
    elif treeSel == "fav:flagged": goPlace(Place(kind: plFlagged))
    elif treeSel == "fav:pinned": goPlace(Place(kind: plPinned))
    elif treeSel == "fav:snoozed": goPlace(Place(kind: plSnoozed))

proc contactsPane() =
  let r = place(available(), lineHeight() + dp(8), fill = true)
  fill(r, ui.theme.face)
  raised(r, 1)
  text(r.x + dp(6), r.y + dp(4), "Contacts", ui.theme.text, style(bold = true))
  if contactNames.len == 0 or listVer mod 7 == 0:
    contactNames.setLen(0)
    contactMails.setLen(0)
    for c in store0.contacts(limit = 200):
      contactNames.add(if c.name.len > 0: c.name else: c.email)
      contactMails.add c.email
  if contactNames.len == 0:
    paragraph "There are no contacts to display. People you write to and hear from show here."
  else:
    let before = contactSel
    listbox(contactNames, contactSel, rows = -1)
    if ui.doubleClick and contactSel >= 0 and contactSel == before:
      openCompose("new", to = contactNames[contactSel] & " <" & contactMails[contactSel] & ">")

# ---- tool bar and menus ------------------------------------------------------------------

proc doReply(mode: string) =
  let ms = selectedMsgs()
  if ms.len == 0: return
  openCompose(mode, store0.message(ms[0].id))

proc mailToolbar() =
  setToolbarLook(if isCompact(): blIconOnly else: blTextBelow)
  let has = selRow >= 0 and selectedMsgs().len > 0
  let ms = if has: selectedMsgs() else: @[]
  toolbar:
    if barButton(pxMail, "Compose", "Compose a message (Ctrl+N)", enabled = accountsC.len > 0):
      openCompose("new")
    if barButton(pxBack, "Reply", "Reply to the author (Ctrl+R)", enabled = has): doReply("reply")
    if barButton(pxUndo, "Reply All", "Reply to all (Ctrl+Shift+R)", enabled = has): doReply("replyAll")
    if barButton(pxForward, "Forward", "Forward (Ctrl+F)", enabled = has): doReply("forward")
    toolSeparator()
    if barButton(pxRefresh, "Send/Recv", "Send and receive (F5)", enabled = accountsC.len > 0):
      link.cmds.send(SyncCmd(kind: scSyncNow))
      syncText = "Checking for new mail..."
    if barButton(pxDelete, "Delete", "Delete (Del)", enabled = has): deleteMsgs(ms)
    if barButton(pxArchive, "Archive", "Archive (Backspace)", enabled = has): archiveMsgs(ms)
    toolSeparator()
    if barButton(nfFlag, "Flag", "Flag (Insert)", enabled = has): toggleFlag(ms)
    if barButton(pxPin, "Pin", "Pin to the top", enabled = has): pinMsgs(ms)
    if barButton(pxClock, "Snooze", "Snooze until later", enabled = has):
      snoozeOpen = true
    if barButton(nfTags, "Tags", "Tag the message (Ctrl+T)", down = tagMenuOpen, enabled = has):
      tagMenuOpen = not tagMenuOpen
    tagMenuAt = ui.lastRect
    toolSeparator()
    if barButton(nfComments, "Threads", "Show messages as threads",
                 down = prefBool("threads", true)):
      prefs.put("threads", not prefBool("threads", true))
      savePrefs()
      changed()
    if barButton(pxUser, "Addresses", "The address book (Ctrl+Shift+B)"): view = vPeople
    if barButton(pxSearch, "Find", "Search (Ctrl+E)"): ui.textFocusWanted = true

proc menus() =
  let ms = selectedMsgs()
  let has = ms.len > 0
  menubar:
    menu "&File":
      if menuItem("&New Message", "Ctrl+N", enabled = accountsC.len > 0): openCompose("new")
      if menuItem("&Add Account..."): openWizard()
      menuSeparator()
      if menuItem("&Send and Receive", "F5"): link.cmds.send(SyncCmd(kind: scSyncNow))
      menuSeparator()
      if menuItem("E&xit", "Alt+F4"): quitApp()
    menu "&Edit":
      if menuItem("&Delete", "Del", enabled = has): deleteMsgs(ms)
      if menuItem("&Archive", "Backspace", enabled = has): archiveMsgs(ms)
      menuSeparator()
      if menuItem("Mark as &Read", "Ctrl+Q", enabled = has): markRead(ms)
      if menuItem("Mark as &Unread", "Ctrl+U", enabled = has): markRead(ms, true)
      if menuItem("Mark All as R&ead", enabled = convs.len > 0):
        var all: seq[Msg]
        for c in convs: all.add c.msgs
        markRead(all)
      menuSeparator()
      if menuItem("&Find Message...", "Ctrl+E"): ui.textFocusWanted = true
    menu "&View":
      if menuItem("&Threads", checked = prefBool("threads", true)):
        prefs.put("threads", not prefBool("threads", true))
        savePrefs()
        changed()
      if menuItem("&Focused Inbox", checked = prefBool("focused", true)):
        prefs.put("focused", not prefBool("focused", true))
        savePrefs()
        changed()
      submenu "&Reading Pane":
        for (k, label) in [("bottom", "&Below the List"), ("right", "&Beside the List"),
                           ("off", "&Off")]:
          if menuItem(label, checked = pref("pane", "bottom") == k):
            prefs.put("pane", k)
            savePrefs()
      if menuItem("&My Day", checked = prefBool("myday", true)):
        prefs.put("myday", not prefBool("myday", true))
        savePrefs()
      if menuItem("&Contacts Pane", checked = prefBool("contactspane", true)):
        prefs.put("contactspane", not prefBool("contactspane", true))
        savePrefs()
    menu "&Go":
      if menuItem("&Inbox", "Ctrl+1"): goPlace(Place(kind: plAllInbox))
      if menuItem("&Calendar", "Ctrl+2"): view = vCalendar
      if menuItem("&People", "Ctrl+3"): view = vPeople
      if menuItem("&To Do", "Ctrl+4"): view = vTodo
      if menuItem("&Notes", "Ctrl+5"): view = vNotes
      menuSeparator()
      if menuItem("&Start Page"): view = vStart
    menu "&Message":
      if menuItem("&New Message", "Ctrl+N", enabled = accountsC.len > 0): openCompose("new")
      if menuItem("&Reply to Sender", "Ctrl+R", enabled = has): doReply("reply")
      if menuItem("Reply to &All", "Ctrl+Shift+R", enabled = has): doReply("replyAll")
      if menuItem("&Forward", "Ctrl+F", enabled = has): doReply("forward")
      menuSeparator()
      if menuItem("F&lag", "Insert", enabled = has): toggleFlag(ms)
      if menuItem("&Pin", enabled = has): pinMsgs(ms)
      if menuItem("S&nooze...", enabled = has): snoozeOpen = true
      if menuItem("&Tags...", "Ctrl+T", enabled = has): tagMenuOpen = true
      if menuItem("&Move to Folder...", "Ctrl+Shift+V", enabled = has): moveOpen = true
      if menuItem("Mark as &Junk", enabled = has): moveMsgs(ms, "junk")
    menu "&Tools":
      if menuItem("&Send and Receive", "F5"): link.cmds.send(SyncCmd(kind: scSyncNow))
      if menuItem("&Address Book...", "Ctrl+Shift+B"): view = vPeople
      menuSeparator()
      if menuItem("&Accounts..."):
        optTab = 1
        optOpen = true
      if menuItem("&Options..."): optOpen = true
    menu "&Help":
      if menuItem("&Keyboard Shortcuts"):
        status = "Ctrl+N new, Ctrl+R reply, Ctrl+F forward, Del delete, Backspace archive, " &
                 "Insert flag, Ctrl+Q read, Ctrl+T tags, F5 send/receive, Ctrl+E search"
      if menuItem("&About Retro Mail..."): aboutOpen = true

# ---- the message list --------------------------------------------------------------------

proc plusBox(x, y: int; open: bool) =
  let s = dp(9)
  fill(rect(x, y, s, s), ui.theme.field)
  box(rect(x, y, s, s), ui.theme.shadow)
  hline(x + 2, y + s div 2, s - 4, ui.theme.text)
  if not open: vline(x + s div 2, y + 2, s - 4, ui.theme.text)

proc swipeAction(right: bool; ms: seq[Msg]) =
  let choice = swipeChoices[prefInt(if right: "swipeRight" else: "swipeLeft", if right: 0 else: 1)]
  case choice
  of "Archive": archiveMsgs(ms)
  of "Delete": deleteMsgs(ms)
  of "Mark as read": markRead(ms, ms.allIt(not it.unread))
  of "Flag": toggleFlag(ms)
  of "Pin": pinMsgs(ms)
  of "Snooze": snoozeMsgs(ms, laterToday())
  of "Move to...": moveOpen = true
  of "Tag...": tagMenuOpen = true
  else: discard

proc swipeLook(right: bool): tuple[c: Color; label, px: string] =
  let choice = swipeChoices[prefInt(if right: "swipeRight" else: "swipeLeft", if right: 0 else: 1)]
  case choice
  of "Archive": (rgb(0, 140, 60), "Archive", pxArchive)
  of "Delete": (rgb(200, 0, 0), "Delete", pxTrash)
  of "Mark as read": (rgb(0, 90, 200), "Read", pxMail)
  of "Flag": (rgb(220, 120, 0), "Flag", pxStar)
  of "Pin": (rgb(120, 40, 160), "Pin", pxPin)
  of "Snooze": (rgb(0, 120, 140), "Snooze", pxClock)
  of "Move to...": (rgb(90, 90, 90), "Move", pxFolder)
  else: (rgb(0, 90, 200), "Tag", pxStar)

proc swipeUnder(full: Rect; dx: int) =
  ## What a swipe does, under the row being swiped.
  let (c, label, px) = swipeLook(dx > 0)
  fill(full, c)
  let ic = pixelIcon(px)
  let st = style(bold = true)
  let tw = textWidth(label, st)
  if dx > 0:
    image(full.x + dp(12), full.y + (full.h - ic.h) div 2, ic)
    text(full.x + dp(34), full.y + (full.h - lineHeight(st)) div 2, label, rgb(255, 255, 255), st)
  else:
    image(full.x + full.w - dp(28), full.y + (full.h - ic.h) div 2, ic)
    text(full.x + full.w - tw - dp(36), full.y + (full.h - lineHeight(st)) div 2, label,
         rgb(255, 255, 255), st)

proc swipeInput(i: int; rr: Rect): int =
  ## Follows a finger swiping row `i` sideways; how far it is now.
  if not canInput(): return 0
  if ui.pressed and mouseIn(rr) and (fingers() or prefBool("mouseSwipe", false)):
    swipeRow = i
    swipeX0 = ui.mx
    swipeY0 = ui.my
    swiping = false
    swipeDx = 0
  if swipeRow != i: return 0
  if ui.mouseDown:
    let dx = ui.mx - swipeX0
    let dy = ui.my - swipeY0
    if not swiping and abs(dx) > dp(14) and abs(dx) > 2 * abs(dy):
      swiping = true
      ui.dragsActive = true
    if swiping:
      swipeDx = dx
      ui.redraw = true
      return dx
    if abs(dy) > dp(14): swipeRow = -1
    return 0
  # let go
  let dx = swipeDx
  let was = swiping
  swipeRow = -1
  swiping = false
  swipeDx = 0
  if was and abs(dx) > rr.w * 35 div 100:
    let r = rows[i]
    let ms = if r.msg >= 0: @[convs[r.conv].msgs[r.msg]]
             else: convs[r.conv].msgs.filterIt(it.id notin mates)
    swipeAction(dx > 0, ms)
  ui.pressUsed = true
  0

proc selectRow(i: int) =
  if i < 0 or i >= rows.len or rows[i].group.len > 0: return
  selRow = i
  selKey = convs[rows[i].conv].key
  openVer = -1

proc moveRow(delta: int) =
  var i = selRow
  for k in 0 ..< rows.len:
    i += delta
    if i < 0 or i >= rows.len: return
    if rows[i].group.len == 0:
      selectRow(i)
      return

const listCols = [18, 22, 18, 18, 18, 190, 0, 150, 92, 64]   ## 0: the rest

proc mailList() =
  let r = place(available(), remainingH(), fill = true)
  fill(r, ui.theme.field)
  sunken(r)
  let inner = inset(r, 1)
  let lh = lineHeight()
  let hh = lh + dp(6)
  let rh = lh + dp(8)
  let sbw = dp(17)
  let listId = idOf("maillist")
  let area = rect(inner.x, inner.y + hh, inner.w - sbw, inner.h - hh)
  let total = rows.len * rh
  let hi = max(0, total - area.h)
  scrollWheel(listId, listScroll, hi, area, rh * 3)
  if not swiping: scrollPan(listId, listScroll, hi, area)
  scrollTick(listId, listScroll, hi)
  scrollBarFor(idOf("maillistbar"), listId, rect(inner.x + inner.w - sbw, inner.y + hh, sbw,
               area.h), true, listScroll, hi, area.h, rh)
  # widths: the tags column only when there are tags
  var ws: seq[int]
  var fixed = 0
  let showTags = tagsC.len > 0
  for k, w in listCols:
    let ww = if k == 7 and not showTags: 0 else: dp(w)
    fixed += ww
  for k, w in listCols:
    ws.add(if w == 0: max(dp(120), area.w - fixed) elif k == 7 and not showTags: 0 else: dp(w))
  if area.w < dp(640):
    ws[5] = dp(130)
    ws[9] = 0
    ws[6] = max(dp(80), area.w - (ws[0] + ws[1] + ws[2] + ws[3] + ws[4] + ws[5] + ws[7] + ws[8]))
  # the header
  var x = inner.x
  let titles = ["", "", "!", nfPaperclip, nfFlag, "From", "Subject", "Tags", "Received", "Size"]
  pushClip(rect(inner.x, inner.y, inner.w, hh))
  for k, w in ws:
    if w == 0: continue
    let c = rect(x, inner.y, w, hh)
    fill(c, ui.theme.face)
    raised(c, 1)
    if titles[k].len > 0:
      let tx = if k in 2 .. 4: x + (w - textWidth(titles[k])) div 2 else: x + dp(5)
      text(tx, inner.y + dp(3), titles[k], ui.theme.text)
    x += w
  fill(rect(x, inner.y, inner.x + inner.w - x, hh), ui.theme.face)
  popClip()
  if rows.len == 0:
    let msg = if query.len > 0: "Nothing found here. Press Enter in the search box to ask the server too."
              elif accountsC.len == 0: "No account yet: File, Add Account."
              else: "There are no messages here."
    text(area.x + dp(12), area.y + dp(12), msg, ui.theme.gray)
    return
  pushClip(area)
  let first = max(0, listScroll div rh)
  let last = min(rows.high, (listScroll + area.h) div rh + 1)
  for i in first .. last:
    let row = rows[i]
    let y = area.y + i * rh - listScroll
    let full = rect(area.x, y, area.w, rh)
    if row.group.len > 0:
      fill(full, ui.theme.face)
      text(area.x + dp(26), y + dp(3), row.group, rgb(0, 0, 128), style(bold = true))
      hline(area.x, y + rh - 1, area.w, ui.theme.line)
      continue
    let c = convs[row.conv]
    let m = if row.msg < 0: c.msgs[0] else: c.msgs[row.msg]
    let dx = swipeInput(i, full)
    var rr = full
    if dx != 0:
      swipeUnder(full, dx)
      rr.x += dx
    let rhit = interact(idOf("row" & $i & ":" & c.key), rr, focusable = false)
    if rhit.clicked:
      if row.msg < 0 and ui.mx < area.x + ws[0] and c.msgs.len > 1:
        if c.key in expanded: expanded.excl c.key else: expanded.incl c.key
        changed()
      selectRow(i)
      ui.focus = listId
      if isCompact(): phone = phRead
    if ui.rpressed and mouseIn(rr) and canInput():
      selectRow(i)
      openPopupMenu("rowmenu", ui.mx, ui.my)
    let selected = i == selRow
    let unread = if row.msg < 0: c.unread > 0 else: m.unread
    let bg = if selected: ui.theme.select
             elif c.pinned: rgb(255, 255, 225)
             elif row.msg >= 0: rgb(246, 246, 246)
             else: ui.theme.field
    fill(rr, bg)
    let fg = if selected: ui.theme.selectText else: ui.theme.fieldText
    let dim = if selected: ui.theme.selectText else: ui.theme.gray
    let st = style(bold = unread)
    let ty = y + (rh - lh) div 2
    x = rr.x
    if row.msg < 0 and c.msgs.len > 1: plusBox(x + dp(5), y + (rh - dp(9)) div 2, c.key in expanded)
    x += ws[0]
    let env = if m.mine and row.msg >= 0: pixelIcon(pxBack)
              elif unread: pixelIcon(pxMail)
              else: glyphIcon(nfEnvelope, dim)
    image(x + (ws[1] - env.w) div 2, y + (rh - env.h) div 2, env)
    x += ws[1]
    if row.msg < 0:
      if c.important: text(x + dp(6), ty, nfExclamation, rgb(200, 0, 0))
      elif c.pinned: image(x + 1, y + (rh - 16) div 2, pixelIcon(pxPin))
    x += ws[2]
    if (row.msg < 0 and c.hasAtt) or m.hasAtt: text(x + dp(4), ty, nfPaperclip, fg)
    x += ws[3]
    if (row.msg < 0 and c.flagged) or (row.msg >= 0 and m.flagged):
      text(x + dp(4), ty, nfFlag, rgb(200, 0, 0))
    x += ws[4]
    if row.msg < 0:
      let w = if c.msgs.len > 1: c.people else: who(m)
      text(x + dp(4), ty, fit(w, ws[5] - dp(8), st), fg, st)
    else:
      let tx = area.x + dp(9)
      vline(tx, y, (if row.msg == c.msgs.high: rh div 2 else: rh), ui.theme.gray)
      hline(tx, y + rh div 2, dp(10), ui.theme.gray)
      text(x + dp(18), ty, fit(who(m), ws[5] - dp(22), st), fg, st)
    x += ws[5]
    if row.msg < 0:
      let s = fit(c.subject, ws[6] - dp(44), st)
      text(x + dp(4), ty, s, fg, st)
      if c.msgs.len > 1:
        text(x + dp(8) + textWidth(s, st), ty, "(" & $c.msgs.len & ")",
             if selected: fg else: rgb(0, 0, 200), st)
    else:
      let f = folderOf(m.folder)
      let s = (if f.role in ["sent", "drafts", "trash"]: "[" & f.name & "]  " else: "") & m.snippet
      text(x + dp(4), ty, fit(s, ws[6] - dp(8)), dim)
    x += ws[6]
    if ws[7] > 0 and row.msg < 0: discard tagsAt(x + dp(3), ty, ws[7] - dp(6), c.tags)
    x += ws[7]
    text(x + dp(4), ty, shortDate(m.date), fg, st)
    x += ws[8]
    if ws[9] > 0:
      let sz = sizeText(if row.msg < 0: c.size else: m.size)
      text(x + ws[9] - textWidth(sz, st) - dp(6), ty, sz, fg, st)
    hline(rr.x, y + rh - 1, rr.w, rgb(232, 232, 232))
  popClip()
  # keys
  if canInput() and not ui.keyUsed and (ui.focus == listId or ui.focus == 0):
    if ui.key == KeyDown: moveRow(1); ui.keyUsed = true
    elif ui.key == KeyUp: moveRow(-1); ui.keyUsed = true
    elif ui.key in {KeyRight, KeyLeft} and selRow >= 0:
      let c = selectedConv()
      if c != nil and c.msgs.len > 1:
        if ui.key == KeyRight: expanded.incl c.key else: expanded.excl c.key
        changed()
      ui.keyUsed = true
    if selRow >= 0 and (ui.key in {KeyDown, KeyUp}):
      scrollShow(listId, listScroll, selRow * rh, selRow * rh + rh, area.h, hi)
  popupMenu("rowmenu"):
    let ms = selectedMsgs()
    if menuItem("&Reply", "Ctrl+R"): doReply("reply")
    if menuItem("Reply &All", "Ctrl+Shift+R"): doReply("replyAll")
    if menuItem("&Forward", "Ctrl+F"): doReply("forward")
    menuSeparator()
    if menuItem("Mark as &Read"): markRead(ms)
    if menuItem("Mark as &Unread"): markRead(ms, true)
    if menuItem("F&lag", checked = ms.anyIt(it.flagged)): toggleFlag(ms)
    if menuItem("&Pin", checked = ms.anyIt(it.pinned)): pinMsgs(ms)
    if menuItem("S&nooze..."): snoozeOpen = true
    if menuItem("&Tags..."): tagMenuOpen = true
    menuSeparator()
    if menuItem("&Move to Folder..."): moveOpen = true
    if menuItem("&Archive"): archiveMsgs(ms)
    if menuItem("&Delete"): deleteMsgs(ms)
    if menuItem("Mark as &Junk"): moveMsgs(ms, "junk")

# ---- the reading pane ------------------------------------------------------------------

proc remoteImages(html: string): int =
  ## How many pictures from the web a message has (shown only when allowed).
  var i = 0
  while true:
    let k = html.find("<img", i)
    if k < 0: break
    let e = html.find('>', k)
    if e < 0: break
    let tag = html[k .. e].toLowerAscii
    if "src=\"http" in tag or "src='http" in tag or "src=http" in tag: inc result
    i = e

proc attachmentsRow(m: Msg) =
  let atts = store0.attachments(m.id)
  var files: seq[Att]
  for a in atts:
    if not a.inline: files.add a
  if files.len == 0: return
  row:
    for a in files:
      let px = if a.mime.startsWith("image/"): pxImage
               elif a.mime.contains("pdf"): pxPdf
               elif a.mime.contains("zip") or a.mime.contains("compressed"): pxArchive
               elif a.name.endsWith(".apk") or a.name.endsWith(".exe"): pxApp
               else: pxFile
      if button(fit(a.name, dp(220)) & "  (" & sizeText(a.size) & ")", px):
        attMenuId = a.id
        openPopupMenu("attmenu", ui.mx, ui.my)
  popupMenu("attmenu"):
    if menuItem("&Open"):
      openAttAfter = attMenuId
      if store0.attachmentData(attMenuId).len == 0:
        link.cmds.send(SyncCmd(kind: scAttachment, id: attMenuId))
        status = "Downloading the attachment..."
    if menuItem("&Save As..."):
      saveAttId = attMenuId
      let r = store0.one("SELECT name FROM atts WHERE id = ?", attMenuId)
      saveAttPath = getHomeDir() / (if r.len > 0: r[0].str else: "attachment")
      saveAttOpen = true
      if store0.attachmentData(attMenuId).len == 0:
        link.cmds.send(SyncCmd(kind: scAttachment, id: attMenuId))

proc openAttachment(id: int) =
  let data = store0.attachmentData(id)
  if data.len == 0: return
  let r = store0.one("SELECT name FROM atts WHERE id = ?", id)
  let name = if r.len > 0: r[0].str else: "attachment"
  let p = getTempDir() / "retro-mail" / name.multiReplace(("/", "_"), ("\\", "_"))
  try:
    createDir(p.parentDir)
    writeFile(p, data)
    if not openFile(p): status = "No program here opens " & name
  except CatchableError as e: status = e.msg

proc mailHeader(m: Msg; collapsed: bool): bool =
  ## A message's header in the conversation; true when clicked.
  let lh = lineHeight()
  let h = if collapsed: lh + dp(12) else: 2 * lh + dp(14)
  let r = place(available(), h, fill = true)
  let hit = interact(idOf("mh" & $m.id), r, focusable = false)
  fill(r, if collapsed: (if hit.hover: rgb(236, 236, 244) else: rgb(244, 244, 244)) else: ui.theme.field)
  box(r, rgb(210, 210, 210))
  let d = if collapsed: lh + dp(4) else: 2 * lh
  initials(r.x + dp(8), r.y + (h - d) div 2, d, (if m.mine and m.fromName.len > 0: m.fromName else: who(m)))
  let x = r.x + d + dp(18)
  let tw = textWidth(shortDate(m.date))
  text(r.x + r.w - tw - dp(10), r.y + dp(6), shortDate(m.date), ui.theme.gray)
  let st = style(bold = true)
  if collapsed:
    let nameW = textWidth(who(m), st)
    text(x, r.y + dp(6), who(m), ui.theme.text, style(bold = m.unread))
    text(x + nameW + dp(12), r.y + dp(6), fit(m.snippet, r.w - nameW - tw - d - dp(60)), ui.theme.gray)
  else:
    let from0 = if m.fromName.len > 0: m.fromName & " <" & m.fromEmail & ">" else: m.fromEmail
    text(x, r.y + dp(6), fit(from0, r.w - d - tw - dp(50), st), ui.theme.text, st)
    var line = "To: " & m.toList
    if m.ccList.len > 0: line.add ";  Cc: " & m.ccList
    text(x, r.y + dp(8) + lh, fit(line, r.w - d - dp(40)), ui.theme.gray)
  hit.clicked

proc messageBody(m: Msg; fill: bool) =
  case m.bodyState
  of 2:
    let pics = remoteImages(m.html)
    if pics > 0 and m.id notin allowPictures and prefInt("pictures", 0) != 1:
      case banner("Pictures from the web are hidden in this message (" & $pics &
                  "), so the sender cannot see when you read it.", bkInfo,
                  ["Show pictures", "Always for everyone"], closable = false)
      of 1: allowPictures.incl m.id
      of 2:
        prefs.put("pictures", 1)
        savePrefs()
      else: discard
    attachmentsRow(m)
    let ev = if fill: htmlView(m.html, height = remainingH() - CtrlH - dp(12),
                               key = "msg" & $m.id, images = imagesFor(m))
             else: htmlBlock(m.html, images = imagesFor(m))
    if ev.link.len > 0:
      if ev.link.startsWith("mailto:"):
        openCompose("new", to = ev.link[7 .. ^1].split('?')[0])
      else: discard openUrl(ev.link)
  of 3:
    paragraph "This message could not be downloaded. It may have been deleted or moved."
  else:
    row:
      spinner()
      label "Downloading the message...", color = ui.theme.gray
    paragraph m.snippet

proc quickReplies(c: Conv): seq[string] =
  let s = (c.subject & " " & (if c.msgs.len > 0: c.msgs[0].snippet else: "")).toLowerAscii
  if "?" in s: @["Yes, that works", "No, sorry", "Let me check"]
  elif "thank" in s: @["You're welcome!", "Any time", "Glad to help"]
  elif "invoice" in s or "payment" in s: @["Received, thank you", "I'll check it now"]
  else: @["Thanks!", "Got it", "Sounds good"]

proc quickReply(text: string) =
  let ms = selectedMsgs()
  if ms.len == 0: return
  openCompose("reply", store0.message(ms[0].id))
  richInsert(composeDoc, text)

proc readingPane() =
  loadOpen()
  let c = selectedConv()
  if c == nil or openMsgs.len == 0:
    let r = place(available(), remainingH(), fill = true)
    fill(r, ui.theme.field)
    sunken(r)
    let msg = if convs.len == 0: "" else: "Select a message to read it here."
    text(r.x + (r.w - textWidth(msg)) div 2, r.y + r.h div 3, msg, ui.theme.gray)
    return
  let lh = lineHeight()
  # OE4's gray header: the subject and the thread's tags, with the helpers
  let r = place(available(), 2 * lh + dp(14), fill = true)
  fill(r, ui.theme.face)
  hline(r.x, r.y + r.h - 1, r.w, ui.theme.shadow)
  let bold = style(bold = true)
  let compact = r.w < dp(620)
  text(r.x + dp(8), r.y + dp(5), "Subject:", ui.theme.text, bold)
  text(r.x + dp(70), r.y + dp(5), fit(c.subject, r.w - dp(80) - (if compact: 0 else: dp(330))),
       ui.theme.text)
  text(r.x + dp(8), r.y + dp(7) + lh, "Thread:", ui.theme.text, bold)
  let info = $openMsgs.len & (if openMsgs.len == 1: " message" else: " messages") & "  |  " &
             fit(c.people, dp(260))
  text(r.x + dp(70), r.y + dp(7) + lh, info, ui.theme.text)
  discard tagsAt(r.x + dp(84) + textWidth(info), r.y + dp(7) + lh, dp(240), c.tags)
  if not compact:
    pushFrame(rect(r.x + r.w - dp(326), r.y + (r.h - CtrlH) div 2, dp(318), 0))
    row:
      if button("Tags", nfTags): tagMenuOpen = true
      if button("Snooze", pxClock): snoozeOpen = true
      if button(if c.flagged: "Unflag" else: "Flag", nfFlag): toggleFlag(selectedMsgs())
    discard popFrame()
  # mark it read after a moment (as OE did)
  let delay = float(prefInt("readDelay", 2))
  if c.unread > 0 and epochTime() - openShown >= delay:
    markRead(c.msgs)
  elif c.unread > 0: wakeIn(500)
  let single = openMsgs.len == 1
  if single:
    let m = openMsgs[0]
    discard mailHeader(m, false)
    messageBody(m, true)
  else:
    panel(remainingH() - CtrlH - dp(12)):
      for m in openMsgs:
        let open = m.id in openExpanded
        if mailHeader(m, not open):
          if open: openExpanded.excl m.id
          else:
            openExpanded.incl m.id
            if m.bodyState == 0:
              store0.setBodyState(m.id, 1)
              link.cmds.send(SyncCmd(kind: scBody, id: m.id))
        if open:
          messageBody(m, false)
          space()
  row:
    if r.w > dp(560):
      for s in quickReplies(c[]):
        if button(s): quickReply(s)
      space available() - 3 * (dp(90) + Gap) + Gap
    if button("Reply", pxBack, w = dp(90)): doReply("reply")
    if button("Reply all", pxUndo, w = dp(90)): doReply("replyAll")
    if button("Forward", pxForward, w = dp(90)): doReply("forward")

# ---- tags, snooze and move -------------------------------------------------------------

proc tagMenu() =
  if not tagMenuOpen: return
  let ms = selectedMsgs()
  if ms.len == 0:
    tagMenuOpen = false
    return
  let lh = lineHeight()
  let ih = lh + dp(10)
  let w = dp(240)
  let n = tagsC.len + 3
  var r = rect(tagMenuAt.x, tagMenuAt.y + tagMenuAt.h, w, n * ih + dp(16))
  if r.x + r.w > ui.w: r.x = ui.w - r.w - dp(4)
  if r.y + r.h > ui.h: r.y = max(0, ui.h - r.h - dp(4))
  ui.overlayNow = r
  fill(r, ui.theme.face)
  box(r, ui.theme.frame)
  raised(inset(r, 1), 1)
  var y = r.y + dp(5)
  var cur: seq[string]
  for m in ms:
    for t in m.tags:
      if t notin cur: cur.add t
  for k, t in tagsC:
    let it = rect(r.x + dp(3), y, w - dp(6), ih)
    let hit = interact(idOf("tagitem" & t.name), it, focusable = false)
    if hit.hover: fill(it, ui.theme.select)
    let fg = if hit.hover: ui.theme.selectText else: ui.theme.text
    let on = cur.anyIt(it.toLowerAscii == t.name.toLowerAscii)
    if on: text(it.x + dp(6), y + dp(5), nfCheck, fg)
    fill(rect(it.x + dp(26), y + dp(5), dp(14), dp(14)), tagColor(t.name))
    box(rect(it.x + dp(26), y + dp(5), dp(14), dp(14)), ui.theme.frame)
    text(it.x + dp(48), y + dp(5), fit(t.name, it.w - dp(110)), fg)
    if k < 10:
      let sc = "Ctrl+" & $((k + 1) mod 10)
      text(it.x + it.w - textWidth(sc) - dp(8), y + dp(5), sc, fg)
    if hit.clicked:
      setMsgTags(ms, t.name, not on)
      tagMenuOpen = false
    y += ih
  hline(r.x + dp(4), y + dp(3), w - dp(8), ui.theme.shadow)
  hline(r.x + dp(4), y + dp(4), w - dp(8), ui.theme.light)
  y += dp(8)
  for (label, what) in [("New tag...", 1), ("Clear all tags", 2), ("All tags (Options)...", 3)]:
    let it = rect(r.x + dp(3), y, w - dp(6), ih)
    let hit = interact(idOf("tagcmd" & label), it, focusable = false)
    if hit.hover: fill(it, ui.theme.select)
    text(r.x + dp(51), y + dp(5), label, if hit.hover: ui.theme.selectText else: ui.theme.text)
    if hit.clicked:
      tagMenuOpen = false
      case what
      of 1: newTagOpen = true
      of 2: clearTags(ms)
      else:
        optTab = 4
        optOpen = true
    y += ih
  if canInput() and ui.pressed and not mouseIn(r) and not mouseIn(tagMenuAt):
    tagMenuOpen = false
  if keyHit(KeyEsc): tagMenuOpen = false

proc smallDialogs() =
  let ms = selectedMsgs()
  dialog snoozeOpen, "Snooze", dp(300):
    label "Hide it until:"
    for (label, t) in [("Later today", laterToday()), ("Tomorrow morning", tomorrowAt(8)),
                       ("This weekend", nextMonday() - 2 * 86400), ("Next week", nextMonday())]:
      if button(label & "    " & fromUnixFloat(t).local.format("ddd HH:mm"), w = dp(270)):
        snoozeMsgs(ms, t)
        snoozeOpen = false
    if button("Cancel", w = dp(270)): snoozeOpen = false
  dialog moveOpen, "Move to Folder", dp(360):
    if ms.len == 0:
      moveOpen = false
    else:
      let fs = foldersC.getOrDefault(ms[0].account)
      var names: seq[string]
      for f in fs: names.add f.name
      label "Move the selected messages to:"
      listbox(names, moveSel, rows = 10)
      row:
        space available() - 2 * (dp(80) + Gap) + Gap
        if button("OK", isDefault = true, w = dp(80), enabled = moveSel in 0 ..< fs.len):
          moveMsgs(ms, "", fs[moveSel].id)
          moveOpen = false
        if button("Cancel", w = dp(80)): moveOpen = false
  dialog newTagOpen, "New Tag", dp(340):
    form dp(60):
      field "&Name:": edit newTagName
      field "&Color:":
        var names: seq[string]
        for (n, _) in tagPalette: names.add n
        combo(names, newTagColor)
    row:
      space available() - 2 * (dp(80) + Gap) + Gap
      if button("OK", isDefault = true, w = dp(80), enabled = newTagName.strip.len > 0):
        let name = newTagName.strip
        addTag(name, tagPalette[newTagColor][1])
        if ms.len > 0: setMsgTags(ms, name, true)
        newTagName = ""
        newTagOpen = false
      if button("Cancel", w = dp(80)): newTagOpen = false
  if fileDialog(saveAttOpen, saveAttPath, fmSave, ["All Files (*.*)"]):
    let data = store0.attachmentData(saveAttId)
    if data.len == 0: status = "The attachment is still downloading: try again in a moment"
    else:
      try:
        writeFile(saveAttPath, data)
        status = "Saved " & saveAttPath
      except CatchableError as e: status = e.msg

proc mailKeys() =
  if not canInput() or ui.keyUsed: return
  let ctrl = CtrlPressed in ui.mods
  let shift = ShiftPressed in ui.mods
  let ms = selectedMsgs()
  if ctrl and ui.key == KeyN: openCompose("new"); ui.keyUsed = true
  elif ctrl and shift and ui.key == KeyR: doReply("replyAll"); ui.keyUsed = true
  elif ctrl and ui.key == KeyR: doReply("reply"); ui.keyUsed = true
  elif ctrl and ui.key == KeyF: doReply("forward"); ui.keyUsed = true
  elif ctrl and ui.key == KeyQ: markRead(ms); ui.keyUsed = true
  elif ctrl and ui.key == KeyU: markRead(ms, true); ui.keyUsed = true
  elif ctrl and ui.key == KeyT: tagMenuOpen = true; ui.keyUsed = true
  elif ctrl and ui.key == KeyE: ui.textFocusWanted = true; ui.keyUsed = true
  elif ctrl and ui.key in {Key1, Key2, Key3, Key4, Key5}:
    view = [vMail, vCalendar, vPeople, vTodo, vNotes][ord(ui.key) - ord(Key1)]
    ui.keyUsed = true
  elif ui.key == KeyF5: link.cmds.send(SyncCmd(kind: scSyncNow)); ui.keyUsed = true
  elif ui.focus == 0 or ui.focus == idOf("maillist"):
    if ui.key == KeyDelete and ms.len > 0: deleteMsgs(ms); ui.keyUsed = true
    elif ui.key == KeyBackspace and ms.len > 0: archiveMsgs(ms); ui.keyUsed = true
    elif ui.key == KeyInsert and ms.len > 0: toggleFlag(ms); ui.keyUsed = true
    elif ui.key == KeyEnter and isCompact(): phone = phRead; ui.keyUsed = true
