# (included by hrbook.nim) Importing Excel and CSV sheets, in four steps.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

var
  importPlan: Plan
  importStep = 0
  importPickOpen = false
  importPick = ""
  importSheet = 0
  importResult: ImportResult
  importUndo: tuple[on: bool; emps: seq[Employee]; fields: seq[FieldDef];
                    lists: OrderedTable[string, seq[string]]; layouts: seq[Layout]]
  colsSheets = @[iconColumn("", 30), column("File", 200), column("Sheet", 110),
                 numberColumn("Rows", 56), choiceColumn("Hotel", [""], 150),
                 column("Looks like", 220), checkColumn("Use", 46)]
  colsMap = @[column("Column in the sheet", 160), column("First values", 230),
              choiceColumn("Goes to", [""], 170), progressColumn("Sure", 80), column("Why", 300)]
  colsAsk = @[colorColumn("", 26), column("Employee", 190), column("Question", 130),
              column("In HR Book", 190), column("In the sheet", 190),
              choiceColumn("Choice", ["Take the sheet's", "Keep HR Book's", "Same person", "Not the same"], 140)]
  colsNew = @[checkColumn("Add", 46), column("No.", 90), column("Name", 220),
              choiceColumn("Hotel", [""], 150), column("From", 420)]
  impSel1, impSel2, impSel3, impSel4 = 0

proc fieldChoices(): seq[string] =
  result = @["(skip)", "(new extra field)", "(new allowance)"]
  for f in book.fields:
    if not f.hidden: result.add f.label

proc fieldOfChoice(s: string): string =
  if s == "(skip)": return ""
  if s == "(new extra field)": return "+"
  if s == "(new allowance)": return "+$"
  for f in book.fields:
    if f.label == s: return f.key
  ""

proc choiceOfField(k: string): string =
  if k.len == 0: "(skip)" elif k == "+": "(new extra field)" elif k == "+$": "(new allowance)"
  else: book.field(k).label

proc resetImport() =
  importPlan = Plan()
  importStep = 0
  importSheet = 0

proc importPage() =
  heading("Import Excel sheets", 2)
  let back = stepper(["Files", "Columns", "People", "Done"], importStep)
  if back >= 0 and back < importStep and importStep < 3: importStep = back
  case importStep
  of 0:
    discard banner("Pick .xlsx or .csv files with any layout: the header row, the columns, the hotel " &
                   "and the people are found by themselves; you check them next. Nothing leaves this device.",
                   bkInfo, closable = false)
    row:
      if button("&Add files...") and filesOk():
        if importPick.len == 0 or not importPick.startsWith(downloadsDir()): importPick = downloadsDir()
        importPickOpen = true
      if button("Clear", enabled = importPlan.sheets.len > 0): resetImport()
      var rows = 0
      for s in importPlan.sheets: rows += s.dataRows
      label($importPlan.sheets.len & " sheets, " & $rows & " rows", color = ui.theme.gray)
      spring()
      if button("&Next >", isDefault = true, enabled = importPlan.sheets.len > 0):
        importStep = 1
        importSheet = 0
    for e in importPlan.errors: label(e, color = color(200, 0, 0))
    if importPlan.sheets.len == 0:
      emptyState(pxSheet, "No sheets yet", detail = "Add the Excel files you keep your staff in: " &
                 "payroll, master lists, visa trackers... as many as you like.")
      return
    colsSheets[4].choices = hotelNames() & @["(each person's own)"]
    let ev = grid(colsSheets, importPlan.sheets.len, proc (r, c: int): string =
      let s = importPlan.sheets[r]
      case c
      of 0: "Sheet"
      of 1: s.file
      of 2: s.sheet
      of 3: $s.dataRows
      of 4: (if s.hotel.len > 0: book.hotelName(s.hotel) elif s.hotelWhy.len > 0: "(from a column)"
             else: "(each person's own)")
      of 5: s.looksLike
      else: (if s.use: "1" else: "0"),
      impSel1, height = -1)
    if ev.edited and ev.row < importPlan.sheets.len:
      if ev.col == 6: importPlan.sheets[ev.row].use = ev.text == "1"
      elif ev.col == 4:
        let i = hotelNames().find(ev.text)
        importPlan.sheets[ev.row].hotel = if i >= 0: book.hotels[i].id else: ""
        importPlan.sheets[ev.row].hotelWhy = if i >= 0: "chosen" else: ""
  of 1:
    var names: seq[string]
    var idx: seq[int]
    for i, s in importPlan.sheets:
      if s.use:
        names.add s.file & (if s.sheet.len > 0: " › " & s.sheet else: "")
        idx.add i
    if idx.len == 0:
      importStep = 0
      return
    importSheet = clamp(importSheet, 0, idx.high)
    row:
      label "Sheet:"
      combo(names, importSheet, w = 300)
      let s = importPlan.sheets[idx[importSheet]]
      label("Header on row " & $(s.headerRow + 1) &
            (if s.headerRow > 0: " (above it: a title)" else: ""), color = ui.theme.gray)
      spring()
      if button("< &Back"): importStep = 0
      if importSheet < idx.high:
        if button("Next &sheet >", isDefault = true): inc importSheet
      else:
        if button("&Next >", isDefault = true):
          matchRows(book, importPlan)
          importStep = 2
    let si = idx[importSheet]
    if importPlan.sheets[si].remembered:
      discard banner("This layout was seen before: its columns are as you set them.", bkSuccess, closable = false)
    else:
      discard banner("Check the columns once: the layout is remembered for next time. Columns HR Book " &
                     "does not know become extra fields, so nothing is lost.", bkInfo, closable = false)
    colsMap[2].choices = fieldChoices()
    let ev = grid(colsMap, importPlan.sheets[si].cols.len, proc (r, c: int): string =
      let m = importPlan.sheets[si].cols[r]
      case c
      of 0: m.header
      of 1: m.samples
      of 2: choiceOfField(m.field)
      of 3: $m.sure
      else: m.why,
      impSel2, height = -1, style = proc (r, c: int): CellStyle =
        let m = importPlan.sheets[si].cols[r]
        if c == 2 and m.sure < 0.65 and m.field.len > 0: cellStyle(bg = color(255, 236, 200))
        else: CellStyle())
    if ev.edited and ev.col == 2 and ev.row < importPlan.sheets[si].cols.len:
      importPlan.sheets[si].cols[ev.row].field = fieldOfChoice(ev.text)
      importPlan.sheets[si].cols[ev.row].sure = 1.0
      importPlan.sheets[si].cols[ev.row].why = "chosen by you"
  of 2:
    var newOnes: seq[int]
    var noHotel = 0
    for i, m in importPlan.matches:
      if importPlan.isNew(i):
        newOnes.add i
        if m.use and newHotel(book, importPlan, i).len == 0: inc noHotel
    var people, values = 0
    for q in importPlan.questions:
      if q.kind == "person": inc people else: inc values
    row:
      label("Check the differences and the new people, then import.", color = ui.theme.gray)
      spring()
      if button("< &Back"): importStep = 1
      if button("&Import", isDefault = true, enabled = noHotel == 0):
        importUndo = (true, book.employees, book.fields, book.lists, book.layouts)
        importResult = apply(book, importPlan)
        staffColsSig = ""
        changed()
        importStep = 3
    kpiRow(180):
      statCard(pxCheck, "Found", $importPlan.matched, "people already here", color(30, 140, 70))
      statCard(pxNew, "New people", $newOnes.len, "to add", color(110, 74, 156))
      statCard(pxQuestion, "Same person?", $people, "check them", color(214, 162, 25))
      statCard(pxWarning, "Differences", $values, "you choose", color(197, 48, 48))
      statCard(pxRename, "Empty fields", $importPlan.fills, "will be filled", color(31, 78, 121))
    if importPlan.questions.len > 0:
      label("What differs, and the people matched by name only:", bold = true)
      let qs = importPlan.questions
      let ev = grid(colsAsk, qs.len, proc (r, c: int): string =
        let q = importPlan.questions[r]
        let m = importPlan.matches[q.match]
        case c
        of 0: (if q.kind == "person": "#E5731A" else: "#C53030")
        of 1: (if m.emp >= 0: book.employees[m.emp].name else: "")
        of 2: (if q.kind == "person": "Same person?" else: book.field(q.field).label)
        of 3: q.current
        of 4: q.incoming
        else:
          if q.kind == "person": (if q.take: "Same person" else: "Not the same")
          else: (if q.take: "Take the sheet's" else: "Keep HR Book's"),
        impSel3, height = (if newOnes.len > 0: clamp(qs.len, 2, 6) else: -1))
      if ev.edited and ev.row < importPlan.questions.len and ev.col == 5:
        importPlan.questions[ev.row].take = ev.text in ["Take the sheet's", "Same person"]
    if noHotel > 0:
      label($noHotel & " new " & (if noHotel == 1: "person needs a hotel" else: "people need their hotel") &
            ": pick it in the Hotel column, or untick Add.", color = color(200, 0, 0))
    if newOnes.len > 0:
      label("New people:", bold = true)
      colsNew[3].choices = hotelNames()
      let ev2 = grid(colsNew, newOnes.len, proc (r, c: int): string =
        let m = importPlan.matches[newOnes[r]]
        let s = importPlan.sheets[m.sheet]
        var no, nm = ""
        for ci, cm in s.cols:
          if ci < s.rows[m.row].len:
            if cm.field == "empNo": no = s.rows[m.row][ci]
            if cm.field == "nameEn" and nm.len == 0: nm = s.rows[m.row][ci]
            if cm.field == "nameAr" and nm.len == 0: nm = s.rows[m.row][ci]
        let h = newHotel(book, importPlan, newOnes[r])
        var src = s.file & (if s.sheet.len > 0: " › " & s.sheet else: "") & ", row " & $(m.row + 1)
        for o in importPlan.matches:
          if o.sameAs == newOnes[r]:
            src.add " + " & importPlan.sheets[o.sheet].file & ", row " & $(o.row + 1)
        case c
        of 0: (if m.use: "1" else: "0")
        of 1: no
        of 2: nm
        of 3: (if h.len > 0: book.hotelName(h) else: "(choose)")
        else: src,
        impSel4, height = clamp(newOnes.len, 2, 10))
      if ev2.edited and ev2.col == 0 and ev2.row < newOnes.len:
        importPlan.matches[newOnes[ev2.row]].use = ev2.text == "1"
      if ev2.edited and ev2.col == 3 and ev2.row < newOnes.len:
        let i = hotelNames().find(ev2.text)
        if i >= 0: importPlan.matches[newOnes[ev2.row]].hotel = book.hotels[i].id
  else:
    let r = importResult
    discard banner("Import done: " & $r.updated & " employees updated, " & $r.added & " added, " &
                   $r.filled & " empty fields filled, " & $r.changed & " values changed" &
                   (if r.newFields == 1: ", 1 new field" elif r.newFields > 1: ", " & $r.newFields & " new fields" else: "") & ".",
                   bkSuccess, closable = false)
    row:
      if button("&Undo the import", enabled = importUndo.on):
        book.employees = importUndo.emps
        book.fields = importUndo.fields
        book.lists = importUndo.lists
        book.layouts = importUndo.layouts
        importUndo.on = false
        staffColsSig = ""
        changed()
        status = "The import was undone."
      if button("&Import more"): resetImport()
      if button("See the &employees"):
        section = "Employees/All hotels"
        current = -1
    if r.newNames.len > 0:
      label("New fields: " & r.newNames.join(", ") & ". Rename or move them in Settings > Fields.",
            color = ui.theme.gray)
    card("Remembered layouts"):
      var facts: seq[(string, string)]
      for l in book.layouts: facts.add (l.name, "used " & $l.used & (if l.used == 1: " time" else: " times"))
      factList(facts)

proc importDialogs() =
  if filePicker(importPickOpen, importPick, fmOpen, ["*.xlsx", "*.xlsm", "*.csv", "*.xls", "*.txt"],
                "Add Excel or CSV files"):
    for s in importPlan.sheets:
      if s.file == importPick.extractFilename:
        toast(importPick.extractFilename & " is already in the list", glyph = pxInfo)
        return
    var p = newPlan(book, @[importPick])
    for s in p.sheets: importPlan.sheets.add s
    for e in p.errors: importPlan.errors.add e
    importStep = 0
