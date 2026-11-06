# (included by hrbook.nim) The dashboard, the charts and the alerts.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

var
  chartHotel = 0
  alertRange = 0
  colsAlerts = @[colorColumn("", 26), column("Employee", 200), column("Hotel", 120),
                 column("Document", 130), column("Number", 110), column("Expires", 90),
                 numberColumn("Days", 56), buttonColumn("", 70)]
  alertSel = 0

proc activeIdx(hotelId = ""): seq[int] =
  for i, e in book.employees:
    if e.active and (hotelId.len == 0 or e.get("hotel") == hotelId): result.add i

proc payrollOf(hotelId = ""): float =
  for i in activeIdx(hotelId): result += book.totalSalary(book.employees[i])

proc omanisOf(hotelId = ""): float =
  let a = activeIdx(hotelId)
  var n = 0
  for i in a:
    if book.employees[i].get("nationality").toLowerAscii in ["omani", "oman", "عماني", "عمانية"]: inc n
  100.0 * float(n) / float(max(1, a.len))

type AlertRow = tuple[color, name, hotel, doc, number, at: string; days, emp: int]

proc alertRows(limit: int): seq[AlertRow] =
  for i, e in book.employees:
    if not e.active: continue
    for f in book.fields:
      if not f.expiry or f.hidden or f.kind != fkDate: continue
      let v = e.get(f.key)
      if v.len == 0: continue
      let d = dayNum(v) - todayNum()
      if d > limit: continue
      let c = if d < 0: "#808080" elif d <= 30: "#C53030" elif d <= 60: "#E5731A" else: "#D6A219"
      var number = ""
      case f.key
      of "passportExpiry": number = e.get("passportNo")
      of "visaExpiry": number = e.get("visaNo")
      of "civilIdExpiry": number = e.get("civilId")
      of "contractEnd": number = e.get("empNo")
      else: discard
      result.add (c, e.name, book.hotelName(e.get("hotel")), f.label.replace(" Expiry", ""),
                  number, showDate(v), d, i)
  result.sort(proc (a, b: AlertRow): int = cmp(a.days, b.days))

proc dashboard() =
  let h = now().hour
  heading((if h < 12: "Good morning" elif h < 17: "Good afternoon" else: "Good evening"), 2)
  label("All your hotels at a glance -- " & showDate(todayIso()), color = ui.theme.gray)
  let all = activeIdx()
  if all.len == 0:
    emptyState(pxUser, "No employees yet",
               detail = "Import your Excel sheets (Import sheets), or add people one by one.")
    row:
      if button("&Import Excel sheets..."): section = "Import sheets"
      if button("&New employee..."): startEdit(-1)
    return
  var otherVisa = 0
  for i in all:
    if book.employees[i].otherVisa: inc otherVisa
  let soon = alertRows(30)
  kpiRow:
    kpiTile("Employees", $all.len)
    if not book.hideSalaries: kpiTile("Monthly payroll", "OMR " & fmtNum(payrollOf(), 0))
    kpiTile("Omanisation", fmtNum(omanisOf(), 1) & " %")
    if statCard(pxWarning, "Expiring in 30 days", $soon.len, "see Alerts", color(197, 48, 48)):
      section = "Alerts"
    if statCard(pxSheet, "Other hotels' visas", $otherVisa, "see the list", color(229, 115, 26)):
      section = "Employees/visa"
  adaptive(260):
    for hh in book.hotels:
      card(hh.name):
        block:
          let a = activeIdx(hh.id)
          var joined, ending, ov = 0
          for i in a:
            let e = book.employees[i]
            let j = parseDateText(e.get("joined"))
            if j.ok and j.y == now().year: inc joined
            let c = dayNum(e.get("contractEnd"))
            if c != low(int) and c - todayNum() in 0 .. 90: inc ending
            if e.otherVisa: inc ov
          if statCard(pxUser, "Employees", $a.len, $joined & " joined this year", colorOf(hh.color)):
            section = "Employees/hotel:" & hh.id
            current = -1
          var facts: seq[(string, string)]
          if not book.hideSalaries: facts.add ("Monthly payroll", "OMR " & fmtNum(payrollOf(hh.id), 0))
          facts.add ("Omanisation", fmtNum(omanisOf(hh.id), 1) & " %")
          facts.add ("Contracts ending soon", $ending)
          facts.add ("On other visas", $ov)
          factList(facts)
  adaptive(380):
    card("Headcount by department"):
      block:
        var depts: seq[string]
        for i in all:
          let d = book.employees[i].get("department")
          if d.len > 0 and d notin depts: depts.add d
        depts.sort()
        var ss: seq[Series]
        for hh in book.hotels:
          var v: seq[float]
          for d in depts:
            var n = 0
            for i in activeIdx(hh.id):
              if book.employees[i].get("department") == d: inc n
            v.add float(n)
          ss.add series(hh.name, v)
        if depts.len > 0:
          chart("", chStacked, depts, ss, height = 230,
                opts = ChartOpts(palette: @businessColors, key: "dash-dept"))
        else: label("No departments yet.", color = ui.theme.gray)
    card("Nationalities"):
      block:
        var counts = initCountTable[string]()
        for i in all:
          let n = book.employees[i].get("nationality")
          counts.inc(if n.len > 0: n else: "(not set)")
        counts.sort()
        var labels: seq[string]
        var vals: seq[float]
        for k, v in counts.pairs:
          labels.add k
          vals.add float(v)
        chart("", chDonut, labels, [series("Employees", vals)], height = 230,
              opts = ChartOpts(palette: @businessColors, key: "dash-nat"))

proc chartsPage() =
  row:
    heading("Charts", 2)
    spring()
    label "Hotel:"
    combo(@["All hotels"] & hotelNames(), chartHotel, w = 160)
  let hid = if chartHotel > 0 and chartHotel <= book.hotels.len: book.hotels[chartHotel - 1].id else: ""
  let a = activeIdx(hid)
  if a.len == 0:
    emptyState(pxPieChart, "Nothing to chart yet", detail = "Charts appear once there are employees.")
    return
  adaptive(330):
    card("Omanisation by hotel"):
      block:
        var labels: seq[string]
        var vals: seq[float]
        for hh in book.hotels:
          labels.add hh.name
          vals.add omanisOf(hh.id)
        chart("", chBar, labels, [series("Omanis %", vals)], height = 220,
              opts = ChartOpts(format: NumFormat(suffix: " %"), dataLabels: true, key: "c-oman",
                               palette: @businessColors))
    if not book.hideSalaries:
      card("Payroll a month by hotel (OMR)"):
        block:
          var labels: seq[string]
          var vals: seq[float]
          for hh in book.hotels:
            labels.add hh.name
            vals.add payrollOf(hh.id)
          chart("", chBar, labels, [series("OMR", vals)], height = 220,
                opts = ChartOpts(dataLabels: true, key: "c-pay", palette: @businessColors))
      card("Basic salaries (how many in each band)"):
        block:
          var v: seq[float]
          for i in a:
            let x = num(book.employees[i].get("basic"))
            if not x.isNaN: v.add x
          if v.len > 1:
            chart("", chHistogram, [], [series("Employees", v)], height = 220,
                  opts = ChartOpts(bins: 10, key: "c-bands", palette: @businessColors,
                                   xTitle: "Basic salary (OMR)"))
          else: label("Not enough salaries yet.", color = ui.theme.gray)
      card("Payroll by department"):
        block:
          var t = initTable[string, float]()
          for i in a:
            let d = book.employees[i].get("department")
            t.mgetOrPut(if d.len > 0: d else: "(none)", 0.0) += book.totalSalary(book.employees[i])
          var labels: seq[string]
          var vals: seq[float]
          for k, v in t.pairs:
            labels.add k
            vals.add v
          chart("", chTreemap, labels, [series("OMR", vals)], height = 220,
                opts = ChartOpts(key: "c-dept", palette: @businessColors))
    card("Years of service"):
      block:
        var bk = [0.0, 0, 0, 0, 0]
        for i in a:
          let j = dayNum(book.employees[i].get("joined"))
          if j == low(int): continue
          let y = yearsBetween(j, todayNum())
          bk[if y < 1: 0 elif y < 3: 1 elif y < 5: 2 elif y < 10: 3 else: 4] += 1
        chart("", chBar, ["< 1", "1-3", "3-5", "5-10", "10+"], [series("Employees", bk)],
              height = 220, opts = ChartOpts(key: "c-years", dataLabels: true, palette: @businessColors))
    card("Nationalities"):
      block:
        var counts = initCountTable[string]()
        for i in a:
          let n = book.employees[i].get("nationality")
          counts.inc(if n.len > 0: n else: "(not set)")
        counts.sort()
        var labels: seq[string]
        var vals: seq[float]
        for k, v in counts.pairs:
          labels.add k
          vals.add float(v)
        chart("", chDonut, labels, [series("Employees", vals)], height = 220,
              opts = ChartOpts(palette: @businessColors, key: "c-nat"))

proc alertsPage() =
  row:
    heading("Alerts", 2)
    spring()
    label "Expiring within:"
    segmented(["30 days", "60 days", "90 days", "180 days"], alertRange)
  let rows = alertRows([30, 60, 90, 180][alertRange])
  var overdue, soon = 0
  for r in rows:
    if r.days < 0: inc overdue
    elif r.days <= 30: inc soon
  kpiRow(220):
    statCard(pxError, "Expired already", $overdue, "renew now", color(128, 128, 128))
    statCard(pxWarning, "Within 30 days", $soon, "act now", color(197, 48, 48))
    statCard(pxClock, "In the list", $rows.len, "visas, passports, contracts...", color(214, 162, 25))
  if rows.len == 0:
    emptyState(pxCheck, "Nothing expires in this time", detail = "Dates watched: the fields marked " &
               "\"Watched for expiry\" in Settings > Fields.")
    return
  let ev = grid(colsAlerts, rows.len, proc (r, c: int): string =
    let a = rows[r]
    case c
    of 0: a.color
    of 1: a.name
    of 2: a.hotel
    of 3: a.doc
    of 4: a.number
    of 5: a.at
    of 6: $a.days
    else: "Open",
    alertSel, height = -1)
  if (ev.clicked and ev.col == 7) or ev.activated:
    let r = if ev.clicked: ev.row else: alertSel
    if r >= 0 and r < rows.len:
      current = rows[r].emp
      section = "Employees/All hotels"
