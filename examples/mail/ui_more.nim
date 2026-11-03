# Retro Mail: what 1.0.2 adds around the list and the reading pane -- many
# messages selected at once, the message in a window of its own, Go to
# Folder, the command box, Quick Steps, Sweep, follow-up reminders, the
# preview of attachments. Included by examples/mail.nim.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

proc notifySystem(title, body: string)
proc addSenderRule(sender, action: string)

# ---- many selected -------------------------------------------------------------------------

proc multiPane() =
  ## The reading pane while several messages are selected: what can be done
  ## with them all, as the new Outlook shows it.
  let ms = selectedMsgs()
  let r = place(available(), remainingH(), fill = true)
  fill(r, ui.theme.field)
  sunken(r)
  pushFrame(rect(r.x + dp(24), r.y + dp(40), min(r.w - dp(48), dp(420)), 0))
  image(pixelIcon(pxMail, big = true))
  label $multiSel.len & " selected" & (if ms.len != multiSel.len: "  (" & $ms.len & " messages)" else: ""),
        bold = true
  space()
  let w = dp(150)
  row:
    if button("Delete", pxDelete, w = w): deleteMsgs(ms); clearMulti()
    if button("Archive", pxArchive, w = w): archiveMsgs(ms); clearMulti()
  row:
    if button("Mark as read", nfEnvelope, w = w): markRead(ms)
    if button("Mark as unread", pxMail, w = w):
      markRead(ms, true)
      readMarked = selKey
  row:
    if button("Flag", nfFlag, w = w): toggleFlag(ms)
    if button("Pin", pxPin, w = w): pinMsgs(ms)
  row:
    if button("Move to...", pxFolder, w = w): moveOpen = true
    if button("Tags...", nfTags, w = w):
      tagMenuAt = ui.lastRect
      tagMenuOpen = true
  space()
  if link("Clear the selection"): clearMulti()
  discard popFrame()

# ---- the message in a window of its own ------------------------------------------------------

proc readerWindow() =
  ## A double click: the message in its own window (as Outlook Express
  ## opened it), with Previous and Next.
  if not readerOpen: return
  loadOpen()
  let c = selectedConv()
  if c == nil or openMsgs.len == 0:
    readerOpen = false
    return
  var m = openMsgs[0]
  for x in openMsgs:
    if x.id == openFocus: m = x
  if m.bodyState == 0:
    store0.setBodyState(m.id, 1)
    link.cmds.send(SyncCmd(kind: scBody, id: m.id))
  let w = min(ui.w - dp(24), dp(980))
  dialog readerOpen, (if m.subject.len > 0: m.subject else: "(no subject)") & " - Message", w:
    row:
      if button("Reply", pxBack): readerOpen = false; doReply("reply")
      if button("Reply All", pxUndo): readerOpen = false; doReply("replyAll")
      if button("Forward", pxForward): readerOpen = false; doReply("forward")
      if button("Delete", pxDelete):
        deleteMsgs(@[m])
        readerOpen = false
      space(dp(16))
      if button("Previous", nfChevronUp, enabled = selRow > 0) or keyHit(KeyPageUp):
        clearMulti()
        moveRow(-1)
      if button("Next", nfChevronDown, enabled = selRow < rows.high) or keyHit(KeyPageDown):
        clearMulti()
        moveRow(1)
    discard mailHeader(m, false)
    let h = max(dp(240), ui.h - dp(260))
    case m.bodyState
    of 2:
      attachmentsRow(m)
      let ev = htmlView(readHtml(m), readZoom, height = h, key = "reader" & $m.id, images = imagesFor(m))
      if ev.link.len > 0:
        if ev.link.startsWith("mailto:"):
          readerOpen = false
          openCompose("new", to = ev.link[7 .. ^1].split('?')[0])
        else: discard openUrl(ev.link)
    else:
      row:
        spinner()
        label "Downloading the message...", color = ui.theme.gray
      space(h - CtrlH)
    row:
      space available() - dp(84)
      if button("Close", isDefault = true, w = dp(84)): readerOpen = false
  if c.unread > 0: markRead(c.msgs)

# ---- Go to Folder (Ctrl+Y) -------------------------------------------------------------------

var
  goFolderOpen = false
  goFolderText = ""
  goFolderSel = 0
  goFolderWas = false

proc goFolderDialog() =
  ## Ctrl+Y: any folder of any account, found by typing.
  if not goFolderOpen:
    goFolderWas = false
    return
  var names: seq[string]
  var ids: seq[int]
  let f = goFolderText.strip.toLowerAscii
  for a in accountsC:
    for fo in foldersC.getOrDefault(a.id):
      if f.len == 0 or f in fo.name.toLowerAscii:
        names.add fo.name & "    (" & a.email & ")"
        ids.add fo.id
  goFolderSel = clamp(goFolderSel, 0, max(0, ids.high))
  dialog goFolderOpen, "Go to Folder", dp(420):
    label "&Folder:"
    if not goFolderWas:
      goFolderWas = true
      goFolderText = ""
      ui.textFocusWanted = true
    if edit(goFolderText): goFolderSel = 0
    if keyHit(KeyDown): goFolderSel = min(ids.high, goFolderSel + 1)
    if keyHit(KeyUp): goFolderSel = max(0, goFolderSel - 1)
    let before = goFolderSel
    listbox(names, goFolderSel, rows = 10)
    let go = (ui.doubleClick and goFolderSel == before) or keyHit(KeyEnter)
    row:
      space available() - 2 * (dp(80) + Gap) + Gap
      if (button("OK", isDefault = true, w = dp(80), enabled = ids.len > 0) or go) and ids.len > 0:
        treeSel = "f:" & $ids[goFolderSel]
        goFolderOpen = false
      if button("Cancel", w = dp(80)): goFolderOpen = false

# ---- the command box (Alt+Q) ----------------------------------------------------------------

var
  cmdOpen = false
  cmdText = ""
  cmdSel = 0
  cmdWas = false

proc commands(): seq[tuple[name, keys: string]] =
  @[("New message", "Ctrl+N"), ("Reply", "Ctrl+R"), ("Reply all", "Ctrl+Shift+R"),
    ("Forward", "Ctrl+F"), ("Forward as attachment", ""), ("New event", ""), ("New meeting", ""),
    ("Delete", "Del"),
    ("Archive", "Backspace"), ("Undo", "Ctrl+Z"), ("Mark as read", "Ctrl+Q"),
    ("Mark as unread", "Ctrl+U"), ("Flag", "Insert"), ("Follow up tomorrow", ""),
    ("Pin", ""), ("Snooze", ""), ("Tags", "Ctrl+T"), ("Move to folder", "Ctrl+Shift+V"),
    ("Go to folder", "Ctrl+Y"), ("Sweep", ""), ("Quick steps", ""), ("Select all", "Ctrl+A"),
    ("Send and receive", "F5"), ("Search", "Ctrl+E"), ("Calendar", "Ctrl+2"),
    ("People", "Ctrl+3"), ("To do", "Ctrl+4"), ("Notes", "Ctrl+5"),
    ("Reading pane beside the list", ""), ("Reading pane below the list", ""),
    ("Reading pane off", ""), ("Threads on or off", ""), ("Customize toolbar", ""),
    ("Options", ""), ("Add an account", ""), ("Message rules", ""), ("Automatic replies", ""),
    ("Import messages", ""), ("Save message as", ""), ("Open a saved message", ""),
    ("Print", "Ctrl+P"), ("Properties", "Alt+Enter"), ("Message source", "Ctrl+F3"),
    ("Save search", ""), ("Hide read messages", ""), ("Ignore conversation", ""), ("Find message", "Ctrl+Shift+F"), ("Keyboard shortcuts", "")]

proc commandBox() =
  ## Alt+Q: "Tell me what you want to do" -- every command, found by typing.
  if not cmdOpen:
    cmdWas = false
    return
  var names: seq[string]
  var found: seq[string]
  let f = cmdText.strip.toLowerAscii
  for (n, k) in commands():
    if f.len == 0 or f in n.toLowerAscii:
      found.add n
      names.add n & (if k.len > 0: "\t" & k else: "")
  cmdSel = clamp(cmdSel, 0, max(0, found.high))
  dialog cmdOpen, "Tell Me What You Want to Do", dp(420):
    if not cmdWas:
      cmdWas = true
      cmdText = ""
      ui.textFocusWanted = true
    if edit(cmdText): cmdSel = 0
    if keyHit(KeyDown): cmdSel = min(found.high, cmdSel + 1)
    if keyHit(KeyUp): cmdSel = max(0, cmdSel - 1)
    let before = cmdSel
    listbox(names, cmdSel, rows = 10, tabs = [dp(270)])
    let go = (ui.doubleClick and cmdSel == before) or keyHit(KeyEnter)
    row:
      space available() - 2 * (dp(80) + Gap) + Gap
      if (button("Do It", isDefault = true, w = dp(80), enabled = found.len > 0) or go) and
         found.len > 0:
        cmdOpen = false
        runCommand(found[cmdSel])
      if button("Cancel", w = dp(80)): cmdOpen = false

# ---- follow up: a flag with a day -----------------------------------------------------------

proc followUp(ms: seq[Msg]; at: float) =
  ## Flagged, to be followed up at `at` (0: no day; -1: done, the flag off).
  store0.transaction:
    for m in ms:
      let on = at >= 0
      if m.flagged != on:
        store0.setFlags(m.id, flagged = int(on))
        queue(m, "flag", %*{"flagged": on})
      store0.setFollow(m.id, max(at, 0.0))
  status = if at > 0: "Follow up " & longDate(at)
           elif at == 0: "Flagged"
           else: "Marked complete"
  wake()
  changed()

proc followMenu(ms: seq[Msg]) =
  ## Message, Follow Up: Outlook's flags with a day.
  if menuItem("&Today", enabled = ms.len > 0): followUp(ms, max(epochTime() + 3600, tomorrowAt(17) - 86400))
  if menuItem("To&morrow", enabled = ms.len > 0): followUp(ms, tomorrowAt(9))
  if menuItem("This &Week", enabled = ms.len > 0): followUp(ms, nextMonday() - 3 * 86400)
  if menuItem("&Next Week", enabled = ms.len > 0): followUp(ms, nextMonday() + 3600)
  if menuItem("No &Date", enabled = ms.len > 0): followUp(ms, 0)
  menuSeparator()
  if menuItem("Mark &Complete", enabled = ms.anyIt(it.flagged)): followUp(ms, -1)

var remindedAt = 0.0

proc followReminders() =
  ## Once a minute: the follow-ups whose day has come are said (a balloon,
  ## and the system's notification).
  if epochTime() - remindedAt < 60: return
  remindedAt = epochTime()
  for d in store0.dueFollowUps(epochTime()):
    store0.setFollow(d.id, 0)
    let text = if d.subject.len > 0: d.subject else: "(no subject)"
    toast(text, title = "Follow up", glyph = nfFlag)
    status = "Follow up: " & text
    notifySystem("Follow up", text)

# ---- Quick Steps ------------------------------------------------------------------------------

type
  QuickAction = tuple[kind, arg: string]   ## "move" folder id, "tag" name, "read", "unread",
                                           ## "flag", "pin", "archive", "delete", "reply", "forward"
  QuickStep = object
    name: string
    actions: seq[QuickAction]

const quickKinds = [("", "(nothing)"), ("move", "Move to folder"), ("tag", "Tag"),
                    ("read", "Mark as read"), ("unread", "Mark as unread"), ("flag", "Flag"),
                    ("pin", "Pin"), ("archive", "Archive"), ("delete", "Delete"),
                    ("reply", "Reply"), ("forward", "Forward")]

proc quickSteps(): seq[QuickStep] =
  let j = try: parseJson(pref("quickSteps", "")) except CatchableError: newJNull()
  if j.kind != JArray:
    return @[QuickStep(name: "Done", actions: @[("read", ""), ("archive", "")]),
             QuickStep(name: "Reply & Delete", actions: @[("reply", ""), ("delete", "")]),
             QuickStep(name: "To Follow Up", actions: @[("flag", ""), ("read", "")])]
  for s in j:
    var q = QuickStep(name: s{"name"}.getStr)
    for a in s{"actions"}.getElems: q.actions.add (a{"kind"}.getStr, a{"arg"}.getStr)
    result.add q

proc saveQuickSteps(qs: seq[QuickStep]) =
  var j = newJArray()
  for q in qs:
    var acts = newJArray()
    for a in q.actions:
      if a.kind.len > 0: acts.add %*{"kind": a.kind, "arg": a.arg}
    j.add %*{"name": q.name, "actions": acts}
  prefs.put("quickSteps", $j)
  savePrefs()

proc runQuickStep(q: QuickStep; ms: seq[Msg]) =
  ## The step's actions on the selected mail, in order (a reply or forward
  ## opens last, after the others are done).
  if ms.len == 0: return
  var write = ""
  for a in q.actions:
    let cur = ms.mapIt(store0.message(it.id)).filterIt(it.id > 0)
    case a.kind
    of "move":
      let id = try: parseInt(a.arg) except ValueError: 0
      if id > 0: moveMsgs(cur, "", id)
    of "tag": (if a.arg.len > 0: setMsgTags(cur, a.arg, true))
    of "read": markRead(cur)
    of "unread": markRead(cur, true)
    of "flag": followUp(cur, 0)
    of "pin": pinMsgs(cur.filterIt(not it.pinned))
    of "archive": archiveMsgs(cur)
    of "delete": deleteMsgs(cur)
    of "reply", "forward": write = a.kind
    else: discard
  if write.len > 0: openCompose(write, store0.message(ms[0].id))
  status = "Quick Step: " & q.name
  clearMulti()

var
  qsOpen = false
  qsSel = 0
  qsEdit: QuickStep
  qsLoaded = -1

proc quickStepsMenu() =
  ## The Quick Steps to run (Message menu, the tool bar).
  let ms = selectedMsgs()
  for q in quickSteps():
    if menuItem(q.name, enabled = ms.len > 0): runQuickStep(q, ms)
  menuSeparator()
  if menuItem("&Manage Quick Steps..."): qsOpen = true

proc quickStepsDialog() =
  ## Manage Quick Steps: each a name and up to four actions.
  if not qsOpen:
    qsLoaded = -1
    return
  var qs = quickSteps()
  dialog qsOpen, "Manage Quick Steps", dp(560):
    var names = qs.mapIt(it.name)
    row([dp(180), -1]):
      col:
        listbox(names, qsSel, rows = 9)
        row:
          if button("&New", w = dp(86)):
            qs.add QuickStep(name: "Quick Step " & $(qs.len + 1), actions: @[("read", "")])
            saveQuickSteps(qs)
            qsSel = qs.high
            qsLoaded = -1
          if button("&Delete", w = dp(86), enabled = qsSel in 0 ..< qs.len):
            qs.delete(qsSel)
            saveQuickSteps(qs)
            qsSel = max(0, qsSel - 1)
            qsLoaded = -1
      col:
        if qsSel in 0 ..< qs.len:
          if qsLoaded != qsSel:
            qsLoaded = qsSel
            qsEdit = qs[qsSel]
            while qsEdit.actions.len < 4: qsEdit.actions.add ("", "")
          form dp(70):
            field "&Name:": edit qsEdit.name
          var folderNames: seq[string]
          var folderIds: seq[int]
          for a in accountsC:
            for f in foldersC.getOrDefault(a.id):
              folderNames.add f.name & " (" & a.email & ")"
              folderIds.add f.id
          let tagNames = tagsC.mapIt(it.name)
          for k in 0 ..< 4:
            withId("qsact" & $k):
              row:
                var i = 0
                for q, (kk, _) in quickKinds:
                  if kk == qsEdit.actions[k].kind: i = q
                if combo(quickKinds.mapIt(it[1]), i, w = dp(150)):
                  qsEdit.actions[k] = (quickKinds[i][0], "")
                case qsEdit.actions[k].kind
                of "move":
                  var fi = max(0, folderIds.find(try: parseInt(qsEdit.actions[k].arg) except ValueError: 0))
                  if folderIds.len > 0:
                    if combo(folderNames, fi, w = dp(180)) or qsEdit.actions[k].arg.len == 0:
                      qsEdit.actions[k].arg = $folderIds[fi]
                of "tag":
                  var ti = max(0, tagNames.find(qsEdit.actions[k].arg))
                  if tagNames.len > 0:
                    if combo(tagNames, ti, w = dp(180)) or qsEdit.actions[k].arg.len == 0:
                      qsEdit.actions[k].arg = tagNames[ti]
                else: discard
          if button("&Save the Quick Step"):
            qs[qsSel] = qsEdit
            saveQuickSteps(qs)
            status = "Saved the Quick Step " & qsEdit.name
    row:
      space available() - dp(84)
      if button("Close", isDefault = true, w = dp(84)): qsOpen = false

# ---- Sweep ----------------------------------------------------------------------------------------

var
  sweepOpen = false
  sweepWhat = 0
  sweepFrom = ""
  sweepName = ""
  sweepFolder = 0

proc openSweep() =
  let ms = selectedMsgs()
  if ms.len == 0: return
  sweepFrom = ms[0].fromEmail
  sweepName = who(ms[0])
  sweepWhat = 0
  sweepOpen = true

proc sweepFromMessage(id: int) =
  ## Sweep, for the sender of message `id`.
  let m = store0.message(id)
  if m.id == 0: return
  sweepFrom = m.fromEmail
  sweepName = who(m)
  sweepWhat = 0
  sweepOpen = true

proc sweepDialog() =
  ## Sweep: everything from one sender at once -- as the new Outlook does.
  if not sweepOpen: return
  let here = if place.kind == plFolder: place.folder else: 0
  let ms = store0.whereMessages("lower(from_email) = ?" & (if here > 0: " AND folder = " & $here else:
                                " AND folder IN (SELECT id FROM folders WHERE role = 'inbox')"),
                                @[toDbValue(sweepFrom.toLowerAscii)], 5000)
  dialog sweepOpen, "Sweep", dp(460):
    label "Messages from " & sweepName & " <" & sweepFrom & ">: " & $ms.len &
          (if here > 0: " in this folder" else: " in the Inbox"), bold = true
    space()
    radio("Move them all to Deleted Items", sweepWhat, 0)
    radio("Archive them all", sweepWhat, 1)
    radio("Keep only the newest, delete the rest", sweepWhat, 2)
    radio("Delete them all, and all that come from " & sweepName & " from now on", sweepWhat, 3)
    radio("Archive them all, and all that come from " & sweepName & " from now on", sweepWhat, 4)
    paragraph "(From now on is a rule: Tools, Message Rules has it.)"
    row:
      space available() - 2 * (dp(80) + Gap) + Gap
      if button("Sweep", isDefault = true, w = dp(80), enabled = ms.len > 0 or sweepWhat >= 3):
        case sweepWhat
        of 0, 3: deleteMsgs(ms)
        of 1, 4: archiveMsgs(ms)
        of 2:
          var sorted = ms
          sorted.sort(proc (a, b: Msg): int = cmp(b.date, a.date))
          if sorted.len > 1: deleteMsgs(sorted[1 .. ^1])
        else: discard
        if sweepWhat >= 3:
          addSenderRule(sweepFrom, if sweepWhat == 3: "delete" else: "archive")
        sweepOpen = false
      if button("Cancel", w = dp(80)): sweepOpen = false

# ---- attachments: previews --------------------------------------------------------------------

var
  previewOpen = false
  previewAtt = 0
  previewZoom = 0.0
  previewPdf: PdfView
  previewPdfFor = 0

proc attachmentPicture(id: int): Bitmap =
  ## An attached picture, decoded once (nil while it downloads).
  let key = "att:" & $id
  if pictures.hasKey(key): return pictures[key]
  let data = store0.attachmentData(id)
  if data.len == 0: return nil
  let b = pictureFromBytes(key, data)
  pictures[key] = b
  b

proc openPreview(a: Att) =
  ## A picture or a PDF looked at here, before (or instead of) opening it.
  previewAtt = a.id
  previewZoom = 0
  previewOpen = true
  if store0.attachmentData(a.id).len == 0:
    link.cmds.send(SyncCmd(kind: scAttachment, id: a.id))

proc previewDialog() =
  if not previewOpen: return
  let r = store0.one("SELECT name, mime FROM atts WHERE id = ?", previewAtt)
  let name = if r.len > 0: r[0].str else: "attachment"
  let mime = if r.len > 0: r[1].str.toLowerAscii else: ""
  let data = store0.attachmentData(previewAtt)
  let w = min(ui.w - dp(24), dp(900))
  let h = max(dp(240), ui.h - dp(200))
  dialog previewOpen, name, w:
    if data.len == 0:
      row:
        spinner()
        label "Downloading " & name & "...", color = ui.theme.gray
      space(h - CtrlH)
      wakeIn(300)
    elif mime.startsWith("image/") or name.toLowerAscii.endsWith(".png") or
         name.toLowerAscii.endsWith(".jpg") or name.toLowerAscii.endsWith(".jpeg") or
         name.toLowerAscii.endsWith(".gif") or name.toLowerAscii.endsWith(".webp"):
      let b = attachmentPicture(previewAtt)
      if b == nil: paragraph "This picture could not be read here."
      else: imageView(b, previewZoom, height = h)
    elif "pdf" in mime or name.toLowerAscii.endsWith(".pdf"):
      if previewPdfFor != previewAtt:
        previewPdfFor = previewAtt
        previewPdf = nil
        let p = getTempDir() / "retro-mail" / $previewAtt & ".pdf"
        try:
          createDir(p.parentDir)
          writeFile(p, data)
          previewPdf = openPdfView(p)
        except CatchableError: previewPdf = nil
      if previewPdf == nil: paragraph "This PDF could not be read here: Open shows it in its program."
      else:
        row:
          if button("-", w = dp(32)): previewPdf.zoomOut()
          if button("+", w = dp(32)): previewPdf.zoomIn()
          label "Page " & $(previewPdf.page + 1) & " of " & $previewPdf.count
        pdfView(previewPdf, height = h - CtrlH - Gap)
    else:
      paragraph "There is no preview of this kind of file here."
    row:
      space available() - 3 * (dp(90) + Gap) + Gap
      if button("Open", w = dp(90), enabled = data.len > 0):
        openAttachment(previewAtt)
      if button("Save As...", w = dp(90)):
        previewOpen = false
        saveAttachmentAs(previewAtt)
      if button("Close", isDefault = true, w = dp(90)): previewOpen = false
