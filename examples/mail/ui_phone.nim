# Retro Mail on a phone: one screen at a time -- folders, the list (swipe
# a message sideways), the conversation, writing -- with the Outlook bar
# at the bottom. Included by examples/mail.nim.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

proc phoneBottom() =
  let barH = dp(56)
  let r = place(available(), barH, fill = true)
  fill(r, ui.theme.shadow)
  let items = [(vMail, pxMail, "Mail"), (vCalendar, pxCalendar, "Calendar"),
               (vPeople, pxUser, "People"), (vTodo, pxCheck, "To Do"), (vNotes, pxNote, "Notes")]
  let w = r.w div items.len
  for k, (v, px, name) in items:
    let cell = rect(r.x + k * w, r.y, w, r.h)
    let on = view == v or (v == vMail and view == vStart)
    let hit = interact(idOf("pbar" & name), cell, focusable = false)
    if hit.clicked:
      view = v
      if v == vMail: phone = phList
    if on: fill(inset(cell, 3), ui.theme.face)
    let ic = pixelIcon(px, big = true)
    image(cell.x + (cell.w - ic.w) div 2, cell.y + dp(3), ic)
    text(cell.x + (cell.w - textWidth(name)) div 2, cell.y + dp(37), name,
         if on: ui.theme.text else: rgb(255, 255, 255))

proc phoneRow(i: int; c: Conv; rr0: Rect) =
  let lh = lineHeight()
  let m = c.msgs[0]
  let dx = swipeInput(i, rr0)
  var c2 = rr0
  if dx != 0:
    swipeUnder(rr0, dx)
    c2.x += dx
  pushClip(rr0)
  let hit = interact(idOf("prow" & c.key), c2, focusable = false)
  let key = rowKey(i)
  if longPressed() and mouseIn(c2) and canInput():
    # a long press: choosing several (as phones do), this one first
    if not phoneChoosing:
      phoneChoosing = true
      multiSel.clear()
    multiSel.incl key
    discard vibrate(20)
    ui.pressUsed = true
  elif hit.clicked and dx == 0:
    if phoneChoosing:
      if key in multiSel: multiSel.excl key else: multiSel.incl key
      if multiSel.len == 0: phoneChoosing = false
    else:
      selectRow(i)
      phone = phRead
  let chosen = phoneChoosing and key in multiSel
  let selected = i == selRow and not phoneChoosing
  fill(c2, if chosen: rgb(204, 224, 255) elif c.pinned: rgb(255, 255, 225) else: ui.theme.field)
  let unread = c.unread > 0
  if unread: fill(rect(c2.x, c2.y, dp(4), c2.h), rgb(0, 0, 200))
  let fg = ui.theme.fieldText
  let dim = ui.theme.gray
  if phoneChoosing:
    # its check box, where the envelope was
    let b = rect(c2.x + dp(8), c2.y + dp(8), dp(18), dp(18))
    fill(b, ui.theme.field)
    box(b, ui.theme.text)
    if chosen: text(b.x + dp(3), b.y + (b.h - lh) div 2, nfCheck, rgb(0, 0, 160))
  else:
    let ic = if unread: pixelIcon(pxMail) else: glyphIcon(nfEnvelope, dim)
    image(c2.x + dp(10), c2.y + dp(8), ic)
  let x = c2.x + dp(34)
  let st = style(bold = unread)
  let who0 = if c.msgs.len > 1: c.people else: who(m)
  let tw = textWidth(shortDate(m.date))
  var nx = x
  let whoFit = fit(who0, c2.w - dp(34) - tw - dp(54), st)
  text(nx, c2.y + dp(6), whoFit, fg, st)
  nx += textWidth(whoFit, st) + dp(6)
  if c.msgs.len > 1:
    let n = $c.msgs.len
    let bw = textWidth(n, style(bold = true, size = 0.85)) + dp(8)
    roundRect(rect(nx, c2.y + dp(7), bw, lh - dp(1)), float(dp(6)), ui.theme.shadow)
    text(nx + dp(4), c2.y + dp(7), n, rgb(255, 255, 255), style(bold = true, size = 0.85))
  text(c2.x + c2.w - tw - dp(10), c2.y + dp(6), shortDate(m.date), dim)
  var marks = ""
  if c.hasAtt: marks.add nfPaperclip
  if c.flagged: marks.add " " & nfFlag
  if marks.len > 0:
    text(c2.x + c2.w - textWidth(marks) - dp(10), c2.y + dp(8) + lh, marks,
         if c.flagged: rgb(200, 0, 0) else: dim)
  if c.pinned: image(c2.x + c2.w - dp(28), c2.y + dp(8) + 2 * lh, pixelIcon(pxPin))
  text(x, c2.y + dp(8) + lh, fit(c.subject, c2.w - dp(90), st), fg, st)
  let pw = tagsAt(x, c2.y + dp(11) + 2 * lh, dp(170), c.tags)
  text(x + pw + dp(2), c2.y + dp(10) + 2 * lh, fit(m.snippet, c2.w - pw - dp(76)), dim)
  hline(c2.x, c2.y + c2.h - 1, c2.w, ui.theme.line)
  if selected: box(c2, ui.theme.select)
  popClip()

proc phoneList() =
  let lh = lineHeight()
  let rh = 3 * lh + dp(18)
  let gh = lh + dp(8)
  let r = place(available(), remainingH() - dp(56) - Gap, fill = true)
  fill(r, ui.theme.field)
  let id = idOf("phonelist")
  var total = 0
  for row in rows:
    if row.msg >= 0: continue
    total += (if row.group.len > 0: gh else: rh)
  let hi = max(0, total - r.h)
  scrollWheel(id, listScroll, hi, r, rh)
  # pull down from the top: send and receive
  if canInput() and ui.pressed and mouseIn(r) and listScroll <= 0:
    pullFrom = ui.my
  if pullFrom >= 0 and ui.mouseDown and not swiping:
    pullBy = max(0, ui.my - pullFrom)
    if pullBy > dp(70) and not pullReady:
      pullReady = true
      discard vibrate(15)
    elif pullBy <= dp(70): pullReady = false
    ui.redraw = true
  elif pullFrom >= 0:
    if pullReady:
      link.cmds.send(SyncCmd(kind: scSyncNow))
      syncText = "Checking for new mail..."
    pullFrom = -1
    pullBy = 0
    pullReady = false
  if not swiping and pullBy < dp(8): scrollPan(id, listScroll, hi, r)
  scrollTick(id, listScroll, hi)
  pushClip(r)
  if pullBy > 0:
    let ph = min(pullBy, dp(90))
    fill(rect(r.x, r.y, r.w, ph), ui.theme.face)
    let t = if pullReady: "Let go to check for new mail" else: "Pull down to check for new mail"
    if ph > lh: text(r.x + (r.w - textWidth(t)) div 2, r.y + ph - lh - dp(6), t, ui.theme.text)
  var y = r.y - listScroll + min(pullBy, dp(90))
  for i, row in rows:
    if row.msg >= 0: continue
    let h = if row.group.len > 0: gh else: rh
    if y + h >= r.y and y < r.y + r.h:
      if row.group.len > 0:
        let g = rect(r.x, y, r.w, gh)
        fill(g, ui.theme.face)
        text(g.x + dp(10), g.y + dp(4), row.group, rgb(0, 0, 128), style(bold = true))
      else:
        phoneRow(i, convs[row.conv], rect(r.x, y, r.w, h))
    y += h
  if rows.len == 0:
    text(r.x + dp(16), r.y + dp(16), (if accountsC.len == 0: "No account yet." else: "No messages here."),
         ui.theme.gray)
  popClip()
  # the round Compose button, over the list (not while choosing)
  if not phoneChoosing and accountsC.len > 0:
    let d = dp(56)
    let fab = rect(r.x + r.w - d - dp(16), r.y + r.h - d - dp(16), d, d)
    let hit = interact(idOf("composefab"), fab, focusable = false)
    disc(float(fab.x + d div 2 + 2), float(fab.y + d div 2 + 3), float(d) / 2, ui.theme.shadow)
    disc(float(fab.x + d div 2), float(fab.y + d div 2), float(d) / 2,
         if hit.down: rgb(0, 60, 150) else: rgb(0, 90, 200))
    let ic = pixelIcon(pxMail, big = true)
    image(fab.x + (d - ic.w) div 2, fab.y + (d - ic.h) div 2, ic)
    if hit.clicked: openCompose("new")

proc phoneChooseBar() =
  ## While choosing several: what to do with them, in place of the Outlook bar.
  let barH = dp(56)
  let r = place(available(), barH, fill = true)
  fill(r, rgb(0, 60, 150))
  let ms = selectedMsgs()
  let items = [(pxArchive, "Archive"), (pxDelete, "Delete"), (nfEnvelope, "Read"),
               (nfFlag, "Flag"), (pxFolder, "Move"), (nfTags, "Tags"), (nfTimes, "Cancel")]
  let w = r.w div items.len
  for k, (px, name) in items:
    let cell = rect(r.x + k * w, r.y, w, r.h)
    let hit = interact(idOf("pchoose" & name), cell, focusable = false)
    if hit.down: fill(inset(cell, 3), rgb(0, 90, 200))
    if px.startsWith("\u{10F}") or px.len == 4 and ord(px[0]) == 0xF4:
      let ic = pixelIcon(px)
      image(cell.x + (cell.w - ic.w) div 2, cell.y + dp(10), ic)
    else:
      text(cell.x + (cell.w - textWidth(px)) div 2, cell.y + dp(10), px, rgb(255, 255, 255))
    text(cell.x + (cell.w - textWidth(name)) div 2, cell.y + dp(34), name, rgb(255, 255, 255))
    if hit.clicked:
      case name
      of "Archive": archiveMsgs(ms)
      of "Delete": deleteMsgs(ms)
      of "Read": markRead(ms, ms.allIt(not it.unread))
      of "Flag": toggleFlag(ms)
      of "Move":
        moveOpen = true
        continue
      of "Tags":
        tagMenuAt = rect(cell.x, cell.y - dp(300), cell.w, 0)
        tagMenuOpen = true
        continue
      else: discard
      phoneChoosing = false
      clearMulti()

proc phoneFolders() =
  toolbar:
    if toolButton(pxBack, "Back"): phone = phList
    if toolButton(pxRefresh, "Send and receive"): link.cmds.send(SyncCmd(kind: scSyncNow))
    if toolButton(pxSettings, "Options"): optOpen = true
    if toolButton(pxAdd, "Add an account"): openWizard()
  folderBar(appName, "")
  let before = treeSel
  folderTree()
  if treeSel != before and treeSel != "start" and not treeSel.startsWith("acct") and
     treeSel notin ["fav", "tags"]:
    phone = phList

proc phoneRead() =
  let c = selectedConv()
  toolbar:
    if toolButton(pxBack, "Back to the list"): phone = phList
    if c != nil:
      let ms = c.msgs.filterIt(it.id notin mates)
      toolSeparator()
      if toolButton(pxArchive, "Archive"): archiveMsgs(ms); phone = phList
      if toolButton(pxDelete, "Delete"): deleteMsgs(ms); phone = phList
      if toolButton(nfFlag, "Flag", down = c.flagged): toggleFlag(ms)
      if toolButton(nfTags, "Tags"):
        tagMenuAt = ui.lastRect
        tagMenuOpen = true
      if toolButton(pxClock, "Snooze"): snoozeOpen = true
      if toolButton(pxPin, "Pin", down = c.pinned): pinMsgs(ms)
  if c == nil:
    phone = phList
    return
  # a swipe sideways over the message: the next one (left) or the one before (right)
  let area = rect(0, ui.barY, ui.w, ui.h - ui.barY)
  if canInput() and ui.pressed and mouseIn(area):
    readSwipeX = ui.mx
    readSwipeY = ui.my
    readSwipeT = epochTime()
  if readSwipeX >= 0 and not ui.mouseDown:
    let dx = ui.mx - readSwipeX
    let dy = ui.my - readSwipeY
    if abs(dx) > dp(90) and abs(dx) > 2 * abs(dy) and epochTime() - readSwipeT < 0.6 and
       readZoom <= 1.0:
      clearMulti()
      moveRow(if dx < 0: 1 else: -1)
      discard vibrate(10)
    readSwipeX = -1
  readingPane()

proc phoneUi() =
  if mouseBack() or (keyHit(KeyEsc) and not composing and ui.popup == 0):
    case phone
    of phRead, phFolders: phone = phList
    of phCompose: cAskClose = true
    of phList:
      if view != vMail: view = vMail
  if composing:
    phone = phCompose
    composeWindow()
    return
  if view in [vCalendar, vPeople, vTodo, vNotes]:
    statusbar(syncText)
    folderBar(($view)[1 .. ^1], "")
    pane(remainingH() - dp(56) - Gap):
      case view
      of vCalendar: calendarView()
      of vPeople: peopleView()
      of vTodo: todoView()
      else: notesView()
    phoneBottom()
    return
  if view == vStart and accountsC.len == 0:
    folderBar(appName, "")
    pane(remainingH() - dp(56) - Gap):
      startPage()
    phoneBottom()
    return
  case phone
  of phFolders: phoneFolders()
  of phRead: phoneRead()
  else:
    toolbar:
      if toolButton(pxTree, "Folders"): phone = phFolders
      if toolButton(pxMail, "New message"): openCompose("new")
      if toolButton(pxRefresh, "Send and receive"): link.cmds.send(SyncCmd(kind: scSyncNow))
      if toolButton(pxSettings, "Options"): optOpen = true
    statusbar(if syncText.len > 0: syncText elif status.len > 0: status else: $unreadAll() & " unread")
    folderBar(placeTitle(), "", if place.kind == plTag: place.tag else: "")
    if isInboxPlace() and prefBool("focused", true) and query.len == 0:
      var t = focusTab
      row:
        discard tabStrip(["Focused", "Other"], t, closable = false, addButton = false)
      if t != focusTab:
        focusTab = t
        changed()
    if phoneChoosing and multiSel.len == 0: phoneChoosing = false
    phoneList()
    if phoneChoosing: phoneChooseBar() else: phoneBottom()
