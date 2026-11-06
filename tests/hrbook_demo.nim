## A demo book for HR Book (examples/hrbook.nim), PIN 246810: 186 invented
## people in three invented hotels, with letters issued, and three Excel
## sheets to import in ~/Downloads (a payroll, a staff list in Arabic, a
## visa tracker) -- for trying the app and for its screenshots.
##
## Everything in it is made up: the names, and numbers that cannot be real
## (phones +968 0000 ..., passports X000..., IBANs and C.R. numbers of
## zeros).
##
## It writes HR Book's data folder, so run it with HOME (or XDG_DATA_HOME)
## pointed at a folder of its own; it will not replace a book that is
## there unless asked (`--replace`):
##
##   HOME=/tmp/hrbook-demo nim c -r tests/hrbook_demo.nim
##   HOME=/tmp/hrbook-demo nim c -r -d:release examples/hrbook.nim
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, tables, strutils, math, base64, times]
import retroui/[canvas2d, xlsx]
from retroui/uirelays/services import dataDir
import ../examples/hrbook/[model, store, letters]

let dir = dataDir("HRBook")              # (where the app looks: its AppId)
if hasData(dir) and "--replace" notin commandLineParams():
  quit "HR Book already has a book in " & dir & "; run this with HOME pointed at another " &
       "folder, or with --replace to put the demo in its place."

var seed = 20261027
proc rnd(n: int): int =
  seed = (seed * 1103515245 + 12345) and 0x7FFFFFFF
  (seed shr 8) mod max(1, n)
proc pick[T](a: openArray[T]): T = a[rnd(a.len)]

proc logo(letter, colorHex: string): string =
  let c = newCanvas2D(240, 240)
  c.fillStyle = colorHex
  c.beginPath()
  c.roundRect(10, 10, 220, 220, 36)
  c.fill()
  c.fillStyle = "#ffffff"
  c.font = "bold 150px sans-serif"
  c.textAlign = "center"
  c.textBaseline = "middle"
  c.fillText(letter, 120, 128)
  c.fillStyle = "#d6a219"
  c.fillRect(40, 196, 160, 12)
  encode(c.encodePng())

proc signaturePic(): string =
  let c = newCanvas2D(420, 160)
  c.strokeStyle = "#1a2a6c"
  c.lineWidth = 4
  c.lineCap = "round"
  c.beginPath()
  c.moveTo(20, 110)
  c.bezierCurveTo(60, 20, 90, 150, 130, 70)
  c.bezierCurveTo(160, 20, 180, 140, 220, 80)
  c.bezierCurveTo(250, 40, 280, 120, 330, 70)
  c.lineTo(400, 60)
  c.stroke()
  encode(c.encodePng())

proc stampPic(colorHex, text: string): string =
  let c = newCanvas2D(300, 300)
  c.strokeStyle = colorHex
  c.lineWidth = 8
  c.beginPath()
  c.arc(150, 150, 130, 0, 2 * PI)
  c.stroke()
  c.lineWidth = 3
  c.beginPath()
  c.arc(150, 150, 105, 0, 2 * PI)
  c.stroke()
  c.fillStyle = colorHex
  # the hotel's name as big as fits inside the inner ring
  var size = 30
  c.font = "bold " & $size & "px sans-serif"
  while size > 14 and c.measureText(text).width > 180:
    dec size, 2
    c.font = "bold " & $size & "px sans-serif"
  c.textAlign = "center"
  c.textBaseline = "middle"
  c.fillText(text, 150, 135)
  c.font = "22px sans-serif"
  c.fillText("HR DEPARTMENT", 150, 175)
  c.globalAlpha = 0.85
  encode(c.encodePng())

const
  depts = ["Front Office", "Housekeeping", "F&B Service", "Kitchen", "Engineering", "Security",
           "Sales & Marketing", "Finance", "Human Resources"]
  deptWeight = [12, 20, 20, 18, 10, 7, 5, 5, 3]
  positions: array[9, seq[(string, string, float, float)]] = [
    @[("Front Office Manager", "M2", 1100.0, 1400.0), ("Guest Relations Supervisor", "S1", 520.0, 640.0),
      ("Receptionist", "E2", 330.0, 420.0), ("Night Auditor", "E2", 340.0, 400.0)],
    @[("Executive Housekeeper", "M1", 900.0, 1150.0), ("Floor Supervisor", "S1", 420.0, 520.0),
      ("Room Attendant", "E1", 160.0, 240.0), ("Laundry Attendant", "E1", 150.0, 200.0)],
    @[("F&B Manager", "M2", 1200.0, 1500.0), ("Restaurant Supervisor", "S1", 450.0, 560.0),
      ("Waiter", "E1", 180.0, 260.0), ("Host", "E1", 300.0, 360.0)],
    @[("Executive Chef", "M2", 1300.0, 1700.0), ("Sous Chef", "S2", 650.0, 820.0),
      ("Chef de Partie", "E3", 330.0, 420.0), ("Commis", "E1", 170.0, 230.0)],
    @[("Chief Engineer", "M1", 1000.0, 1250.0), ("Shift Engineer", "S1", 480.0, 600.0),
      ("Technician", "E2", 220.0, 320.0)],
    @[("Security Manager", "M1", 850.0, 1000.0), ("Security Officer", "E2", 325.0, 380.0)],
    @[("Director of Sales", "M3", 1500.0, 1900.0), ("Sales Executive", "E3", 400.0, 520.0)],
    @[("Finance Manager", "M2", 1300.0, 1600.0), ("Accountant", "E3", 450.0, 600.0)],
    @[("HR Manager", "M2", 1200.0, 1500.0), ("HR Officer", "E3", 420.0, 520.0)]]
  omaniFirstM = [("Ahmed", "أحمد"), ("Mohammed", "محمد"), ("Salim", "سالم"), ("Khalid", "خالد"),
                 ("Said", "سعيد"), ("Hamad", "حمد"), ("Yousuf", "يوسف"), ("Ali", "علي"),
                 ("Hilal", "هلال"), ("Badar", "بدر"), ("Talal", "طلال"), ("Nasser", "ناصر")]
  omaniFirstF = [("Fatma", "فاطمة"), ("Aisha", "عائشة"), ("Maryam", "مريم"), ("Shamsa", "شمسة"),
                 ("Zainab", "زينب"), ("Noor", "نور"), ("Asma", "أسماء"), ("Muna", "منى")]
  omaniLast = [("Al Balushi", "البلوشي"), ("Al Hinai", "الهنائي"), ("Al Saadi", "السعدي"),
               ("Al Maamari", "المعمري"), ("Al Riyami", "الريامي"), ("Al Kindi", "الكندي"),
               ("Al Habsi", "الحبسي"), ("Al Shukaili", "الشكيلي"), ("Al Siyabi", "السيابي"),
               ("Al Amri", "العامري"), ("Al Farsi", "الفارسي"), ("Al Rawahi", "الرواحي")]
  expats = [
    ("Indian", @["Rajesh", "Anil", "Suresh", "Vinod", "Arun", "Joseph"],
     @["Nair", "Kumar", "Pillai", "Menon", "Fernandes", "Varghese", "Iyer"], @["Priya", "Deepa", "Lakshmi"]),
    ("Filipino", @["Jose", "Mark", "John", "Paolo"],
     @["Santos", "Reyes", "Cruz", "Garcia", "Mendoza", "Bautista"], @["Maria", "Kristine", "Angelica"]),
    ("Nepali", @["Ram", "Bikash", "Ramesh"], @["Gurung", "Thapa", "Shrestha", "Rai"], @["Sita", "Anita"]),
    ("Bangladeshi", @["Abdul", "Rahim", "Karim", "Shahid"], @["Hossain", "Rahman", "Islam", "Uddin"],
     @["Nasrin", "Farzana"]),
    ("Sri Lankan", @["Nimal", "Chaminda", "Kasun"], @["Perera", "Fernando", "Silva"], @["Dilani", "Chathuri"]),
    ("Egyptian", @["Mahmoud", "Mostafa", "Hany"], @["Abdelrahman", "Hassan", "Fathy"], @["Mona", "Heba"])]
  banks = ["Example Bank", "Example National Bank", "Example Savings Bank", "Example Gulf Bank"]

proc iso(y, m, d: int): string = $y & "-" & align($m, 2, '0') & "-" & align($d, 2, '0')
proc daysFromNow(n: int): string =
  let t = (todayNum() + n) * 86400
  fromUnix(t).utc.format("yyyy-MM-dd")



var b = newBook(["Sohar Hotel", "Muscat Hotel", "Salalah Resort"])
b.templates = starterTemplates()
# (invented hotels: example addresses, C.R. and VAT numbers of zeros)
let hinfo = [("SOH", "فندق صحار", "#1f4e79", "1 Example Beach Road, Sohar, Sultanate of Oman",
              "0000001", "OM0000000001", "+968 0000 0100", "Mr. Salim Al Hinai", "HR Manager"),
             ("MCT", "فندق مسقط", "#7b2c2c", "2 Example Street, Muscat, Sultanate of Oman",
              "0000002", "OM0000000002", "+968 0000 0200", "Ms. Huda Al Kindi", "HR Manager"),
             ("SLL", "منتجع صلالة", "#2e6b3a", "3 Example Beach, Salalah, Sultanate of Oman",
              "0000003", "OM0000000003", "+968 0000 0300", "Mr. Nasser Al Amri", "HR Manager")]
for i in 0 .. 2:
  let (code, ar, col, adr, cr, vat, phone, signer, title) = hinfo[i]
  b.hotels[i].code = code
  b.hotels[i].nameAr = ar
  b.hotels[i].color = col
  b.hotels[i].address = adr
  b.hotels[i].cr = cr
  b.hotels[i].vat = vat
  b.hotels[i].phone = phone
  b.hotels[i].email = "hr@" & code.toLowerAscii & "-hotel.example"
  b.hotels[i].refPrefix = code & "/HR"
  b.hotels[i].signer = signer
  b.hotels[i].signerTitle = title
  b.hotels[i].signerAr = ["سالم الهنائي", "هدى الكندي", "ناصر العامري"][i]
  b.hotels[i].signerTitleAr = "مدير الموارد البشرية"
  b.hotels[i].logo = logo(["S", "M", "R"][i], col)
  b.hotels[i].signature = signaturePic()
  b.hotels[i].stamp = stampPic(col, b.hotels[i].name.toUpperAscii)
b.lists["positions"] = @[]
b.lists["grades"] = @["E1", "E2", "E3", "S1", "S2", "M1", "M2", "M3"]
b.groups.add Group(id: newId("g-"), name: "Training", color: "#178c96", modified: nowT())
let sizes = [72, 64, 50]
var counter = 0
for h in 0 .. 2:
  var perDept: array[9, int]
  for k in 0 ..< sizes[h]:
    var d = 0
    var x = rnd(100)
    for i, w in deptWeight:
      if x < w:
        d = i
        break
      x -= w
    let pl = positions[d]
    let pi = if perDept[d] == 0: 0 elif perDept[d] == 1: 1 else: 2 + rnd(pl.len - 2)
    inc perDept[d]
    let (title, grade, lo, hi) = pl[min(pi, pl.high)]
    var e = newEmployee()
    e.v["hotel"] = b.hotels[h].id
    e.v["department"] = depts[d]
    e.v["position"] = title
    if title notin b.lists["positions"]: b.lists["positions"].add title
    e.v["grade"] = grade
    e.v["status"] = "Active"
    inc counter
    e.v["empNo"] = b.hotels[h].code & "-" & $(1000 + counter * 3)
    # (numbers that cannot be anyone's: zeros, then the person's count)
    let n4 = align($counter, 4, '0')
    let civil = "0000" & n4
    let passport = "X000" & n4
    let female = rnd(5) == 0 or (d in [0, 1, 2] and rnd(3) == 0)
    e.v["gender"] = if female: "Female" else: "Male"
    let omaniOdds = (if d in [0, 5, 8]: 70 elif d in [1, 3, 4]: 25 else: 40)
    if rnd(100) < omaniOdds:
      e.v["nationality"] = "Omani"
      let (fe, fa) = if female: pick(omaniFirstF) else: pick(omaniFirstM)
      let (me, ma) = pick(omaniFirstM)
      let (le, la) = pick(omaniLast)
      e.v["nameEn"] = fe & " " & me & " " & le
      e.v["nameAr"] = fa & " " & ma & " " & la
      e.v["civilId"] = civil
      e.v["civilIdExpiry"] = daysFromNow(60 + rnd(1500))
    else:
      let (nat, firsts, lasts, firstsF) = pick(expats)
      e.v["nationality"] = nat
      e.v["nameEn"] = (if female: pick(firstsF) else: pick(firsts)) & " " & pick(lasts)
      e.v["civilId"] = civil
      e.v["passportNo"] = passport
      e.v["passportExpiry"] = daysFromNow(200 + rnd(1800))
      e.v["visaNo"] = "V000" & n4
      e.v["visaType"] = "Employment"
      e.v["visaExpiry"] = daysFromNow(15 + rnd(720))
      e.v["civilIdExpiry"] = e.v["visaExpiry"]
      e.v["visaUnder"] = if rnd(9) == 0: b.hotels[(h + 1 + rnd(2)) mod 3].id else: b.hotels[h].id
    let basic = round((lo + float(rnd(int(hi - lo) + 1))) / 5) * 5
    e.v["basic"] = $int(basic)
    e.v["housing"] = $int(round(basic * (if grade[0] == 'M': 0.3 else: 0.2) / 5) * 5)
    e.v["transport"] = if grade[0] == 'M': "100" elif grade[0] == 'S': "60" else: "30"
    if d in [2, 3]: e.v["otherAllowance"] = "15"
    let jy = 2012 + rnd(15)
    var joined = iso(jy, 1 + rnd(12), 1 + rnd(28))
    if dayNum(joined) > todayNum(): joined = daysFromNow(-rnd(200))
    e.v["joined"] = joined
    e.v["dob"] = iso(1972 + rnd(32), 1 + rnd(12), 1 + rnd(28))
    e.v["contract"] = if e.v["nationality"] == "Omani" or rnd(4) == 0: "Unlimited" else: "Limited"
    if e.v["contract"] == "Limited": e.v["contractEnd"] = daysFromNow(20 + rnd(720))
    e.v["bank"] = pick(banks)
    e.v["iban"] = "OM00 0000 0000 0000 " & n4
    e.v["phone"] = "+968 0000 " & n4
    e.v["leaveBalance"] = $rnd(31)
    if rnd(8) == 0: e.groups.add b.groups[0].id
    if rnd(10) == 0: e.groups.add b.groups[2].id
    if d in [1, 3] and rnd(6) == 0: e.groups.add b.groups[1].id
    # history: the salary over the years
    var bas = basic
    var y = jy
    var steps: seq[(int, float)]
    while y < 2026:
      steps.add (y, bas)
      bas = round(bas * 1.05 / 5) * 5
      y += 1 + rnd(2)
    steps.add (2026, basic)
    for (yy, v) in steps:
      e.history.add Change(at: float(dayNum(iso(yy, 1, 1))) * 86400, field: "basic", was: "",
                           now: $int(v), source: if yy == 2026: "Payroll Oct 2026.xlsx" else: "Increments " & $yy & ".xlsx")
    b.employees.add e
# the one in the pictures
block:
  var e = b.employees[3]
  e.v["nameEn"] = "Maryam Salim Al Hinai"
  e.v["nameAr"] = "مريم سالم الهنائي"
  e.v["gender"] = "Female"
  e.v["nationality"] = "Omani"
  e.v["department"] = "Front Office"
  e.v["position"] = "Guest Relations Supervisor"
  e.v["grade"] = "S1"
  e.v["joined"] = "2018-09-02"
  e.v["basic"] = "610"
  e.v["housing"] = "120"
  e.v["transport"] = "60"
  e.v.del("otherAllowance")
  e.v["contract"] = "Unlimited"
  e.v.del("contractEnd")
  e.v["emergency"] = "Salim Al Hinai (father), +968 0000 0034"
  for k in ["passportNo", "passportExpiry", "visaNo", "visaType", "visaExpiry", "visaUnder"]: e.v.del(k)
  e.v["civilIdExpiry"] = daysFromNow(410)
  e.history = @[]
  for (y, v) in [(2018, 450), (2020, 480), (2022, 520), (2023, 580), (2025, 610)]:
    e.history.add Change(at: float(dayNum(iso(y, 1, 1))) * 86400, field: "basic", now: $v,
                         source: if y == 2023: "Promotion letter (by hand)" else: "Payroll Jan " & $y & ".xlsx")
  b.employees[3] = e
for i in [5, 40, 77, 120, 150]: b.employees[i].v["status"] = "Left"
for (en, ar) in [("Guest Relations Supervisor", "مشرفة علاقات النزلاء"), ("Receptionist", "موظف استقبال"),
                 ("Executive Housekeeper", "مدير التدبير الفندقي"), ("Chef de Partie", "رئيس قسم مطبخ"),
                 ("Room Attendant", "عامل غرف"), ("Security Guard", "حارس أمن"), ("Waiter", "نادل")]:
  b.arabic[en] = ar
# a few letters issued
for k in 0 .. 3:
  let e = b.employees[k * 7 + 3]
  let t = b.templates[k mod 2]
  let refNo = takeRefNo(b, e.get("hotel"))
  b.issued.add Issued(at: nowT() - float(86400 * (10 - k)), emp: e.id, empName: e.name, templ: t.id,
                      templName: t.name, refNo: refNo, hotel: e.get("hotel"))
b.layouts.add Layout(headers: "x", name: "Payroll (3 hotels)", used: 4, modified: nowT())
# sheets to import, as the hotels keep them (in Downloads, where HR Book
# looks first; files of the same names are replaced, nothing else touched)
block:
  let dl = getHomeDir() / "Downloads"
  createDir(dl)
  proc ofHotel(h: int): seq[int] =
    for i, e in b.employees:
      if e.get("hotel") == b.hotels[h].id and e.get("status") == "Active": result.add i
  # Sohar: November's payroll -- three raises, a phone allowance HR Book
  # has not got yet, two new joiners, a name written short
  var rows = @[@["Sohar Hotel - Payroll November 2026"], @[""],
               @["S.No", "Staff No", "Employee Name", "Designation", "Basic", "HRA", "Transport",
                 "Phone Allowance", "Total"]]
  let soh = ofHotel(0)
  for k, i in soh[0 ..< 30]:
    let e = b.employees[i]
    var basic = parseInt(e.get("basic"))
    if k in [2, 9, 17]: basic += 25
    var nm = e.get("nameEn")
    if k == 5: nm = nm.replace(" Al ", " Al-")
    let hra = parseInt(e.get("housing"))
    let tr = parseInt(e.get("transport"))
    let ph = if e.get("grade").startsWith("M"): 20 elif e.get("grade").startsWith("S"): 10 else: 0
    rows.add @[$(k + 1), e.get("empNo"), nm, e.get("position"), $basic, $hra, $tr,
               (if ph > 0: $ph else: ""), $(basic + hra + tr + ph)]
  rows.add @["31", "SOH-1601", "Hamed Nasser Al Kindi", "Commis Chef", "330", "65", "30", "", "425"]
  rows.add @["32", "SOH-1604", "Joy Villanueva", "Waitress", "240", "50", "30", "", "320"]
  rows.add @["", "", "Total", "", "", "", "", "", ""]
  writeXlsx(dl / "Sohar payroll Nov 2026.xlsx", [XlsxSheet(name: "Nov 2026", rows: rows)])
  # Muscat: the master list in Arabic
  var ar = @[@["فندق مسقط"], @["سجل الموظفين"], @[""],
             @["الرقم الوظيفي", "الاسم", "الجنسية", "الوظيفة", "القسم", "تاريخ الالتحاق", "الهاتف"]]
  for i in ofHotel(1)[0 ..< 20]:
    let e = b.employees[i]
    ar.add @[e.get("empNo"), (if e.get("nameAr").len > 0: e.get("nameAr") else: e.get("nameEn")),
             e.get("nationality"), e.get("position"), e.get("department"),
             e.get("joined").replace("-", "/"), e.get("phone")]
  writeXlsx(dl / "Muscat staff list.xlsx", [XlsxSheet(name: "الموظفين", rows: ar)])
  # the PRO's visa tracker: all hotels, numbers without their letters, no
  # hotel column; some visas renewed
  var vt = @[@["Visa tracker (all hotels)"],
             @["Emp ID", "Name", "Passport #", "PP Exp.", "Visa Exp", "Visa Under", "Mob."]]
  var n = 0
  for i, e in b.employees:
    if e.get("visaExpiry").len == 0 or e.get("status") != "Active": continue
    inc n
    if n > 40: break
    var ve = e.get("visaExpiry")
    if n mod 6 == 0: ve = daysFromNow(700)
    var no = e.get("empNo")
    no = no[no.find('-') + 1 .. ^1]
    vt.add @[no, e.get("nameEn"), e.get("passportNo"), e.get("passportExpiry"), ve,
             b.hotelName(e.get("visaUnder")), e.get("phone")]
  writeXlsx(dl / "Visa tracker.xlsx", [XlsxSheet(name: "All staff", rows: vt)])

for f in [dataFile(dir), dataFile(dir) & ".1", dataFile(dir) & ".2", dataFile(dir) & ".3"]:
  removeFile(f)                           # (the book there before, with --replace)
discard create(dir, "246810", b)
echo "demo book: ", b.employees.len, " employees in ", dir, " (PIN 246810)"
