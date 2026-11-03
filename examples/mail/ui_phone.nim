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
  if hit.clicked and dx == 0:
    selectRow(i)
    phone = phRead
  if longPressed() and mouseIn(c2) and canInput():
    selectRow(i)
    openPopupMenu("rowmenu", ui.mx, ui.my)
  let selected = i == selRow
  fill(c2, if c.pinned: rgb(255, 255, 225) else: ui.theme.field)
  let unread = c.unread > 0
  if unread: fill(rect(c2.x, c2.y, dp(4), c2.h), rgb(0, 0, 200))
  let fg = ui.theme.fieldText
  let dim = ui.theme.gray
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
  if not swiping: scrollPan(id, listScroll, hi, r)
  scrollTick(id, listScroll, hi)
  pushClip(r)
  var y = r.y - listScroll
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
    phoneList()
    phoneBottom()
