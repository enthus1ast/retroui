# (included by hrbook.nim) Letters and certificates: make them, edit the
# templates, and the list of those issued.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

var
  tplSel = 0
  tplLoaded = -1
  tplName = ""
  tplBody = ""
  tplLang = 0
  tplHotel = 0
  tplEditorId: Id
  letterTab = 0
  showTagHelp = false
  tagPickSel = 0
  tagPickAs = 0
  tagQuery = ""
  askName = ""
  askTagOpen = false
  makeEmp = ""                ## "SOH-1042 -- Maryam Al Hinai" as typed / picked
  answers: seq[string]
  answerKeys: seq[string]
  previewDoc: Report
  previewSig = ""             ## what the preview shows
  previewWant = ""            ## what it is to show (the form as it is now)
  previewWantAt = 0.0         ## when that last changed
  madeDoc: Report
  madeOpen = false
  madePath = ""
  madeRef = ""
  askDeleteTpl = false
  colsIssuedAll = @[column("Date", 86), column("Employee", 190), column("Letter", 190),
                    column("Ref. No.", 150), column("Hotel", 130)]
  issuedAllSel = 0
  lpW = 520                   ## the preview beside the form
  lpH = 420

proc liveTemplates(): seq[int] =
  for i, t in book.templates:
    if not t.deleted: result.add i

proc empLabel(i: int): string =
  let e = book.employees[i]
  (if e.get("empNo").len > 0: e.get("empNo") & " -- " else: "") & e.name

proc empChoices(): seq[string] =
  for i, e in book.employees:
    if not e.deleted: result.add empLabel(i)

proc empOfLabel(s: string): int =
  for i, e in book.employees:
    if not e.deleted and empLabel(i) == s: return i
  # (typed: a number or a name)
  let q = s.strip.toLowerAscii
  if q.len == 0: return -1
  for i, e in book.employees:
    if not e.deleted and (e.get("empNo").toLowerAscii == q or e.name.toLowerAscii == q): return i
  -1

proc loadTemplate(i: int) =
  let t = book.templates[i]
  tplLoaded = i
  tplName = t.name
  tplBody = t.body
  tplLang = ord(t.lang)
  tplHotel = if t.hotel.len == 0: 0 else: book.hotelIndex(t.hotel) + 1

proc templateChanged(): bool =
  if tplLoaded < 0 or tplLoaded >= book.templates.len: return false
  let t = book.templates[tplLoaded]
  t.name != tplName or t.body != tplBody or ord(t.lang) != tplLang or
    (if t.hotel.len == 0: 0 else: book.hotelIndex(t.hotel) + 1) != tplHotel

proc saveTemplate() =
  if tplLoaded < 0 or tplLoaded >= book.templates.len: return
  book.templates[tplLoaded].name = tplName.strip
  book.templates[tplLoaded].body = tplBody
  book.templates[tplLoaded].lang = LetterLang(tplLang)
  book.templates[tplLoaded].hotel = if tplHotel > 0 and tplHotel <= book.hotels.len: book.hotels[tplHotel - 1].id else: ""
  book.templates[tplLoaded].modified = nowT()
  changed()

proc draftTemplate(): Template =
  result = if tplLoaded >= 0 and tplLoaded < book.templates.len: book.templates[tplLoaded] else: Template()
  result.name = tplName
  result.body = tplBody
  result.lang = LetterLang(tplLang)
  result.hotel = if tplHotel > 0 and tplHotel <= book.hotels.len: book.hotels[tplHotel - 1].id else: ""

proc askTags(t: Template): seq[string] =
  ## The blanks of the template, each once.
  for tag in findTags(t.body):
    if tag.ask and tag.name notin result: result.add tag.name

proc answersTable(t: Template): Table[string, string] =
  let asks = askTags(t)
  for i, a in asks:
    if i < answers.len and answers[i].strip.len > 0: result[tagKey(a)] = answers[i].strip

var answerMemo: Table[string, string]  ## the blanks filled before, by their name

proc syncAnswers(t: Template) =
  let asks = askTags(t)
  if asks != answerKeys:
    for i, k in answerKeys:
      if i < answers.len: answerMemo[tagKey(k)] = answers[i]
    answerKeys = asks
    answers = newSeq[string](asks.len)
    for i, k in asks: answers[i] = answerMemo.getOrDefault(tagKey(k))

proc letterPreview(t: Template; ei: int; height: int; key: string) =
  ## The letter as it will be, for employee `ei` (the reference number is
  ## shown as it will be, not taken).
  if ei < 0:
    emptyState(pxDocument, "Pick an employee to see the letter", h = height)
    return
  let e = book.employees[ei]
  let h = letterHotel(book, t, e)
  let refNo = nextRefNo(h)
  var sig = t.body & "\x00" & e.id & "\x00" & $e.modified & "\x00" & $t.lang & t.hotel & refNo & "\x00" &
            $h.modified
  for a in answers: sig.add "\x00" & a
  if sig != previewSig or previewDoc == nil:
    if sig != previewWant:
      previewWant = sig
      previewWantAt = nowT()
    # (made again once the typing stops: making it reads the hotel's
    # pictures, and keys pressed while it does would be lost)
    if previewDoc == nil or nowT() - previewWantAt >= 0.5:
      previewSig = sig
      previewDoc = letterReport(book, t, e, answersTable(t), refNo, dir)
    else:
      wakeIn(550)
  reportView(previewDoc, height = height, key = key)

proc makeLetter(t: Template; ei: int) =
  let e = book.employees[ei]
  let h = letterHotel(book, t, e)
  madeRef = takeRefNo(book, h.id)
  madeDoc = letterReport(book, t, e, answersTable(t), madeRef, dir)
  book.issued.add Issued(at: nowT(), emp: e.id, empName: e.name, templ: t.id, templName: t.name,
                         refNo: madeRef, hotel: h.id)
  changed()
  let safe = (t.name & " - " & e.name).multiReplace(("/", "-"), ("\\", "-"), (":", "-"))
  madePath = dir / "letters" / safe & ".pdf"
  madeOpen = true

proc makeTab(t: Template) =
  if letterFor >= 0 and letterFor < book.employees.len:
    makeEmp = empLabel(letterFor)
    letterFor = -1
  syncAnswers(t)
  let ei = empOfLabel(makeEmp)
  sidePane(true, lpW, lpH):
    form 0:
      field "Employee:": comboEdit(makeEmp, empChoices())
      for i, a in answerKeys:
        withId(a):
          field(a & ":"): edit(answers[i])
    if ei >= 0:
      let e = book.employees[ei]
      let h = letterHotel(book, t, e)
      label("On " & h.name & "'s paper · next number " & nextRefNo(h), color = ui.theme.gray)
    var missing = 0
    for a in answers:
      if a.strip.len == 0: inc missing
    if missing > 0: label($missing & " blank(s) to fill in above.", color = color(200, 120, 0))
    row:
      if button("&Make the letter", isDefault = true, enabled = ei >= 0):
        makeLetter(t, ei)
  do:
    letterPreview(t, ei, -1, "make")

proc templateTab(t: Template) =
  sidePane(true, lpW, lpH):
    form 0:
      field "Name:": edit(tplName)
      field "Language:": segmented(["English", "Arabic", "Both"], tplLang)
      field "Paper:": combo(@["The employee's hotel"] & hotelNames(), tplHotel)
    row:
      if button("Insert a &tag..."): showTagHelp = true
      if button("Insert a &blank..."):
        askName = ""
        askTagOpen = true
        focusFirstText()
      spring()
      if button("&Save", isDefault = true, enabled = templateChanged()): saveTemplate()
      if button("Undo changes", enabled = templateChanged()): loadTemplate(tplLoaded)
    editArea(tplBody, lines = -1)
    tplEditorId = ui.lastId
  do:
    var ei = empOfLabel(makeEmp)
    if ei < 0:
      for i, e in book.employees:
        if not e.deleted:
          ei = i
          break
    letterPreview(draftTemplate(), ei, -1, "edit")

proc insertAtCaret(s: string) =
  var stt = state(tplEditorId)
  let a = clamp(min(stt.caret, stt.anchor), 0, tplBody.len)
  let b = clamp(max(stt.caret, stt.anchor), 0, tplBody.len)
  tplBody = tplBody[0 ..< a] & s & tplBody[b .. ^1]
  stt.caret = a + s.len
  stt.anchor = stt.caret
  state(tplEditorId) = stt
  ui.focus = tplEditorId
  letterTab = 1

proc lettersPage() =
  let live = liveTemplates()
  row:
    heading("Letters and certificates", 2)
    spring()
    if button("&New template"):
      book.templates.add Template(id: newId("t-"), name: "New letter", lang: llEnglish,
                                  modified: nowT(), body: "# TITLE\n\nTo: #[?Addressed to]#\n\n" &
                                    "This is to certify that #[Mr/Ms]# #[Name]# ...\n\n[signature]\n")
      tplSel = liveTemplates().high
      letterTab = 1
      changed()
    if button("&Copy", enabled = live.len > 0):
      var c = book.templates[live[tplSel]]
      c.id = newId("t-")
      c.name = c.name & " (copy)"
      c.modified = nowT()
      book.templates.add c
      tplSel = liveTemplates().high
      changed()
    if button("&Delete...", enabled = live.len > 0): askDeleteTpl = true
  if live.len == 0:
    emptyState(pxDocument, "No templates", detail = "Make one with New template.")
    return
  tplSel = clamp(tplSel, 0, live.high)
  var names: seq[string]
  for i in live:
    let t = book.templates[i]
    names.add t.name & (case t.lang
                        of llArabic: "  (عربي)"
                        of llBoth: "  (both)"
                        else: "")
  row:
    label "Template:"
    combo(names, tplSel, w = 300)
    if templateChanged(): label("(changed: Save to keep it)", color = color(200, 120, 0))
  if tplLoaded != live[tplSel]:
    if templateChanged(): saveTemplate()
    loadTemplate(live[tplSel])
  let t = book.templates[live[tplSel]]
  tabs(letterTab, ["&Make a letter", "&Edit the template", "&Issued (" & $book.issued.len & ")"]):
    case letterTab
    of 0: makeTab(t)
    of 1: templateTab(t)
    else:
      var rows: seq[seq[string]]
      for k in countdown(book.issued.high, 0):
        let x = book.issued[k]
        rows.add @[showDate(fromUnix(int64(x.at)).local.format("yyyy-MM-dd")), x.empName,
                   x.templName, x.refNo, book.hotelName(x.hotel)]
      if rows.len == 0: label("No letters made yet.", color = ui.theme.gray)
      else: grid(colsIssuedAll, rows, issuedAllSel, height = -1)

proc letterDialogs() =
  # the letter made: save, share, print
  if madeOpen and madeDoc != nil:
    dialog(madeOpen, "Letter " & madeRef, 560):
      reportView(madeDoc, height = min(dp(520), ui.h - dp(220)), key = "made")
      label("Numbered " & madeRef & " and kept in the list of issued letters.", color = ui.theme.gray)
      row:
        if button("Save &PDF", isDefault = true):
          try:
            createDir(madePath.parentDir)
            madeDoc.savePdf(madePath)
            let out2 = downloadsDir() / madePath.extractFilename
            if out2 != madePath:
              try: copyFile(madePath, out2)
              except IOError, OSError: discard
            toast("Saved " & madePath.extractFilename, glyph = pxCheck)
          except IOError, OSError: toast("Could not save the PDF", glyph = pxError)
        if button("S&hare..."):
          try:
            createDir(madePath.parentDir)
            madeDoc.savePdf(madePath)
            if not shareFile(madePath): toast("Sharing is not available here", glyph = pxInfo)
          except IOError, OSError: toast("Could not save the PDF", glyph = pxError)
        if button("P&rint..."):
          let r = madeDoc.printReport(madeRef)
          if not r.ok: toast(r.message, glyph = pxWarning)
        spring()
        if button("Close"): madeOpen = false
  # inserting a tag
  if showTagHelp:
    dialog(showTagHelp, "Insert a tag", 520):
      paragraph("A tag is replaced by the employee's data when the letter is made: " &
                "#[Total Salary]# becomes 790.000. After a | it can be written another way.",
                color = ui.theme.gray)
      searchBox(tagQuery, "Search the tags")
      var names: seq[string]
      for n in book.tagNames(draftTemplate().lang == llArabic):
        if tagQuery.len == 0 or tagQuery.toLowerAscii in n.toLowerAscii: names.add n
      tagPickSel = clamp(tagPickSel, 0, max(0, names.high))
      listbox(names, tagPickSel, rows = 8)
      label("Written as:")
      segmented(["As it is", "In words", "Arabic words", "Long date", "Arabic date"], tagPickAs)
      let suffix = ["", "|words", "|words-ar", "|long", "|long-ar"][tagPickAs]
      let tag = if names.len > 0: "#[" & names[tagPickSel] & suffix & "]#" else: ""
      var ei = empOfLabel(makeEmp)
      if ei < 0 and book.employees.len > 0: ei = 0
      if tag.len > 0 and ei >= 0 and ei < book.employees.len:
        let e = book.employees[ei]
        let vals = tagValues(book, e, letterHotel(book, draftTemplate(), e), "SOH/HR/2026/001")
        label("\u200E" & tag & "  →  " & fillTags(tag, vals), bold = true)
      row:
        spring()
        if button("&Insert", isDefault = true, enabled = tag.len > 0 and letterTab == 1):
          insertAtCaret(tag)
          showTagHelp = false
        if button("Close"): showTagHelp = false
  if askTagOpen:
    dialog(askTagOpen, "Insert a blank", 420):
      paragraph("A blank is asked when the letter is made (\"Addressed to\", \"Purpose\").",
                color = ui.theme.gray)
      form 0:
        field "Question:": edit(askName)
      row:
        spring()
        if button("&Insert", isDefault = true, enabled = askName.strip.len > 0):
          insertAtCaret("#[?" & askName.strip & "]#")
          askTagOpen = false
        if button("Cancel"): askTagOpen = false
  let live = liveTemplates()
  case msgBox(askDeleteTpl, AppTitle, "Delete the template \"" &
              (if live.len > 0 and tplSel < live.len: book.templates[live[tplSel]].name else: "") &
              "\"? The letters made with it stay in the list.", ["&Delete", "Cancel"], miQuestion)
  of 1:
    if live.len > 0 and tplSel < live.len:
      book.templates[live[tplSel]].deleted = true
      book.templates[live[tplSel]].modified = nowT()
      tplLoaded = -1
      tplSel = 0
      changed()
  else: discard
