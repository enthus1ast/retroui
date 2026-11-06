# (included by hrbook.nim) The employees: the list, a person's page, the form.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

var
  shownList: seq[int]       ## the employees in the list now (indexes)
  staffCols: seq[Column]
  staffColsSig = ""
  colKeys: seq[string]      ## the field of each column ("" marks, "=total")
  colBase: seq[int]          ## the columns' natural widths
  colsFitFor = -1
  # the form
  editOpen = false
  editIndex = -1
  editTab = 0
  editMsg = ""
  draftText: seq[string]
  draftDate: seq[Date]
  draftHasDate: seq[bool]
  draftBool: seq[bool]
  draftInt: seq[int]
  draftGroups: seq[bool]
  draftOther: seq[string]
  # letters from a person's page
  letterFor = -1

proc startEdit(i: int)

proc tagChip(x: var int; y, h: int; text: string; bg: Color; fg = color(255, 255, 255)) =
  let st0 = style(size = 0.85)
  let w = textWidth(text, st0) + dp(10)
  roundRect(rect(x, y, w, h), float(h) / 2, bg)
  text(x + dp(5), y + (h - lineHeight(st0)) div 2, text, fg, st0)
  x += w + dp(4)

proc marksOf(e: Employee): seq[(string, Color)] =
  if e.otherVisa:
    let i = book.hotelIndex(e.get("visaUnder"))
    let who = if i >= 0: (if book.hotels[i].code.len > 0: book.hotels[i].code else: book.hotels[i].name)
              else: e.get("visaUnder")
    result.add ("Visa: " & who, color(229, 115, 26))
  for gid in e.groups:
    for g in book.groups:
      if g.id == gid: result.add (g.name, colorOf(g.color))

proc drawMarks(e: Employee; r: Rect) =
  var x = r.x + 3
  let h = min(r.h - 6, FontH + 2)
  let y = r.y + (r.h - h) div 2
  pushClip(r)
  for (t, c) in marksOf(e): tagChip(x, y, h, t, c)
  popClip()

proc markChips(e: Employee) =
  ## The person's marks as chips (their own row).
  let marks = marksOf(e)
  if marks.len == 0: return
  let h = FontH + dp(4)
  let r = place(0, h, fill = true)
  var x = r.x
  for (t, c) in marks: tagChip(x, r.y, h, t, c)

proc buildCols() =
  let oneHotel = hotelFilter > 0 or section.startsWith("Employees/hotel:")
  var sig = $book.hideSalaries & $oneHotel
  for f in book.fields:
    if f.inList and not f.hidden: sig.add "|" & f.key
  if sig == staffColsSig: return
  staffColsSig = sig
  staffCols.setLen(0)
  colKeys.setLen(0)
  colBase.setLen(0)
  colsFitFor = -1
  for f in book.fields:
    if not f.inList or f.hidden: continue
    if f.key == "hotel" and oneHotel: continue
    let w = case f.key
            of "empNo": 76
            of "nameEn": 180
            of "nameAr": 160
            of "position": 150
            else: (if f.kind in {fkMoney, fkNumber}: 84 elif f.kind == fkDate: 88 else: 104)
    staffCols.add(if f.kind in {fkMoney, fkNumber}: numberColumn(f.label, w) else: column(f.label, w))
    colKeys.add f.key
  if not book.hideSalaries:
    staffCols.add numberColumn("Total", 112)
    colKeys.add "=total"
  staffCols.add customColumn("Marks", 170, proc (row: int; r: Rect; selected: bool) =
    if row < shownList.len: drawMarks(book.employees[shownList[row]], r))
  colKeys.add ""

proc fitCols(room: int) =
  ## The columns fitted to the room there is (the name and the position
  ## take what is spare, or give it back); the user's drags stay until the
  ## room changes.
  if room == colsFitFor or staffCols.len == 0: return
  colsFitFor = room
  if colBase.len != staffCols.len:
    colBase.setLen(0)
    for c in staffCols: colBase.add c.width
  var total = 0
  for w in colBase: total += w
  let flexible = proc (i: int): bool = colKeys[i] in ["nameEn", "position", "department", "nameAr", ""]
  var flexTotal = 0
  for i in 0 ..< staffCols.len:
    if flexible(i): flexTotal += colBase[i]
  let extra = room - total
  for i in 0 ..< staffCols.len:
    var w = colBase[i]
    if flexible(i) and flexTotal > 0:
      w = max(70, colBase[i] + extra * colBase[i] div flexTotal)
    staffCols[i].width = w

proc filteredList(): seq[int] =
  var hotelId = ""
  var groupId = ""
  var visa = visaOnly
  if section.startsWith("Employees/hotel:"): hotelId = section["Employees/hotel:".len .. ^1]
  elif section.startsWith("Employees/group:"): groupId = section["Employees/group:".len .. ^1]
  elif section == "Employees/visa": visa = true
  if hotelFilter > 0 and hotelFilter <= book.hotels.len: hotelId = book.hotels[hotelFilter - 1].id
  let depts = listOf("departments")
  let q = query.strip.toLowerAscii
  for i, e in book.employees:
    if e.deleted: continue
    if statusFilter == 0 and not e.active: continue
    if statusFilter == 1 and e.active: continue
    if hotelId.len > 0 and e.get("hotel") != hotelId: continue
    if groupId.len > 0 and groupId notin e.groups: continue
    if groupFilter > 0 and groupFilter <= book.groups.len and book.groups[groupFilter - 1].id notin e.groups: continue
    if visa and not e.otherVisa: continue
    if deptFilter > 0 and deptFilter <= depts.len and e.get("department") != depts[deptFilter - 1]: continue
    if q.len > 0:
      var hay = ""
      for k in ["empNo", "nameEn", "nameAr", "civilId", "passportNo", "position", "phone"]:
        hay.add e.get(k).toLowerAscii & " "
      if q notin hay and query.strip notin hay: continue
    result.add i
  result.sort(proc (a, b: int): int =
    let ha = book.hotelIndex(book.employees[a].get("hotel"))
    let hb = book.hotelIndex(book.employees[b].get("hotel"))
    if ha != hb: cmp(ha, hb) else: cmp(book.employees[a].get("empNo"), book.employees[b].get("empNo")))

proc cellText(e: Employee; key: string): string =
  if key == "=total": return (if book.hideSalaries: "•••" else: money(book.totalSalary(e)))
  let f = book.field(key)
  if book.hideSalaries and f.section == secSalary and f.kind == fkMoney: return "•••"
  book.display(f, e.get(key))

proc quickFacts(e: Employee) =
  row:
    avatar(e.name, dp(44))
    col:
      label(e.name, bold = true)
      if e.get("nameAr").len > 0: label(e.get("nameAr"))
      label(e.get("position"), color = ui.theme.gray)
  markChips(e)
  separator()
  var facts: seq[(string, string)]
  for k in ["empNo", "hotel", "department", "nationality", "joined", "contract", "phone",
            "visaExpiry", "passportExpiry"]:
    let f = book.field(k)
    if f.hidden: continue
    let v = book.display(f, e.get(k))
    if v.len > 0: facts.add (f.label, v)
  if not book.hideSalaries: facts.add ("Total salary", money(book.totalSalary(e)))
  factList(facts)
  row:
    if button("&Open", isDefault = true): current = shownList[sel]
    if button("&Edit..."): startEdit(shownList[sel])
    if button("&Letter..."):
      letterFor = shownList[sel]
      section = "Letters"

proc staffPage() =
  buildCols()
  let upright = ui.h > ui.w
  row:
    searchBox(query, "Search a name, number or ID", w = 230)
    combo(@["All hotels"] & hotelNames(), hotelFilter, w = 140)
    combo(@["All departments"] & listOf("departments"), deptFilter, w = 150)
    var gnames = @["All groups"]
    for g in book.groups: gnames.add g.name
    combo(gnames, groupFilter, w = 120)
    segmented(["Active", "Left", "All"], statusFilter)
    if not upright:
      spring()
      if button("&New employee"): startEdit(-1)
  shownList = filteredList()
  if sel >= shownList.len: sel = max(0, shownList.len - 1)
  if shownList.len == 0:
    emptyState(pxUser, if book.employees.len == 0: "No employees yet" else: "Nobody matches",
               detail = if book.employees.len == 0: "Import your Excel sheets, or add them one by one." else: "")
    if book.employees.len == 0:
      row:
        if button("&Import Excel sheets..."): section = "Import sheets"
        if button("&New employee..."): startEdit(-1)
    return
  template theGrid() =
    fitCols(max(300, (available() - SbW - dp(34)) * 100 div max(1, dp(100))))
    let ev = grid(staffCols, shownList.len, proc (r, c: int): string =
      if c < colKeys.len and colKeys[c].len > 0: cellText(book.employees[shownList[r]], colKeys[c]) else: "",
      sel, height = -1, rowHeaders = true, tapActivates = ui.touch,
      style = proc (r, c: int): CellStyle =
        let e = book.employees[shownList[r]]
        if not e.active: cellStyle(fg = color(128, 128, 128))
        elif c < colKeys.len and colKeys[c] == "nameEn": cellStyle(bold = true)
        else: CellStyle(),
      footer = proc (c: int): string =
        if c < colKeys.len and colKeys[c] == "nameEn": $shownList.len & " people"
        elif c < colKeys.len and colKeys[c] == "=total":
          var t = 0.0
          for i in shownList: t += book.totalSalary(book.employees[i])
          if book.hideSalaries: "" else: money(t)
        else: "")
    if ev.activated: current = shownList[sel]
  if upright:
    theGrid()
  else:
    sidePane(true, paneW, paneH):
      theGrid()
    do:
      panel: quickFacts(book.employees[shownList[sel]])

# ---- a person's page -------------------------------------------------------------------------

var
  colsHist = @[column("Date", 86), column("What", 150), column("Was", 140), column("Now", 140),
               column("From", 220)]
  colsDocs = @[colorColumn("", 26), column("Document", 160), column("Number", 130),
               column("Expires", 90), numberColumn("Days left", 70)]
  colsIssued = @[column("Date", 86), column("Letter", 200), column("Ref. No.", 150)]
  histSel, docSel, issuedSel = 0

proc sectionFacts(e: Employee; sec: Section) =
  var facts: seq[(string, string)]
  for f in book.fields:
    if f.section != sec or f.hidden: continue
    var v = book.display(f, e.get(f.key))
    if book.hideSalaries and f.kind == fkMoney: v = "•••"
    facts.add (f.label, v)
  if facts.len == 0:
    label("No fields here yet: add some in Settings > Fields.", color = ui.theme.gray)
  else: factList(facts)

proc profilePage() =
  let i = current
  let e = book.employees[i]
  let hotel = book.hotelName(e.get("hotel"))
  let upright = ui.h > ui.w
  template actions() =
    spring()
    let stt = e.get("status")
    badge(if stt.len > 0: stt else: "Active", if e.active: color(30, 140, 70) else: color(128, 128, 128))
    if button("&Edit..."): startEdit(i)
    if button("&Letter..."):
      letterFor = i
      section = "Letters"
    if button("&Delete..."): askDeleteEmp = true
  row:
    if button("< &Back", w = 80): current = -1
    avatar(e.name, dp(52))
    col(if upright: 380 else: 520):
      heading(e.name, 2)
      var sub = e.get("position")
      if e.get("department").len > 0: sub.add (if sub.len > 0: ", " else: "") & e.get("department")
      if hotel.len > 0: sub.add " -- " & hotel
      if e.get("nameAr").len > 0: sub = e.get("nameAr") & "   ·   " & sub
      label(sub, color = ui.theme.gray)
    if not upright: actions()
  if upright:
    row: actions()
  markChips(e)
  tabs(profileTab, ["&Personal", "&Job", "&Salary", "&Documents", "&Other", "&History", "Le&tters"]):
    case profileTab
    of 0, 1, 4:
      sectionFacts(e, [secPersonal, secJob, secSalary, secDocuments, secOther][
        (if profileTab == 0: 0 elif profileTab == 1: 1 else: 4)])
    of 2:
      if book.hideSalaries:
        label("Salaries are hidden (View > Hide salaries).", color = ui.theme.gray)
      else:
        kpiRow(150):
          for f in book.fields:
            # (an allowance the person does not have is left out, as in letters)
            if f.kind == fkMoney and f.inTotal and not f.hidden and not num(e.get(f.key)).isNaN:
              kpiTile(f.label, money(num(e.get(f.key))))
          kpiTile("Total a month", money(book.totalSalary(e)), color = color(31, 78, 121))
        # the basic salary over time, from the history
        var labels: seq[string]
        var vals: seq[float]
        for c in e.history:
          if c.field == "basic" and not num(c.now).isNaN:
            labels.add $fromUnix(int64(c.at)).utc.year
            vals.add num(c.now)
        adaptive(380):
          card("Basic salary over time"):
            if vals.len >= 2:
              chart("", chArea, labels, [series("Basic (OMR)", vals)], height = 220,
                    opts = ChartOpts(palette: @businessColors, dataLabels: true, key: "basic-" & e.id))
            else: label("One salary so far: changes will show here.", color = ui.theme.gray)
          card("Other salary details"):
            sectionFacts(e, secSalary)
    of 3:
      var rows: seq[seq[string]]
      for f in book.fields:
        if f.section != secDocuments or f.hidden or f.kind != fkDate: continue
        let v = e.get(f.key)
        if v.len == 0: continue
        let d = dayNum(v) - todayNum()
        let c = if d < 0: "#808080" elif d <= 30: "#C53030" elif d <= 90: "#E5731A" else: "#2E8B57"
        var number = ""
        case f.key
        of "passportExpiry": number = e.get("passportNo")
        of "visaExpiry": number = e.get("visaNo")
        of "civilIdExpiry": number = e.get("civilId")
        else: discard
        rows.add @[c, f.label.replace(" Expiry", ""), number, showDate(v), $d]
      if rows.len == 0: label("No document dates yet.", color = ui.theme.gray)
      else: grid(colsDocs, rows, docSel, height = min(8, rows.len + 1))
      sectionFacts(e, secDocuments)
    of 5:
      var rows: seq[seq[string]]
      for k in countdown(e.history.high, 0):
        let c = e.history[k]
        let f = book.field(c.field)
        rows.add @[showDate(fromUnix(int64(c.at)).local.format("yyyy-MM-dd")), f.label,
                   book.display(f, c.was), book.display(f, c.now), c.source]
      grid(colsHist, rows, histSel, height = -1)
    else:
      var rows: seq[seq[string]]
      for k in countdown(book.issued.high, 0):
        let x = book.issued[k]
        if x.emp == e.id:
          rows.add @[showDate(fromUnix(int64(x.at)).local.format("yyyy-MM-dd")), x.templName, x.refNo]
      if rows.len == 0: label("No letters made yet.", color = ui.theme.gray)
      else: grid(colsIssued, rows, issuedSel, height = -1)
      if button("&Make a letter..."):
        letterFor = i
        section = "Letters"

# ---- the form ----------------------------------------------------------------------------------

proc toDate(iso: string): Date =
  let d = parseDateText(iso)
  if d.ok: date(d.y, d.m, d.d) else: today()

proc isoOf(d: Date): string = $d.year & "-" & align($d.month, 2, '0') & "-" & align($d.day, 2, '0')

proc startEdit(i: int) =
  editIndex = i
  editTab = 0
  editMsg = ""
  let n = book.fields.len
  draftText = newSeq[string](n)
  draftDate = newSeq[Date](n)
  draftHasDate = newSeq[bool](n)
  draftBool = newSeq[bool](n)
  draftInt = newSeq[int](n)
  draftOther = newSeq[string](n)
  draftGroups = newSeq[bool](book.groups.len)
  var e = if i >= 0: book.employees[i] else: newEmployee()
  if i < 0:
    e.v["status"] = "Active"
    var h = ""
    if section.startsWith("Employees/hotel:"): h = section["Employees/hotel:".len .. ^1]
    elif hotelFilter > 0 and hotelFilter <= book.hotels.len: h = book.hotels[hotelFilter - 1].id
    elif book.hotels.len > 0: h = book.hotels[0].id
    e.v["hotel"] = h
  for k, f in book.fields:
    let v = e.get(f.key)
    case f.kind
    of fkDate:
      draftHasDate[k] = v.len > 0
      draftDate[k] = toDate(v)
    of fkYesNo: draftBool[k] = v in ["1", "true", "Yes", "yes"]
    of fkHotel:
      let hi = book.hotelIndex(v)
      if f.key == "visaUnder":
        draftInt[k] = if v.len == 0: 0 elif hi >= 0: hi + 1 else: book.hotels.len + 1
        if hi < 0: draftOther[k] = v
      else: draftInt[k] = max(0, hi)
    of fkMoney, fkNumber:
      let x = num(v)
      draftText[k] = if x.isNaN: v elif f.kind == fkMoney: fmtNum(x, 3).replace(",", "") else: v
    else: draftText[k] = v
  for g, grp in book.groups: draftGroups[g] = grp.id in e.groups
  editOpen = true

proc fieldControl(k: int; f: FieldDef) =
  case f.kind
  of fkLine: edit(draftText[k])
  of fkLongText: editArea(draftText[k], lines = 3)
  of fkNumber, fkMoney: edit(draftText[k], w = 140)
  of fkDate:
    if draftHasDate[k]:
      row:
        datePicker(draftDate[k], w = 150)
        if button("Clear", w = 60): draftHasDate[k] = false
    else:
      if button("Set a date...", w = 120):
        draftHasDate[k] = true
        draftDate[k] = today()
  of fkChoice: comboEdit(draftText[k], listOf(f.list))
  of fkYesNo: checkbox("Yes", draftBool[k])
  of fkHotel:
    if f.key == "visaUnder":
      combo(@["(the hotel they work at)"] & hotelNames() & @["Another company"], draftInt[k])
      if draftInt[k] == book.hotels.len + 1: edit(draftOther[k])
    else:
      combo(hotelNames(), draftInt[k])

proc saveEdit(): bool =
  # the employee number: there, and not taken in the same hotel
  var noIdx, nameIdx, hotelIdx = -1
  for k, f in book.fields:
    if f.key == "empNo": noIdx = k
    if f.key == "nameEn": nameIdx = k
    if f.key == "hotel": hotelIdx = k
  let no = if noIdx >= 0: draftText[noIdx].strip else: ""
  let nm = if nameIdx >= 0: draftText[nameIdx].strip else: ""
  if no.len == 0 and nm.len == 0:
    editMsg = "Give at least the name or the employee number."
    return false
  let hotelId = if hotelIdx >= 0 and draftInt[hotelIdx] < book.hotels.len: book.hotels[draftInt[hotelIdx]].id else: ""
  if no.len > 0:
    for j, o in book.employees:
      if j != editIndex and not o.deleted and o.get("empNo").strip.toUpperAscii == no.toUpperAscii and
         o.get("hotel") == hotelId:
        editMsg = "Number " & no & " is " & o.name & "'s already."
        return false
  for k, f in book.fields:
    if f.kind in {fkMoney, fkNumber} and draftText[k].strip.len > 0 and num(draftText[k]).isNaN:
      editMsg = f.label & ": not a number."
      editTab = ord(f.section)
      return false
  var e = if editIndex >= 0: book.employees[editIndex] else: newEmployee()
  let at = nowT()
  for k, f in book.fields:
    var v = ""
    case f.kind
    of fkDate: v = if draftHasDate[k]: isoOf(draftDate[k]) else: ""
    of fkYesNo: v = if draftBool[k]: "1" else: (if e.get(f.key).len > 0: "0" else: "")
    of fkHotel:
      if f.key == "visaUnder":
        let x = draftInt[k]
        v = if x == 0: "" elif x <= book.hotels.len: book.hotels[x - 1].id else: draftOther[k].strip
      else:
        v = if draftInt[k] < book.hotels.len: book.hotels[draftInt[k]].id else: ""
    of fkMoney, fkNumber:
      let x = num(draftText[k])
      v = if x.isNaN: "" elif x == round(x): $int64(x) else: $x
    of fkChoice:
      v = draftText[k].strip
      if v.len > 0 and f.list.len > 0:
        var l = listOf(f.list)
        if v notin l:
          l.add v
          book.lists[f.list] = l
    else: v = draftText[k].strip
    e.setValue(f.key, v, "edited by hand", at)
  var gs: seq[string]
  for g, on in draftGroups:
    if on and g < book.groups.len: gs.add book.groups[g].id
  if gs != e.groups:
    e.groups = gs
    e.modified = at
  if editIndex >= 0: book.employees[editIndex] = e
  else:
    book.employees.add e
    current = book.employees.high
    if not section.startsWith("Employees"): section = "Employees/All hotels"
  changed()
  true

proc editDialog() =
  if not editOpen: return
  let title = if editIndex >= 0: "Edit " & book.employees[editIndex].name else: "New employee"
  dialog(editOpen, title, 640):
    tabs(editTab, ["&Personal", "&Job", "&Salary", "&Documents", "&Other", "&Groups"], sameHeight = true):
      if editTab <= 4:
        let sec = Section(editTab)
        form 0:
          for k, f in book.fields:
            if f.section != sec or f.hidden: continue
            withId(f.key):
              field(f.label & ":"):
                fieldControl(k, f)
      else:
        if book.groups.len == 0: label("No groups yet: add them in Settings > Groups.", color = ui.theme.gray)
        else:
          var names: seq[string]
          for g in book.groups: names.add g.name
          checkList(names, draftGroups, rows = min(8, names.len))
    if editMsg.len > 0: label(editMsg, color = color(200, 0, 0))
    row:
      var total = 0.0
      for k, f in book.fields:
        if f.kind == fkMoney and f.inTotal and not f.hidden:
          let x = num(draftText[k])
          if not x.isNaN: total += x
      label("Total a month: OMR " & money(total), bold = true)
      spring()
      if button("&Save", isDefault = true):
        if saveEdit(): editOpen = false
      if button("Cancel"): editOpen = false
