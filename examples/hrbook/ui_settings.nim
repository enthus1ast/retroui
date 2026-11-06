# (included by hrbook.nim) Settings: hotels, fields, allowances, lists,
# groups, security and backups, look.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

var
  hotelSel = 0
  picKind = ""                 ## which picture is being chosen
  picOpen = false
  picPath = ""
  picCache: Table[string, Bitmap]
  fieldSel = 0
  colsFields = @[column("Field", 170, editable = true), column("Arabic", 140, editable = true),
                 choiceColumn("Section", ["Personal", "Job", "Salary", "Documents", "Other"], 100),
                 choiceColumn("Kind", ["text", "number", "money", "date", "choice", "yesno", "longtext", "hotel"], 90),
                 checkColumn("In the list", 70), checkColumn("In total", 66),
                 checkColumn("Expiry", 60), checkColumn("Hidden", 60)]
  addFieldOpen = false
  newFieldLabel = ""
  newFieldAr = ""
  newFieldSection = 4
  newFieldKind = 0
  askDeleteField = false
  allowSel = 0
  colsAllow = @[column("Allowance", 200, editable = true), column("Arabic", 170, editable = true),
                checkColumn("In the total", 90), checkColumn("Hidden", 60)]
  addAllowOpen = false
  newAllow = ""
  listSel = 0
  listItemSel = 0
  listEdit = ""
  colsList = @[column("Value", 240), column("In Arabic", 240, editable = true)]
  groupSel = 0
  colsGroups = @[column("Group", 200, editable = true),
                 choiceColumn("Colour", ["Orange", "Red", "Green", "Blue", "Purple", "Gold", "Teal", "Gray"], 100),
                 numberColumn("People", 70)]
  # security and backups
  pinDlgOpen = false
  pinOld, pinNew, pinNew2, pinDlgMsg = ""
  backupDoneOpen = false
  backupPath = ""
  restorePickOpen = false
  restorePath = ""
  restorePinOpen2 = false
  restorePin = ""
  restoreMsg = ""
  restoreBook: Book
  restoreDiff: Diff
  restoreCompareOpen = false
  restoreTake: seq[bool]
  askReplace = false
  colsDiff = @[colorColumn("", 26), column("Employee", 190), column("What", 120),
               column("Fields that differ", 230), choiceColumn("Choice", ["Take the backup's", "Keep this one's"], 140)]
  diffSel = 0

const groupColors = [("Orange", "#e5731a"), ("Red", "#c53030"), ("Green", "#2e8b57"), ("Blue", "#1f4e79"),
                     ("Purple", "#6e4a9c"), ("Gold", "#d6a219"), ("Teal", "#178c96"), ("Gray", "#787878")]

proc colorName(hex: string): string =
  for (n, h) in groupColors:
    if cmpIgnoreCase(h, hex) == 0: return n
  "Gray"

proc picOf(png: string): Bitmap =
  if png.len == 0: return nil
  let k = $png.len & png[0 ..< min(64, png.len)] & png[max(0, png.len - 64) .. ^1]
  if picCache.hasKey(k): return picCache[k]
  result = try: decodePng(decode(png)) except CatchableError: nil
  if picCache.len > 32: picCache.clear()
  picCache[k] = result

proc pictureRow(title, detail: string; png: string; kind: string): bool =
  ## A picture setting: its preview, Choose and Remove; true when removed.
  row:
    col(170):
      label(title, bold = true)
      label(detail, color = ui.theme.gray)
    let r = canvas(dp(120), dp(64))
    fill(r, color(255, 255, 255))
    box(r, ui.theme.shadow)
    let b = picOf(png)
    if b != nil and b.w > 0 and b.h > 0:
      let s = min((r.w - 4) / b.w, (r.h - 4) / b.h)
      let w = int(float(b.w) * s)
      let h = int(float(b.h) * s)
      drawBitmap(rect(r.x + (r.w - w) div 2, r.y + (r.h - h) div 2, w, h), b)
    else:
      text(r.x + dp(8), r.y + (r.h - FontH) div 2, "(none)", ui.theme.gray)
    col:
      if button("Choose...", w = 100) and filesOk():
        picKind = kind
        if picPath.len == 0: picPath = downloadsDir()
        picOpen = true
      if button("Remove", w = 100, enabled = png.len > 0): result = true

proc hotelsPage() =
  heading("Hotels", 2)
  if book.hotels.len == 0:
    if button("&Add a hotel"):
      book.hotels.add Hotel(id: newId("h-"), name: "New hotel", color: "#1f4e79", modified: nowT())
      changed()
    return
  hotelSel = clamp(hotelSel, 0, book.hotels.high)
  row:
    label "Hotel:"
    combo(hotelNames(), hotelSel, w = 240)
    if button("&Add a hotel"):
      book.hotels.add Hotel(id: newId("h-"), name: "New hotel", code: "NEW", color: "#1f4e79",
                            refPrefix: "NEW/HR", modified: nowT())
      hotelSel = book.hotels.high
      changed()
    var used = 0
    for e in book.employees:
      if not e.deleted and e.get("hotel") == book.hotels[hotelSel].id: inc used
    if button("Delete", enabled = used == 0 and book.hotels.len > 1):
      book.hotels.delete(hotelSel)
      hotelSel = 0
      changed()
    if used > 0: label($used & " employees: it cannot be deleted", color = ui.theme.gray)
  var h = addr book.hotels[hotelSel]
  var ch = false
  adaptive(400):
    card("Name and numbers"):
      form 0:
        field "Name:": ch = edit(h.name) or ch
        field "Arabic name:": ch = edit(h.nameAr) or ch
        field "Short code:": ch = edit(h.code) or ch
        field "C.R. No.:": ch = edit(h.cr) or ch
        field "VAT No.:": ch = edit(h.vat) or ch
        field "Letter numbers:": ch = edit(h.refPrefix) or ch
      label("Letters are numbered " & nextRefNo(h[]), color = ui.theme.gray)
    card("Address and contact"):
      form 0:
        field "Address:": ch = edit(h.address) or ch
        field "Arabic address:": ch = edit(h.addressAr) or ch
        field "Phone:": ch = edit(h.phone) or ch
        field "Email:": ch = edit(h.email) or ch
        field "Website:": ch = edit(h.website) or ch
        field "Colour:": ch = edit(h.color) or ch
    card("Who signs the letters"):
      form 0:
        field "Name:": ch = edit(h.signer) or ch
        field "Title:": ch = edit(h.signerTitle) or ch
        field "Arabic name:": ch = edit(h.signerAr) or ch
        field "Arabic title:": ch = edit(h.signerTitleAr) or ch
    card("Pictures for the letters"):
      if pictureRow("Logo", "Top of the letters", h.logo, "logo"): h.logo = ""; ch = true
      if pictureRow("Letterhead", "A whole A4 page (it replaces the logo and the header)",
                    h.letterhead, "letterhead"): h.letterhead = ""; ch = true
      if pictureRow("Signature", "Above the signer's name", h.signature, "signature"): h.signature = ""; ch = true
      if pictureRow("Stamp", "Beside the signature", h.stamp, "stamp"): h.stamp = ""; ch = true
  if ch:
    h.modified = nowT()
    changed()

proc fieldsPage() =
  row:
    heading("Fields", 2)
    spring()
    if button("&Add a field..."):
      newFieldLabel = ""
      newFieldAr = ""
      addFieldOpen = true
      focusFirstText()
    let f = if fieldSel < book.fields.len: book.fields[fieldSel] else: FieldDef()
    if button("Move &up", enabled = fieldSel > 0):
      swap(book.fields[fieldSel], book.fields[fieldSel - 1])
      dec fieldSel
      staffColsSig = ""
      changed()
    if button("Move dow&n", enabled = fieldSel < book.fields.high):
      swap(book.fields[fieldSel], book.fields[fieldSel + 1])
      inc fieldSel
      staffColsSig = ""
      changed()
    if button("&Delete...", enabled = not f.builtin and f.key.len > 0): askDeleteField = true
  paragraph("Rename any field, choose where it shows, add your own. Built-in fields can be hidden; " &
            "the ones you add can also be deleted. Every field is a #[tag]# for letters.",
            color = ui.theme.gray)
  let ev = grid(colsFields, book.fields.len, proc (r, c: int): string =
    let f = book.fields[r]
    case c
    of 0: f.label
    of 1: f.labelAr
    of 2: $f.section
    of 3: $f.kind
    of 4: (if f.inList: "1" else: "0")
    of 5: (if f.kind == fkMoney: (if f.inTotal: "1" else: "0") else: "")
    of 6: (if f.kind == fkDate: (if f.expiry: "1" else: "0") else: "")
    else: (if f.hidden: "1" else: "0"),
    fieldSel, height = -1, style = proc (r, c: int): CellStyle =
      if book.fields[r].builtin and c == 3: cellStyle(fg = color(128, 128, 128))
      elif book.fields[r].hidden: cellStyle(fg = color(128, 128, 128))
      else: CellStyle())
  if ev.edited and ev.row < book.fields.len:
    var f = addr book.fields[ev.row]
    case ev.col
    of 0: (if ev.text.strip.len > 0: f.label = ev.text.strip)
    of 1: f.labelAr = ev.text.strip
    of 2:
      for s in Section:
        if $s == ev.text: f.section = s
    of 3:
      if not f.builtin:
        for k in FieldKind:
          if $k == ev.text: f.kind = k
        if f.kind == fkChoice and f.list.len == 0:
          f.list = "list-" & f.key
          if not book.lists.hasKey(f.list): book.lists[f.list] = @[]
    of 4: f.inList = ev.text == "1"
    of 5: (if f.kind == fkMoney: f.inTotal = ev.text == "1")
    of 6: (if f.kind == fkDate: f.expiry = ev.text == "1")
    else: f.hidden = ev.text == "1"
    f.modified = nowT()
    staffColsSig = ""
    changed()

proc allowancesPage() =
  row:
    heading("Salary and allowances", 2)
    spring()
    if button("&Add an allowance..."):
      newAllow = ""
      addAllowOpen = true
      focusFirstText()
  paragraph("The amounts of the salary. Those \"in the total\" make the total salary " &
            "(#[Total Salary]# in letters). Add allowances as you need them: phone, food, shift...",
            color = ui.theme.gray)
  var idx: seq[int]
  for i, f in book.fields:
    if f.kind == fkMoney: idx.add i
  let ev = grid(colsAllow, idx.len, proc (r, c: int): string =
    let f = book.fields[idx[r]]
    case c
    of 0: f.label
    of 1: f.labelAr
    of 2: (if f.inTotal: "1" else: "0")
    else: (if f.hidden: "1" else: "0"),
    allowSel, height = -1)
  if ev.edited and ev.row < idx.len:
    var f = addr book.fields[idx[ev.row]]
    case ev.col
    of 0: (if ev.text.strip.len > 0: f.label = ev.text.strip)
    of 1: f.labelAr = ev.text.strip
    of 2: f.inTotal = ev.text == "1"
    else: f.hidden = ev.text == "1"
    f.modified = nowT()
    staffColsSig = ""
    changed()

proc listsPage() =
  heading("Lists", 2)
  paragraph("The choices of the fields that pick from a list. New values from imports and " &
            "forms are added here by themselves. Their Arabic is what Arabic letters say " &
            "(a field's Arabic tag, as #[الجنسية]#, gives \"عماني\" for Omani).",
            color = ui.theme.gray)
  var keys: seq[string]
  var titles: seq[string]
  for k in book.lists.keys:
    keys.add k
    let i = ListNames.find(k)
    if i >= 0: titles.add ListTitles[i]
    else:
      var t = k
      for f in book.fields:
        if f.list == k: t = f.label
      titles.add t
  listSel = clamp(listSel, 0, max(0, keys.high))
  if keys.len == 0: return
  row:
    label "List:"
    if combo(titles, listSel, w = 220): listItemSel = 0
  let key = keys[listSel]
  var items = book.lists[key]
  listItemSel = clamp(listItemSel, 0, max(0, items.high))
  row([-1, 220]):
    let ev = grid(colsList, items.len, proc (r, c: int): string =
      if c == 0: items[r] else: book.arabic.getOrDefault(items[r]),
      listItemSel, height = -1)
    if ev.edited and ev.col == 1 and ev.row < items.len:
      if ev.text.strip.len > 0: book.arabic[items[ev.row]] = ev.text.strip
      else: book.arabic.del(items[ev.row])
      changed()
    col:
      edit(listEdit)
      if button("&Add", w = 200, enabled = listEdit.strip.len > 0 and listEdit.strip notin items):
        items.add listEdit.strip
        listEdit = ""
        book.lists[key] = items
        changed()
      if button("&Rename to it", w = 200, enabled = items.len > 0 and listEdit.strip.len > 0):
        let old = items[listItemSel]
        items[listItemSel] = listEdit.strip
        book.lists[key] = items
        # the people who had the old value get the new one
        for f in book.fields:
          if f.list == key:
            for e in book.employees.mitems:
              if e.get(f.key) == old: e.setValue(f.key, listEdit.strip, "list renamed")
        listEdit = ""
        changed()
      if button("Re&move", w = 200, enabled = items.len > 0):
        items.delete(listItemSel)
        book.lists[key] = items
        changed()
      if button("Move &up", w = 200, enabled = listItemSel > 0):
        swap(items[listItemSel], items[listItemSel - 1])
        dec listItemSel
        book.lists[key] = items
        changed()
      if button("Sort A-&Z", w = 200, enabled = items.len > 1):
        items.sort()
        book.lists[key] = items
        changed()

proc groupsPage() =
  row:
    heading("Groups", 2)
    spring()
    if button("&Add a group"):
      book.groups.add Group(id: newId("g-"), name: "New group", color: "#e5731a", modified: nowT())
      groupSel = book.groups.high
      changed()
    if button("&Delete", enabled = book.groups.len > 0):
      let gid = book.groups[groupSel].id
      book.groups.delete(groupSel)
      for e in book.employees.mitems:
        let k = e.groups.find(gid)
        if k >= 0:
          e.groups.delete(k)
          e.modified = nowT()
      groupSel = 0
      changed()
  paragraph("Mark people with groups of your own (probation, training, night shift...): they show " &
            "as coloured tags in the list and on their page, and each group has its place under " &
            "Employees. Put people in groups in their form (Groups tab).", color = ui.theme.gray)
  if book.groups.len == 0: return
  let ev = grid(colsGroups, book.groups.len, proc (r, c: int): string =
    let g = book.groups[r]
    case c
    of 0: g.name
    of 1: colorName(g.color)
    else:
      var n = 0
      for e in book.employees:
        if not e.deleted and g.id in e.groups: inc n
      $n,
    groupSel, height = -1)
  if ev.edited and ev.row < book.groups.len:
    case ev.col
    of 0: (if ev.text.strip.len > 0: book.groups[ev.row].name = ev.text.strip)
    of 1:
      for (n, hx) in groupColors:
        if n == ev.text: book.groups[ev.row].color = hx
    else: discard
    book.groups[ev.row].modified = nowT()
    changed()

proc backupNow() =
  if not filesOk(): return
  backupPath = downloadsDir() / "HR Book" / backupName()
  try:
    writeBackup(st, book, backupPath)
    book.lastBackup = nowT()
    changed()
    backupDoneOpen = true
  except IOError, OSError:
    backupPath = dir / "backups" / backupName()
    try:
      writeBackup(st, book, backupPath)
      book.lastBackup = nowT()
      changed()
      backupDoneOpen = true
    except IOError, OSError: toast("Could not write the backup", glyph = pxError)

proc startRestore() =
  if not filesOk(): return
  if restorePath.len == 0: restorePath = downloadsDir() / "HR Book"
  if not dirExists(restorePath): restorePath = downloadsDir()
  restorePickOpen = true

proc securityPage() =
  heading("Security and backup", 2)
  adaptive(420):
    col:
      group("Security"):
        if settingButtons("PIN", ["Change..."], "It opens HR Book and seals its data and backups") == 1:
          pinOld = ""
          pinNew = ""
          pinNew2 = ""
          pinDlgMsg = ""
          pinDlgOpen = true
          focusFirstText()
        const mins = [1, 2, 5, 10, 30]
        var li = max(0, mins.find(book.lockMinutes))
        if settingCombo("Lock after", ["1 minute", "2 minutes", "5 minutes", "10 minutes", "30 minutes"],
                        li, "Of not being used, and in the background"):
          book.lockMinutes = mins[li]
          changed()
        if settingToggle("Hide salaries", book.hideSalaries, "In the lists, the pages and the charts"):
          changed()
          staffColsSig = ""
      group("This device"):
        let size = try: getFileSize(dataFile(dir)) except OSError: 0'i64
        factList({"Data file": dataFile(dir), "Size": $(size div 1024) & " KB, sealed with the PIN",
                  "Copies kept": "the last 3 versions, beside it",
                  "Internet": "none: HR Book has no internet permission"})
    col:
      group("Backups"):
        let last = if book.lastBackup > 0: fromUnix(int64(book.lastBackup)).local.format("dd/MM/yyyy HH:mm") else: "never"
        if settingButtons("Back up now", ["Back up..."], "Last: " & last & ". One file, sealed with the PIN: " &
                          "copy it to another tablet or keep it safe") == 1: backupNow()
        if settingButtons("Restore or merge", ["Choose..."],
                          "Open a backup: see what is new in it, then merge it with what is here or " &
                          "replace everything") == 1: startRestore()

proc lookPage() =
  heading("Look", 2)
  col(560):
    group("Look"):
      discard appearanceSettings()
    group("About"):
      factList({"HR Book": AppVersion, "Made with": "Retro Nim UI " & RetroVersion,
                "Encryption": "Monocypher (XChaCha20-Poly1305, Argon2id)"})

proc settingsPage() =
  case section
  of "Settings/Fields": fieldsPage()
  of "Settings/Allowances": allowancesPage()
  of "Settings/Lists": listsPage()
  of "Settings/Groups": groupsPage()
  of "Settings/Security and backup": securityPage()
  of "Settings/Look": lookPage()
  else: hotelsPage()

proc settingsDialogs() =
  # a picture for a hotel
  if filePicker(picOpen, picPath, fmOpen, ["*.png", "*.jpg", "*.jpeg", "*.bmp"], "Choose a picture"):
    let (mw, mh) = case picKind
                   of "letterhead": (1240, 1754)
                   of "logo": (600, 600)
                   of "stamp": (500, 500)
                   else: (700, 300)
    let b = loadPicture(picPath, mw, mh)
    if b == nil or b.w == 0: toast("Not a picture HR Book can read", glyph = pxError)
    elif hotelSel < book.hotels.len:
      let data = encode(encodePng(b))
      case picKind
      of "logo": book.hotels[hotelSel].logo = data
      of "letterhead": book.hotels[hotelSel].letterhead = data
      of "signature": book.hotels[hotelSel].signature = data
      of "stamp": book.hotels[hotelSel].stamp = data
      else: discard
      book.hotels[hotelSel].modified = nowT()
      changed()
  # a new field
  if addFieldOpen:
    dialog(addFieldOpen, "Add a field", 440):
      form 0:
        field "Name:": edit(newFieldLabel)
        field "Arabic name:": edit(newFieldAr)
        field "Section:": combo(["Personal", "Job", "Salary", "Documents", "Other"], newFieldSection)
        field "Kind:": combo(["Text", "Number", "Money", "Date", "Choice from a list", "Yes / No", "Long text"],
                             newFieldKind)
      row:
        spring()
        if button("&Add", isDefault = true, enabled = newFieldLabel.strip.len > 0):
          let kind = [fkLine, fkNumber, fkMoney, fkDate, fkChoice, fkYesNo, fkLongText][newFieldKind]
          var f = FieldDef(key: newId("f_"), label: newFieldLabel.strip, labelAr: newFieldAr.strip,
                           kind: kind, section: Section(newFieldSection), modified: nowT(),
                           inTotal: kind == fkMoney and newFieldSection == 2,
                           expiry: kind == fkDate and newFieldSection == 3)
          if kind == fkChoice:
            f.list = "list-" & f.key
            book.lists[f.list] = @[]
          book.fields.add f
          fieldSel = book.fields.high
          staffColsSig = ""
          changed()
          addFieldOpen = false
        if button("Cancel"): addFieldOpen = false
  if addAllowOpen:
    dialog(addAllowOpen, "Add an allowance", 400):
      form 0:
        field "Name:": edit(newAllow)
      row:
        spring()
        if button("&Add", isDefault = true, enabled = newAllow.strip.len > 0):
          var name = newAllow.strip
          if "allowance" notin name.toLowerAscii: name.add " Allowance"
          book.fields.add FieldDef(key: newId("f_"), label: name, kind: fkMoney, section: secSalary,
                                   inTotal: true, modified: nowT())
          staffColsSig = ""
          changed()
          addAllowOpen = false
        if button("Cancel"): addAllowOpen = false
  case msgBox(askDeleteField, AppTitle, "Delete the field \"" &
              (if fieldSel < book.fields.len: book.fields[fieldSel].label else: "") &
              "\" and its values in every record?", ["&Delete", "Cancel"], miWarning)
  of 1:
    if fieldSel < book.fields.len and not book.fields[fieldSel].builtin:
      let k = book.fields[fieldSel].key
      book.fields.delete(fieldSel)
      for e in book.employees.mitems:
        if e.v.hasKey(k):
          e.v.del(k)
          e.modified = nowT()
      fieldSel = 0
      staffColsSig = ""
      changed()
  else: discard
  # the PIN
  if pinDlgOpen:
    dialog(pinDlgOpen, "Change the PIN", 380):
      form 0:
        field "Current PIN:": edit(pinOld, password = true)
        field "New PIN:": edit(pinNew, password = true)
        field "Again:": edit(pinNew2, password = true)
      if pinDlgMsg.len > 0: label(pinDlgMsg, color = color(200, 0, 0))
      row:
        spring()
        if button("&Change", isDefault = true):
          var ok = false
          try:
            discard open(dir, pinOld)
            ok = true
          except VaultError, IOError, OSError: pinDlgMsg = "The current PIN is wrong."
          if ok:
            if pinNew.len < 4 or not pinNew.allCharsInSet({'0'..'9'}): pinDlgMsg = "The new PIN is 4 digits or more."
            elif pinNew != pinNew2: pinDlgMsg = "The two new PINs are not the same."
            else:
              try:
                st.changePin(book, pinNew)
                pinDlgOpen = false
                toast("The PIN is changed. Old backups keep their old PIN.", glyph = pxCheck)
              except IOError, OSError, VaultError: pinDlgMsg = "Could not save."
        if button("Cancel"): pinDlgOpen = false
  # a backup written
  if backupDoneOpen:
    dialog(backupDoneOpen, "Backup saved", 460):
      row:
        icon(pxCheck, size = 2.0)
        col:
          label("Saved: " & backupPath.extractFilename, bold = true)
          paragraph("In " & backupPath.parentDir & ". Copy this file to the other tablet " &
                    "(or keep it safe); it opens there with the same PIN.", color = ui.theme.gray)
      row:
        spring()
        if button("S&hare..."):
          if not shareFile(backupPath): toast("Sharing is not available here", glyph = pxInfo)
        if button("OK", isDefault = true): backupDoneOpen = false
  # restoring
  if filePicker(restorePickOpen, restorePath, fmOpen, ["*.hrbook", "*"], "Choose a backup"):
    restorePin = ""
    restoreMsg = ""
    restorePinOpen2 = true
    focusFirstText()
  if restorePinOpen2:
    dialog(restorePinOpen2, "Open the backup", 380):
      label(restorePath.extractFilename, bold = true)
      label("The PIN it was made with:")
      edit(restorePin, password = true)
      if restoreMsg.len > 0: label(restoreMsg, color = color(200, 0, 0))
      row:
        spring()
        if button("&Open", isDefault = true, enabled = restorePin.len > 0):
          try:
            restoreBook = readBackup(restorePath, restorePin)
            restoreDiff = compare(book, restoreBook)
            restoreTake = newSeq[bool](restoreDiff.emps.len)
            restorePinOpen2 = false
            restoreCompareOpen = true
          except VaultError: restoreMsg = "Wrong PIN, or not an HR Book backup."
          except IOError, OSError: restoreMsg = "Could not read it."
        if button("Cancel"): restorePinOpen2 = false
  if restoreCompareOpen:
    let d = restoreDiff
    dialog(restoreCompareOpen, "What the backup has", 900):
      let saved = if d.info.savedAt > 0: fromUnix(int64(d.info.savedAt)).local.format("dd/MM/yyyy HH:mm") else: "?"
      let here = if book.savedAt > 0: fromUnix(int64(book.savedAt)).local.format("dd/MM/yyyy HH:mm") else: "?"
      label("Backup saved " & saved & (if d.info.device == book.device: " on this tablet" else: " on another tablet") &
            " -- here last saved " & here, bold = true)
      # the answer first: is there anything new in it?
      let fresh = d.newCount + d.newerCount + d.removedCount + d.hotelsChanged + d.fieldsNew +
                  d.templatesNew + d.groupsNew
      let theirs = $d.newCount & (if d.newCount == 1: " new person" else: " new people") & " and " &
                   $(d.newerCount + d.removedCount) & (if d.newerCount + d.removedCount == 1: " change" else: " changes")
      if fresh == 0:
        discard banner("Nothing new: everything in this backup is already here" &
                       (if d.olderCount + d.onlyHere > 0: " (this tablet has newer things)." else: "."),
                       bkSuccess, closable = false)
      elif d.olderCount == 0 and d.onlyHere == 0:
        discard banner("The backup is newer: " & theirs & " that this tablet does not have. " &
                       "Merge brings them in.", bkInfo, closable = false)
      else:
        discard banner("Both have news: the backup has " & theirs & "; this tablet has " &
                       $(d.olderCount + d.onlyHere) & " of its own. Merge keeps the newer of each " &
                       "(you can choose below); nothing here is lost.", bkWarning, closable = false)
      kpiRow(150):
        statCard(pxNew, "New people", $d.newCount, "only there", color(110, 74, 156))
        statCard(pxRefresh, "Newer there", $d.newerCount, "changed there", color(31, 78, 121))
        statCard(pxClock, "Newer here", $d.olderCount, "changed here", color(214, 162, 25))
        statCard(pxTrash, "Removed there", $d.removedCount, "deleted there", color(197, 48, 48))
        statCard(pxCheck, "The same", $d.sameCount, $d.onlyHere & " only here", color(30, 140, 70))
      var notes: seq[string]
      if d.hotelsChanged > 0: notes.add $d.hotelsChanged & " hotel(s) changed"
      if d.fieldsNew > 0: notes.add $d.fieldsNew & " new field(s)"
      if d.templatesNew > 0: notes.add $d.templatesNew & " new letter template(s)"
      if d.groupsNew > 0: notes.add $d.groupsNew & " new group(s)"
      if notes.len > 0: label("Also: " & notes.join(", ") & ".", color = ui.theme.gray)
      var rows: seq[int]
      for i, x in d.emps:
        if x.kind != "same": rows.add i
      if rows.len > 0:
        let ev = grid(colsDiff, rows.len, proc (r, c: int): string =
          let x = d.emps[rows[r]]
          let e = restoreBook.employees[x.bak]
          case c
          of 0: (case x.kind
                 of "new": "#6e4a9c"
                 of "newer": "#1f4e79"
                 of "removed": "#c53030"
                 else: "#d6a219")
          of 1: e.name
          of 2: (case x.kind
                 of "new": "New"
                 of "newer": "Newer there"
                 of "removed": "Removed there"
                 else: "Newer here")
          of 3:
            var ls: seq[string]
            for k in x.fields:
              ls.add(if k == "groups": "Groups" else: book.field(k).label)
            ls.join(", ")
          else:
            if x.kind == "older": (if restoreTake[rows[r]]: "Take the backup's" else: "Keep this one's")
            else: "Take the backup's",
          diffSel, height = min(10, rows.len + 1))
        if ev.edited and ev.col == 4 and ev.row < rows.len:
          restoreTake[rows[ev.row]] = ev.text == "Take the backup's"
      row:
        if button("&Merge", isDefault = true):
          merge(book, restoreBook, restoreDiff, restoreTake)
          staffColsSig = ""
          changed()
          flushSave()
          restoreCompareOpen = false
          toast("Merged: the newest of each is kept", glyph = pxCheck)
        if button("&Replace everything..."): askReplace = true
        spring()
        if button("Cancel"): restoreCompareOpen = false
  case msgBox(askReplace, AppTitle, "Replace everything here with the backup? What was changed " &
              "here since is lost (the last copies of the data file are kept).", ["&Replace", "Cancel"], miWarning)
  of 1:
    replaceWith(book, restoreBook)
    staffColsSig = ""
    changed()
    flushSave()
    restoreCompareOpen = false
    current = -1
    toast("Everything is as in the backup", glyph = pxCheck)
  else: discard
