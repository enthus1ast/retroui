# Retro Mail: Calendar, People, To Do and Notes. Included by
# examples/mail.nim.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

var
  calDay: Date
  calMode = amWeek
  appts: seq[Appointment]
  apptsVer = -1
  apptsFrom = 0.0
  peopleFilter = ""
  peopleSel = 0
  peopleRows: seq[tuple[email, name: string; uses: int; saved: bool]]
  peopleVer = -1
  pName, pMail, pPhone, pCompany, pNotes: string
  pLoaded = ""
  taskText = ""
  noteSel = 0
  noteTitle, noteBody: string
  noteId = 0
  noteLoaded = -1
  peopleW = 420
  notesW = 260

proc toDate(t: float): Date =
  let d = fromUnixFloat(t).local
  date(d.year, ord(d.month), d.monthday)

proc minuteOf(t: float): int =
  let d = fromUnixFloat(t).local
  d.hour * 60 + d.minute

proc loadAppts() =
  if calDay.year == 0: calDay = today()
  let d0 = dateTime(calDay.year, Month(calDay.month), 1, 0, 0, 0, 0, local()).toTime.toUnixFloat
  if apptsVer == dataVer and apptsFrom == d0: return
  apptsVer = dataVer
  apptsFrom = d0
  appts.setLen(0)
  let palette = [rgb(0, 99, 177), rgb(0, 128, 0), rgb(122, 59, 160), rgb(200, 100, 0)]
  for e in store0.events(d0 - 7 * 86400, d0 + 45 * 86400):
    var k = 0
    for i, a in accountsC:
      if a.id == e.account: k = i
    if e.allDay:
      var t = e.start
      while t < e.finish - 1:
        appts.add Appointment(title: e.title, day: toDate(t), allDay: true, color: palette[k mod 4])
        t += 86400
    else:
      appts.add Appointment(title: e.title & (if e.location.len > 0: " (" & e.location & ")" else: ""),
                            day: toDate(e.start), start: minuteOf(e.start),
                            finish: (if toDate(e.finish) == toDate(e.start): minuteOf(e.finish) else: 1440),
                            color: palette[k mod 4])

proc calendarView() =
  loadAppts()
  if isCompact():
    discard agendaView(appts, calDay, calMode, height = -1, key = "cal")
    return
  split(treeW, -1):
    calendar(calDay)
    space()
    label "Calendars", bold = true
    for i, a in accountsC:
      label a.email, color = [rgb(0, 99, 177), rgb(0, 128, 0), rgb(122, 59, 160), rgb(200, 100, 0)][i mod 4]
    space()
    paragraph "Calendars are read from your accounts. New events: in Outlook or Google " &
              "Calendar for now."
    if link("Open Outlook on the web"): discard openUrl("https://outlook.office.com/calendar/")
    if link("Open Google Calendar"): discard openUrl("https://calendar.google.com/")
  do:
    let ev = agendaView(appts, calDay, calMode, height = -1, key = "cal")
    if ev.opened: status = "An event: open it in your account's calendar to change it"

proc peopleView() =
  if peopleVer != dataVer:
    peopleVer = dataVer
    peopleRows = store0.contacts(peopleFilter, 2000)
  split(peopleW, -1):
    row:
      if searchBox(peopleFilter, "Find people"):
        peopleVer = -1
    var data: seq[seq[string]]
    for p in peopleRows: data.add @[p.name, p.email, $p.uses]
    var cols = @[column("Name", 150), column("E-mail", 180), numberColumn("Messages", 70)]
    let ev = grid(cols, data, peopleSel, height = -1)
    if ev.activated and peopleSel in 0 ..< peopleRows.len:
      let p = peopleRows[peopleSel]
      openCompose("new", to = (if p.name.len > 0: p.name & " <" & p.email & ">" else: p.email))
  do:
    if peopleSel in 0 ..< peopleRows.len and pLoaded != peopleRows[peopleSel].email:
      let p = peopleRows[peopleSel]
      pLoaded = p.email
      let d = store0.contactDetails(p.email)
      pName = d.name
      pMail = p.email
      pPhone = d.phone
      pCompany = d.company
      pNotes = d.notes
    panel(-1):
      label "Contact", bold = true
      form dp(90):
        field "&Name:": edit pName
        field "&E-mail:": edit pMail
        field "&Phone:": edit pPhone
        field "&Company:": edit pCompany
      label "Notes:"
      editArea(pNotes, lines = 4)
      row:
        if button("&Save", isDefault = true, enabled = '@' in pMail):
          store0.saveContact(pMail, pName, pPhone, pCompany, pNotes)
          peopleVer = -1
          status = "Saved " & pMail
        if button("&New Message", pxMail, enabled = '@' in pMail):
          openCompose("new", to = (if pName.len > 0: pName & " <" & pMail & ">" else: pMail))
        if button("Ne&w Contact"):
          pName = ""
          pMail = ""
          pPhone = ""
          pCompany = ""
          pNotes = ""
          pLoaded = "-"
        if button("&Delete", enabled = pMail.len > 0):
          store0.deleteContact(pMail)
          peopleVer = -1
      if pMail.len > 0:
        space()
        label "Recent mail with " & (if pName.len > 0: pName else: pMail), bold = true
        var args = @[toDbValue("%" & pMail & "%"), toDbValue("%" & pMail & "%")]
        for m in store0.whereMessages("from_email LIKE ? OR to_list LIKE ?", args, 8):
          if link(shortDate(m.date) & "  " & fit(m.subject, dp(320))):
            query = "from:" & pMail
            view = vMail
            changed()

proc todoView() =
  panel(-1):
    label "To Do", bold = true
    row([-1, dp(90)]):
      edit taskText
      if button("&Add", isDefault = true, enabled = taskText.strip.len > 0):
        discard store0.addTask(taskText.strip)
        taskText = ""
    space()
    for t in store0.tasks():
      row([-1, dp(30)]):
        var done = t.done
        if checkbox(t.title, done): store0.setTaskDone(t.id, done)
        if toolButton(pxDelete, "Delete"): store0.deleteTask(t.id)
    space()
    label "Flagged mail", bold = true
    var none: seq[DbValue]
    let flagged = store0.whereMessages("flagged = 1", none, 50)
    if flagged.len == 0: label "Nothing flagged", color = ui.theme.gray
    for m in flagged:
      row([dp(110), -1]):
        label shortDate(m.date), color = ui.theme.gray
        if link(fit(who(m) & ": " & m.subject, available())):
          goPlace(Place(kind: plFlagged))

proc notesView() =
  let ns = store0.notes()
  split(notesW, -1):
    if button("&New Note", pxNote):
      noteId = store0.saveNote(0, "New note", "")
      noteLoaded = -1
      noteSel = 0
    var names: seq[string]
    for n in ns: names.add(if n.title.len > 0: n.title else: "(untitled)")
    listbox(names, noteSel, rows = -1)
  do:
    if noteSel in 0 ..< ns.len and noteLoaded != ns[noteSel].id:
      noteLoaded = ns[noteSel].id
      noteId = ns[noteSel].id
      noteTitle = ns[noteSel].title
      noteBody = ns[noteSel].body
    if ns.len == 0:
      label "No notes yet.", color = ui.theme.gray
    else:
      var ch = edit(noteTitle)
      if editArea(noteBody, lines = -1): ch = true
      if ch: discard store0.saveNote(noteId, noteTitle, noteBody)
      if button("&Delete Note"):
        store0.deleteNote(noteId)
        noteLoaded = -1
