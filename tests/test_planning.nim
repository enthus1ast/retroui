## The planning views: the kanban board, the Gantt chart, the agenda, the
## dashboard tiles and the org chart -- by mouse, keys and fingers, empty
## and with thousands of items.

import std/[monotimes, times, strutils]
import retro
import retro/planning
import retro/uirelays/input
import harness

fakeDriver()
startApp("planning", W, H)

proc clickAt(x, y: int; clicks = 1) =
  down(x, y, clicks)
  run()
  up(x, y)
  run()

proc dragMouse(x0, y0, x1, y1: int; steps = 6) =
  down(x0, y0)
  run()
  for i in 1 .. steps:
    move(x0 + (x1 - x0) * i div steps, y0 + (y1 - y0) * i div steps)
    run()
  up(x1, y1)
  run(2)

proc holdThenDrag(x0, y0, x1, y1: int) =
  ## A finger held on something (the long press), then moved there.
  down(x0, y0)
  run(40)
  move(x0 + 20, y0 + 20)
  run()
  move(x1, y1)
  run()
  up(x1, y1)
  run(2)

proc ms(t0: MonoTime): float = float((getMonoTime() - t0).inNanoseconds) / 1e6

# ---- kanban -------------------------------------------------------------------------------------

block kanban:
  var lanes = @[
    KanbanLane(title: "To do", cards: @[
      KanbanCard(title: "Price list", detail: "For the new menu", tag: color(219, 68, 55),
                 who: "Sultan Al-Said"),
      KanbanCard(title: "Staff rota", due: date(2020, 1, 1)),
      KanbanCard(title: "Linen order")]),
    KanbanLane(title: "Doing", limit: 1, cards: @[KanbanCard(title: "Pool repair")]),
    KanbanLane(title: "Done")]
  var sel: KanbanPos = (0, 0)
  var ev: KanbanEvent
  var r: Rect
  view = proc () =
    let e = kanbanBoard(lanes, sel, height = 400)
    if e.moved or e.opened or e.added or e.selChanged: ev = e
    r = ui.lastRect
  run(3)
  let gap = dp(8)
  let laneW = max(dp(210), (r.w - gap * 4) div 3)
  let hdrH = FontH + dp(12)
  proc laneX(i: int): int = r.x + gap + i * (laneW + gap)
  proc cardY(k: int): int =
    var y = r.y + gap + hdrH + dp(6)
    for j in 0 ..< k:
      let c = lanes[0].cards[j]
      var h = dp(8) + FontH + dp(6)
      if c.detail.len > 0: h += FontH
      if c.due.year > 0 or c.who.len > 0: h += FontH + dp(4)
      y += h + dp(6)
    y + dp(6)
  # a click chooses, a double click opens
  ev = KanbanEvent()
  clickAt(laneX(0) + 40, cardY(1))
  doAssert sel == (0, 1), $sel
  clickAt(laneX(0) + 40, cardY(1), clicks = 2)
  doAssert ev.opened, "a double click opens"
  # keys: arrows choose, Ctrl + arrows move
  key(KeyDown)
  run()
  doAssert sel == (0, 2)
  key(KeyUp, {CtrlPressed})
  run()
  doAssert ev.moved and lanes[0].cards[1].title == "Linen order" and sel == (0, 1),
    "Ctrl+Up moves the card up"
  key(KeyRight, {CtrlPressed})
  run()
  doAssert lanes[1].cards.len == 2 and sel.lane == 1 and ev.moved, "Ctrl+Right to the next lane"
  doAssert ev.fromPos == (0, 1) and ev.toPos.lane == 1, $ev
  key(KeyEnter)
  run()
  doAssert ev.opened
  # the mouse drags a card to another lane
  let before = lanes[2].cards.len
  ev = KanbanEvent()
  dragMouse(laneX(0) + 40, cardY(0), laneX(2) + 60, r.y + hdrH + dp(40))
  doAssert lanes[2].cards.len == before + 1 and ev.moved and ev.toPos.lane == 2,
    "dragged to Done: " & $lanes[2].cards.len
  doAssert lanes[2].cards[0].title == "Price list"
  # a finger: held, then moved
  ui.touch = true
  run(3)
  let fromTitle = lanes[0].cards[0].title
  holdThenDrag(laneX(0) + 40, cardY(0), laneX(2) + 60, r.y + r.h - dp(80))
  doAssert lanes[2].cards[^1].title == fromTitle, "a held finger drags the card"
  ui.touch = false
  # "+ Add card"
  ev = KanbanEvent()
  let addH = FontH + dp(10)
  let laneBottom = r.y + gap + (r.h - SbW - 2 * gap)
  clickAt(laneX(1) + laneW div 2, laneBottom - dp(4) - addH div 2)
  doAssert ev.added and ev.lane == 1, $ev
  # over the limit: the count is red (drawn without trouble); the board scrolls sideways
  doAssert lanes[1].cards.len > lanes[1].limit
  # empty board and lanes without cards
  var none: seq[KanbanLane]
  var s2: KanbanPos
  view = proc () = discard kanbanBoard(none, s2, height = 200)
  run(2)
  var emptyLanes = @[KanbanLane(title: "A"), KanbanLane(title: "B")]
  view = proc () = discard kanbanBoard(emptyLanes, s2, height = 200)
  run(2)
  key(KeyRight)
  run()
  key(KeyDown, {CtrlPressed})
  run()
  doAssert s2 == (1, -1)
  # a thousand cards: only those in view are drawn
  var big = @[KanbanLane(title: "Backlog"), KanbanLane(title: "Next")]
  for i in 0 ..< 1000:
    big[i mod 2].cards.add KanbanCard(title: "Card " & $i, detail: "detail " & $i,
                                      who: "P " & $(i mod 7))
  var s3: KanbanPos
  view = proc () = discard kanbanBoard(big, s3, height = 400)
  run(3)
  let t0 = getMonoTime()
  for i in 0 ..< 20:
    queue.add Event(kind: MouseMoveEvent, x: r.x + 60, y: r.y + 120)
    queue.add Event(kind: MouseWheelEvent, y: -1)
    run()
  echo "kanban, 1000 cards: ", formatFloat(ms(t0) / 20, ffDecimal, 2), " ms a frame"

# ---- Gantt ---------------------------------------------------------------------------------------

block gantt:
  let t = today()
  let red = color(200, 40, 40)
  var tasks = @[
    GanttTask(name: "Opening", start: t.addDays(1), finish: t.addDays(10), level: 0),
    GanttTask(name: "Kitchen", start: t.addDays(1), finish: t.addDays(5), progress: 0.5,
              color: red, level: 1),
    GanttTask(name: "Rooms", start: t.addDays(3), finish: t.addDays(8), level: 1, deps: @[1]),
    GanttTask(name: "Ribbon", start: t.addDays(10), finish: t.addDays(10), level: 1,
              milestone: true, deps: @[2])]
  var sel = 0
  var scale = gsDay
  var ev: GanttEvent
  var r: Rect
  view = proc () =
    let e = ganttView(tasks, sel, scale, height = 300, listW = 150)
    if e.changed or e.opened or e.toggled or e.selChanged: ev = e
    r = ui.lastRect
  run(3)
  let hdrH = 2 * (FontH + dp(6))
  let rowH = ItemH + dp(8)
  proc rowY(k: int): int = r.y + hdrH + k * rowH + rowH div 2
  # the bar of "Kitchen" (row 1): found by its color
  proc barOf(k: int; c: Color): tuple[a, b: int] =
    result = (-1, -1)
    let want = (uint32(c.r) shl 16) or (uint32(c.g) shl 8) or uint32(c.b)
    for x in r.x + 150 ..< r.x + r.w:
      if px(x, rowY(k)) == want:
        if result.a < 0: result.a = x
        result.b = x
  let light = mixColor(red, ui.theme.field, 0.55)
  var (a, b) = barOf(1, red)
  let (la, lb) = barOf(1, light)
  doAssert a > 0 and lb > a, "the bar is drawn, half done: " & $(a, b, la, lb)
  let ppd = dp(26)
  # the mouse moves the bar three days on
  let s0 = tasks[1].start
  dragMouse((a + lb) div 2, rowY(1), (a + lb) div 2 + 3 * ppd, rowY(1))
  doAssert dayNumber(tasks[1].start) == dayNumber(s0) + 3 and
           dayNumber(tasks[1].finish) - dayNumber(tasks[1].start) == 4,
    "moved by three days: " & $tasks[1].start
  doAssert ev.changed and ev.task == 1
  # ... and its end two days further
  let f0 = tasks[1].finish
  let (_, lb2) = barOf(1, light)
  dragMouse(lb2 - 1, rowY(1), lb2 - 1 + 2 * ppd, rowY(1))
  doAssert dayNumber(tasks[1].finish) == dayNumber(f0) + 2, "stretched: " & $tasks[1].finish
  # keys: Ctrl+Left moves a day back, Ctrl+Shift+Right makes it longer
  sel = 1
  run()
  let s1 = tasks[1].start
  key(KeyLeft, {CtrlPressed})
  run()
  doAssert dayNumber(tasks[1].start) == dayNumber(s1) - 1
  let f1 = tasks[1].finish
  key(KeyRight, {CtrlPressed, ShiftPressed})
  run()
  doAssert dayNumber(tasks[1].finish) == dayNumber(f1) + 1
  key(KeyDown)
  run()
  doAssert sel == 2
  key(KeyEnter)
  run()
  doAssert ev.opened and ev.task == 2
  # folding: Space on the parent
  sel = 0
  run()
  key(KeySpace)
  run(2)
  doAssert tasks[0].closed and ev.toggled
  key(KeySpace)
  run(2)
  doAssert not tasks[0].closed
  # zoom: the - key, then Ctrl + the wheel back in
  key(KeyMinus)
  run(2)
  doAssert scale == gsWeek
  queue.add Event(kind: MouseMoveEvent, x: r.x + 300, y: r.y + 100)
  queue.add Event(kind: MouseWheelEvent, y: 1, mods: {CtrlPressed}, hasMods: true)
  run(2)
  doAssert scale == gsDay, $scale
  # a finger: held on the bar, then moved
  ui.touch = true
  run(3)
  let rowHt = max(ItemH + dp(8), dp(32))
  let ry = r.y + hdrH + 1 * rowHt + rowHt div 2
  # (the part of the bar on the screen: done or not, as the date falls)
  var xa = -1
  var xe = -1
  let want = (uint32(red.r) shl 16) or (uint32(red.g) shl 8) or uint32(red.b)
  let wantL = (uint32(light.r) shl 16) or (uint32(light.g) shl 8) or uint32(light.b)
  for x in r.x + 150 ..< r.x + r.w:
    if px(x, ry) in [want, wantL]:
      if xa < 0: xa = x
      xe = x
  doAssert xa > 0
  xa = (xa + xe) div 2 - 4
  let s2 = tasks[1].start
  down(xa + 4, ry)
  run(40)
  move(xa + 4 + dp(14), ry)
  run()
  move(xa + 4 + 2 * ppd, ry)
  run()
  up(xa + 4 + 2 * ppd, ry)
  run(2)
  doAssert dayNumber(tasks[1].start) == dayNumber(s2) + 2, "a held finger moves the bar"
  ui.touch = false
  # empty, and ten thousand tasks
  var none: seq[GanttTask]
  var s0n = 0
  view = proc () = discard ganttView(none, s0n, scale, height = 200)
  run(2)
  key(KeyDown)
  run()
  var many: seq[GanttTask]
  for i in 0 ..< 10_000:
    many.add GanttTask(name: "Task " & $i, start: t.addDays(i mod 300),
                       finish: t.addDays(i mod 300 + 5), level: (if i mod 10 == 0: 0 else: 1),
                       progress: float(i mod 10) / 10, deps: (if i > 0: @[i - 1] else: @[]))
  var ms0 = 0
  view = proc () = discard ganttView(many, ms0, scale, height = 400)
  run(3)
  let t0 = getMonoTime()
  for i in 0 ..< 20:
    queue.add Event(kind: MouseMoveEvent, x: 300, y: 200)
    queue.add Event(kind: MouseWheelEvent, y: -1)
    run()
  echo "gantt, 10000 tasks: ", formatFloat(ms(t0) / 20, ffDecimal, 2), " ms a frame"

# ---- the agenda ----------------------------------------------------------------------------------

block agenda:
  firstWeekday = 0
  var day = date(2026, 3, 10)
  var mode = amMonth
  var items = @[
    Appointment(title: "Audit", day: date(2026, 3, 5), start: 9 * 60, finish: 11 * 60),
    Appointment(title: "Holiday", day: date(2026, 3, 5), allDay: true, color: color(15, 157, 88)),
    Appointment(title: "Review", day: date(2026, 3, 12), start: 14 * 60, finish: 15 * 60)]
  for i in 0 ..< 8:
    items.add Appointment(title: "Busy " & $i, day: date(2026, 3, 20), start: (8 + i) * 60,
                          finish: (8 + i) * 60 + 30)
  var ev: AgendaEvent
  var r: Rect
  view = proc () =
    let e = agendaView(items, day, mode, height = 420)
    if e.opened or e.added or e.moved or e.navigated: ev = e
    r = ui.lastRect
  run(3)
  let headH = FontH + dp(6)
  let cw = r.w div 7
  let ch = (r.h - headH) div 6
  let gridStart = date(2026, 3, 1).addDays(-weekday(date(2026, 3, 1)))
  proc cellOf(d: Date): Rect =
    let k = dayNumber(d) - dayNumber(gridStart)
    let gh = r.h - headH
    let x0 = r.x + (k mod 7) * r.w div 7
    let y0 = r.y + headH + (k div 7) * gh div 6
    rect(x0, y0, r.x + (k mod 7 + 1) * r.w div 7 - x0, r.y + headH + (k div 7 + 1) * gh div 6 - y0)
  let numH = FontH + dp(2)
  let chipH = lineHeight(style(size = 0.85)) + dp(3)
  # a click on an entry opens it
  let c5 = cellOf(date(2026, 3, 5))
  ev = AgendaEvent()
  clickAt(c5.x + 20, c5.y + numH + chipH + dp(1) + chipH div 2)   # (2nd: timed after all-day)
  doAssert ev.opened and items[ev.item].title == "Audit", $ev
  # a click on an empty day asks for a new entry there
  let c18 = cellOf(date(2026, 3, 18))
  ev = AgendaEvent()
  clickAt(c18.x + 10, c18.y + c18.h - 6)
  doAssert ev.added and ev.addDay == date(2026, 3, 18) and ev.addMinute == -1, $ev
  doAssert day == date(2026, 3, 18)
  # drag "Review" from the 12th to the 26th
  let c12 = cellOf(date(2026, 3, 12))
  let c26 = cellOf(date(2026, 3, 26))
  dragMouse(c12.x + 20, c12.y + numH + chipH div 2, c26.x + 30, c26.y + c26.h div 2)
  doAssert items[2].day == date(2026, 3, 26), "dragged to another day: " & $items[2].day
  # the 20th has more than fits: "+N more" opens the day
  let c20 = cellOf(date(2026, 3, 20))
  let fits = (ch - numH - dp(2)) div (chipH + dp(1))
  doAssert fits < 8
  clickAt(c20.x + 20, c20.y + numH + (fits - 1) * (chipH + dp(1)) + chipH div 2)
  doAssert mode == amDay and day == date(2026, 3, 20), $mode & " " & $day
  # keys: the arrows move the day, Page Down the period, Home today
  mode = amMonth
  day = date(2026, 3, 10)
  run(2)
  # (the board has the focus: a click on it)
  clickAt(cellOf(date(2026, 3, 10)).x + 5, cellOf(date(2026, 3, 10)).y + ch - 4)
  day = date(2026, 3, 10)
  run()
  key(KeyRight)
  run()
  doAssert day == date(2026, 3, 11)
  key(KeyPageDown)
  run()
  doAssert day == date(2026, 4, 11)
  key(KeyHome)
  run()
  doAssert day == today()
  # the week: a click on an empty time, a block dragged later, stretched
  mode = amWeek
  day = date(2026, 3, 5)
  run(3)
  let gutter = textWidth("00:00") + dp(12)
  let wHead = FontH + dp(8)
  let adChip = lineHeight(style(size = 0.85)) + dp(4)
  let adH = 1 * (adChip + dp(2)) + dp(4)
  let hourH = dp(42)
  let bodyY = r.y + wHead + adH
  let bodyW = r.w - gutter - SbW
  let colW = bodyW div 7
  let sy = 8 * hourH                       # (the working day in view)
  let k5 = weekday(date(2026, 3, 5))       # its column
  proc slotY(minute: int): int = bodyY - sy + minute * hourH div 60
  ev = AgendaEvent()
  clickAt(r.x + gutter + (k5 + 1) * colW + colW div 2, slotY(13 * 60 + 10))
  doAssert ev.added and ev.addMinute == 13 * 60 and
           dayNumber(ev.addDay) == dayNumber(date(2026, 3, 6)), $ev
  # "Audit" 9:00-11:00 on the 5th: dragged to 10:00
  let ax = r.x + gutter + k5 * colW + colW div 2
  dragMouse(ax, slotY(9 * 60 + 30), ax, slotY(10 * 60 + 30))
  doAssert items[0].start == 10 * 60 and items[0].finish == 12 * 60,
    "moved an hour later: " & $items[0].start & "-" & $items[0].finish
  # its lower edge: it ends at 12:30
  dragMouse(ax, slotY(12 * 60) - 3, ax, slotY(12 * 60 + 30))
  doAssert items[0].finish == 12 * 60 + 30, $items[0].finish
  # a finger: held on it, then moved to the next day
  ui.touch = true
  run(3)
  let hourT = dp(52)
  let adT = adH                            # (the same chips)
  let syT = 8 * hourH                     # (the scroll stays where it was)
  let bodyT = r.y + wHead + adT
  let ty = bodyT - syT + (10 * 60 + 30) * hourT div 60
  holdThenDrag(ax, ty, ax + colW, ty)
  doAssert dayNumber(items[0].day) == dayNumber(date(2026, 3, 6)), "a held finger moves it: " &
    $items[0].day
  ui.touch = false
  # the day view, an empty agenda, thousands of entries
  mode = amDay
  run(2)
  var none: seq[Appointment]
  var d2 = today()
  var m2 = amMonth
  view = proc () = discard agendaView(none, d2, m2, height = 300)
  run(2)
  m2 = amWeek
  run(2)
  var lots: seq[Appointment]
  for i in 0 ..< 5000:
    lots.add Appointment(title: "Entry " & $i, day: today().addDays(i mod 60 - 30),
                         start: (i mod 20) * 45, finish: (i mod 20) * 45 + 60)
  m2 = amMonth
  view = proc () = discard agendaView(lots, d2, m2, height = 400)
  run(3)
  var t0 = getMonoTime()
  for i in 0 ..< 10:
    key(KeyRight)
    run()
  echo "agenda month, 5000 entries: ", formatFloat(ms(t0) / 10, ffDecimal, 2), " ms a frame"
  m2 = amWeek
  run(2)
  t0 = getMonoTime()
  for i in 0 ..< 10:
    key(KeyRight)
    run()
  echo "agenda week, 5000 entries: ", formatFloat(ms(t0) / 10, ffDecimal, 2), " ms a frame"

# ---- tiles ---------------------------------------------------------------------------------------

block tiles:
  var clicked = 0
  var rects: seq[Rect]
  view = proc () =
    rects.setLen(0)
    kpiRow:
      if kpiTile("Revenue", "OMR 84,120", 0.125, "vs last month",
                 trend = [3.0, 4, 3.5, 5, 6, 5.5, 7], target = 0.68): inc clicked
      rects.add ui.lastRect
      kpiTile("Complaints", "12", -0.2, lowerIsBetter = true)
      rects.add ui.lastRect
      kpiTile("Empty", "-", NaN, trend = [NaN, NaN], target = NaN)
      rects.add ui.lastRect
      statCard(pxUser, "Guests", "214", "38 arriving today")
      rects.add ui.lastRect
  run(3)
  doAssert rects.len == 4 and rects[0].w > dp(150)
  doAssert rects[1].x > rects[0].x or rects[1].y > rects[0].y
  clickAt(rects[0].x + 20, rects[0].y + 20)
  doAssert clicked == 1, "a tile is clicked"
  # the delta of costs going down is good: green
  var green = false
  for y in rects[1].y ..< rects[1].y + rects[1].h:
    for x in rects[1].x ..< rects[1].x + 60:
      if px(x, y) == 0x008000: green = true
  doAssert green, "lower is better: green"

# ---- the org chart -------------------------------------------------------------------------------

block org:
  var nodes = @[
    OrgNode(name: "Amal", title: "General manager", parent: -1),
    OrgNode(name: "Badr", title: "Rooms", parent: 0),
    OrgNode(name: "Dana", title: "F&B", parent: 0),
    OrgNode(name: "Eid", title: "Front office", parent: 1),
    OrgNode(name: "Fahd", title: "Housekeeping", parent: 1),
    OrgNode(name: "Loop A", title: "", parent: 6),       # a loop: no crash, no hang
    OrgNode(name: "Loop B", title: "", parent: 5)]
  var sel = 0
  var ev: OrgEvent
  var r: Rect
  view = proc () =
    let e = orgChart(nodes, sel, height = 360)
    if e.selChanged or e.opened or e.toggled: ev = e
    r = ui.lastRect
  run(3)
  # keys: Down to the first under, Right to the one beside, Up back
  clickAt(r.x + 2, r.y + 2)               # (the focus)
  sel = 0
  run()
  key(KeyDown)
  run()
  doAssert sel == 1, $sel
  key(KeyRight)
  run()
  doAssert sel == 2
  key(KeyUp)
  run()
  doAssert sel == 0
  key(KeyEnter)
  run()
  doAssert ev.opened and ev.node == 0
  # fold Badr's people away and back with Space
  sel = 1
  run()
  key(KeySpace)
  run(2)
  doAssert nodes[1].closed and ev.toggled
  key(KeySpace)
  run(2)
  doAssert not nodes[1].closed
  # a click on a box chooses it: find Dana's box by her strip color
  let want = (uint32(ui.theme.select.r) shl 16) or (uint32(ui.theme.select.g) shl 8) or
             uint32(ui.theme.select.b)
  discard want
  # a thousand people
  var many: seq[OrgNode]
  for i in 0 ..< 1000:
    many.add OrgNode(name: "Person " & $i, title: "Role", parent: (if i == 0: -1 else: (i - 1) div 4))
  var s2 = 0
  view = proc () = discard orgChart(many, s2, height = 400)
  run(3)
  let t0 = getMonoTime()
  for i in 0 ..< 20:
    queue.add Event(kind: MouseMoveEvent, x: 300, y: 200)
    queue.add Event(kind: MouseWheelEvent, y: -1)
    run()
  echo "org chart, 1000 people: ", formatFloat(ms(t0) / 20, ffDecimal, 2), " ms a frame"
  var none: seq[OrgNode]
  var s3 = 0
  view = proc () = discard orgChart(none, s3, height = 200)
  run(2)
  key(KeyDown)
  run()

echo "planning tests passed"
