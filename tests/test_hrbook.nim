## Tests of HR Book's engine (examples/hrbook), headless: its data, the
## sealed store and its PIN, the smart import of Excel sheets
## (tests/data/hrbook: invented people, fake numbers), backups merged from
## another tablet, and letters.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, tables, strutils]
import retroui/[vault, report]
import ../examples/hrbook/[model, store, importer, letters]

let data = currentSourcePath().parentDir / "data" / "hrbook"
let tmp = getTempDir() / "hrbook-test-" & $getCurrentProcessId()
removeDir(tmp)
createDir(tmp)

proc byNo(b: Book; no: string): int =
  for i, e in b.employees:
    if e.get("empNo") == no: return i
  -1

var book = newBook(["Sohar Hotel", "Muscat Hotel", "Salalah Resort"])

block importPayroll:
  var plan = newPlan(book, @[data / "payroll.xlsx"])
  doAssert plan.errors.len == 0, $plan.errors
  doAssert plan.sheets.len == 1
  let s = plan.sheets[0]
  doAssert s.headerRow == 2, "the header row under the title: " & $s.headerRow
  var got = initTable[string, string]()
  for c in s.cols: got[c.header] = c.field
  doAssert got["S.No"] == "", "the row counter is skipped: " & got["S.No"]
  doAssert got["Staff No"] == "empNo"
  doAssert got["Employee Name"] == "nameEn"
  doAssert got["Designation"] == "position"
  doAssert got["Dept"] == "department"
  doAssert got["DOJ"] == "joined"
  doAssert got["Basic"] == "basic"
  doAssert got["HRA"] == "housing"
  doAssert got["Transport"] == "transport"
  doAssert got["Remarks"] == "notes"
  doAssert s.hotel == book.hotels[0].id, "the hotel from the sheet's name: " & s.hotelWhy
  doAssert s.looksLike == "Payroll"
  matchRows(book, plan)
  doAssert plan.newPeople == 4, "4 people (the total row is left out): " & $plan.newPeople
  let r = apply(book, plan)
  doAssert r.added == 4
  let i = book.byNo("SOH-1002")
  doAssert i >= 0
  let e = book.employees[i]
  doAssert e.get("nameEn") == "Rajesh Kumar Nair"
  doAssert e.get("joined") == "2019-06-15", e.get("joined")
  doAssert e.get("basic") == "380"
  doAssert e.get("hotel") == book.hotels[0].id
  doAssert e.get("notes") == "renewal applied"
  doAssert book.totalSalary(e) == 485
  doAssert e.history.len > 3 and e.history[0].source == "payroll.xlsx › Sohar"
  doAssert book.layouts.len == 1

block importVisa:
  var plan = newPlan(book, @[data / "visa.xlsx"])
  let s = plan.sheets[0]
  var got = initTable[string, string]()
  for c in s.cols: got[c.header] = c.field
  doAssert got["Emp ID"] == "empNo"
  doAssert got["Passport #"] == "passportNo"
  doAssert got["PP Exp."] == "passportExpiry", got["PP Exp."]
  doAssert got["Visa Exp"] == "visaExpiry"
  doAssert got["Visa Under"] == "visaUnder"
  doAssert got["Mob."] == "phone"
  for c in s.cols:
    if c.header == "Mob.":
      doAssert c.sure >= 0.9, "numbers written after +968 or 00968 are phones: " & c.why
  matchRows(book, plan)
  doAssert plan.matched == 2, "Rajesh and Maria by their numbers without SOH-: " & $plan.matched
  doAssert plan.newPeople == 1, "Bikash is new"
  doAssert plan.matches[0].how.startsWith("employee no."), plan.matches[0].how
  discard apply(book, plan)
  let i = book.byNo("SOH-1002")
  let e = book.employees[i]
  doAssert e.get("visaExpiry") == "2026-11-12"
  doAssert e.get("passportNo") == "X0000002" and e.get("phone") == "+968 0000 0102"
  doAssert e.get("visaUnder") == book.hotels[1].id, "a hotel's name becomes the hotel"
  doAssert e.otherVisa, "works at Sohar, on Muscat's visa"
  doAssert not book.employees[book.byNo("SOH-1003")].otherVisa

block importAgain:
  # the same payroll with a new basic: one difference, asked
  var plan = newPlan(book, @[data / "payroll.xlsx"])
  doAssert plan.sheets[0].remembered, "the layout is remembered"
  let i = book.byNo("SOH-1003")
  book.employees[i].setValue("basic", "340", "test")
  matchRows(book, plan)
  doAssert plan.newPeople == 0 and plan.matched == 4
  var q = -1
  for k, x in plan.questions:
    if x.kind == "value" and x.field == "basic": q = k
  doAssert q >= 0, "the changed salary is asked"
  plan.questions[q].take = false       # keep 340
  discard apply(book, plan)
  doAssert book.employees[i].get("basic") == "340"

block storeAndPin:
  var s = create(tmp, "246810", book)
  doAssert hasData(tmp)
  doAssert "Rajesh" notin readFile(dataFile(tmp)), "the file is sealed"
  var wrong = false
  try: discard open(tmp, "111111")
  except VaultError: wrong = true
  doAssert wrong
  let (s2, b2) = open(tmp, "246810")
  doAssert s2.opened and b2.employees.len == book.employees.len
  doAssert b2.employees[0].v == book.employees[0].v
  doAssert b2.hotels[1].name == "Muscat Hotel"
  doAssert b2.fields.len == book.fields.len

block backupMerge:
  var s = create(tmp, "246810", book)
  let bak = tmp / "test.hrbook"
  writeBackup(s, book, bak)
  # here: one change; in the backup (another tablet): another change and a new person
  var other = readBackup(bak, "246810")
  let i = book.byNo("SOH-1001")
  book.employees[i].setValue("phone", "+968 0000 0001", "here", nowT() + 1)
  let j = other.byNo("SOH-1004")
  other.employees[j].setValue("basic", "500", "there", nowT() + 2)
  var n = newEmployee()
  n.v["empNo"] = "SOH-1099"
  n.v["nameEn"] = "New Person"
  other.employees.add n
  writeBackup(s, other, bak)
  let back = readBackup(bak, "246810")
  let d = compare(book, back)
  doAssert d.newCount == 1 and d.newerCount == 1 and d.olderCount == 1, $d.newCount & " " & $d.newerCount & " " & $d.olderCount
  merge(book, back, d)
  doAssert book.byNo("SOH-1099") >= 0
  doAssert book.employees[book.byNo("SOH-1004")].get("basic") == "500"
  doAssert book.employees[i].get("phone") == "+968 0000 0001", "the newer one here stays"

block arabicHeadersAndAllowance:
  var plan = newPlan(book, @[data / "muscat-arabic.xlsx"])
  let s = plan.sheets[0]
  doAssert s.hotel == book.hotels[1].id, "the hotel from the title row"
  var got = initTable[string, string]()
  for c in s.cols: got[c.header] = c.field
  doAssert got["رقم الموظف"] == "empNo"
  doAssert got["الأساسي"] == "basic"
  doAssert got["بدل السكن"] == "housing"
  doAssert got["Phone Allowance"] == "+$", "an allowance not known yet: " & got["Phone Allowance"]
  doAssert got["Shoe Size"] == "+"
  matchRows(book, plan)
  let before = book.fields.len
  let r = apply(book, plan)
  doAssert r.newFields == 2 and book.fields.len == before + 2
  let pa = book.fields[before]
  doAssert pa.label == "Phone Allowance" and pa.kind == fkMoney and pa.inTotal and pa.section == secSalary
  doAssert pa.labelAr == "بدل هاتف", "its Arabic name, for Arabic letters: " & pa.labelAr
  doAssert allowanceNames("بدل الهاتف") == ("Phone Allowance", "بدل الهاتف")
  doAssert allowanceNames("Food allow.").ar == "بدل طعام"
  doAssert allowanceNames("Hotel Allowance").ar == "", "(Hotel is not tel)"
  doAssert book.fields[before + 1].kind == fkNumber
  let i = book.byNo("MCT-1004")
  doAssert i >= 0
  doAssert book.totalSalary(book.employees[i]) == 420 + 85 + 30 + 10
  # the second time: remembered, no new fields
  var again = newPlan(book, @[data / "muscat-arabic.xlsx"])
  doAssert again.sheets[0].remembered
  matchRows(book, again)
  doAssert apply(book, again).newFields == 0

block numberOfSomeoneElse:
  var b2 = newBook(["Sohar Hotel", "Muscat Hotel", "Salalah Resort"])
  var e = newEmployee()
  e.v["empNo"] = "SOH-1003"
  e.v["nameEn"] = "Mostafa Fathy"
  e.v["hotel"] = b2.hotels[0].id
  b2.employees.add e
  var plan = newPlan(b2, @[data / "payroll.xlsx"])
  matchRows(b2, plan)
  var asked = false
  for q in plan.questions:
    if q.kind == "person":
      asked = true
      doAssert not q.take, "another name: not the same person, unless the user says so"
      doAssert plan.isNew(q.match)
    if q.kind == "value": doAssert plan.matches[q.match].emp != 0, "no value questions for him"
  doAssert asked
  # digits that point at two people: the name picks
  var b3 = newBook(["Sohar Hotel", "Muscat Hotel"])
  for (no, nm, h) in [("SOH-1002", "Ali Said", 0), ("MCT-1002", "Rajesh Kumar Nair", 1)]:
    var x = newEmployee()
    x.v["empNo"] = no
    x.v["nameEn"] = nm
    x.v["hotel"] = b3.hotels[h].id
    b3.employees.add x
  var p3 = newPlan(b3, @[data / "visa.xlsx"])
  matchRows(b3, p3)
  doAssert p3.matches[0].emp == 1, "1002 Rajesh K. Nair is MCT-1002's Rajesh, not Ali"

block crossSheets:
  # two sheets of the same new people: one person each, with both sheets' facts
  var b4 = newBook(["Sohar Hotel", "Muscat Hotel", "Salalah Resort"])
  var plan = newPlan(b4, @[data / "payroll.xlsx", data / "visa.xlsx"])
  matchRows(b4, plan)
  var linked = 0
  for m in plan.matches:
    if m.sameAs >= 0: inc linked
  doAssert linked == 2, "1002 and 1003 are in both sheets: " & $linked
  let r = apply(b4, plan)
  doAssert r.added == 5, "4 from the payroll and Bikash from the visa sheet: " & $r.added
  let i = b4.byNo("SOH-1003")
  doAssert b4.employees[i].get("visaExpiry") == "2027-02-03", "the visa sheet's facts too"
  doAssert b4.employees[i].get("basic") == "350"

block lettersBlock:
  book.templates = starterTemplates()
  let e = book.employees[book.byNo("SOH-1002")]
  let t = book.templates[0]
  doAssert findTags(t.body).len > 10
  let doc = letterReport(book, t, e, {tagKey("Addressed to"): "Example Bank",
                                      tagKey("Purpose"): "a loan"}.toTable,
                         "SOH/HR/2026/001", tmp)
  doAssert doc.pageCount == 1
  var text = ""
  for p in doc.pageTexts(0): text.add p.text & " "
  doAssert "Rajesh Kumar Nair" in text, text
  doAssert "Four Hundred Eighty-Five Omani Rials" in text, text
  doAssert "Example Bank" in text and "a loan" in text
  doAssert "#[" notin text, "every tag filled: " & text
  let ar = letterReport(book, book.templates[1], e, {tagKey("الجهة الموجهة إليها"): "بنك المثال"}.toTable,
                        "SOH/HR/2026/002", tmp)
  var arText = ""
  for p in ar.pageTexts(0): arText.add p.text & " "
  doAssert "#[" notin arText, arText
  doAssert "له هذه الشهادة" in arText, arText
  doAssert "هندي" in arText, "the nationality in Arabic: " & arText
  doAssert "Other Allowance" notin text, "an allowance he does not have is left out"
  doAssert "Housing Allowance" in text and "OMR 485.000" in text
  doc.savePdf(tmp / "letter.pdf")
  doAssert readFile(tmp / "letter.pdf").startsWith("%PDF")
  doAssert takeRefNo(book, book.hotels[0].id).endsWith("/001")
  doAssert takeRefNo(book, book.hotels[0].id).endsWith("/002")

removeDir(tmp)
echo "hr book tests passed"
