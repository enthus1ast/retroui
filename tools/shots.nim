## Renders every control of Retro Nim UI in its states -- normal, with the
## keyboard focus, under the mouse, pressed, disabled, open, on a touch
## screen, in a dark color scheme -- into docs/controls/*.png, and writes
## docs/controls.md: for each control its description and signature (read
## from the doc comments in src/), the example code (the very code that
## drew the pictures) and the pictures.
##
##   nim c -r -d:release tools/shots.nim        (from the repository's root)
##
## Headless: a fake screen driver, the built-in fonts, no window.

import std/[os, strutils, tables, algorithm, sequtils, json, math]
import retro
import retro/uirelays/[coords, screen, input]

# ---- a fake screen of any size ---------------------------------------------------------------------

var
  W = 360
  H = 120
  touchNow = false
  pixels: seq[uint32]
  queue: seq[Event]
  ticks = 1000
  clip = ""
  view: proc ()

proc fakeDriver() =
  windowRelays.createWindow = proc (l: var ScreenLayout; icon: pointer; iconLen: int) =
    l.width = W; l.height = H; l.scaleX = 1; l.scaleY = 1; l.uiScale = 100
  windowRelays.getWindowLayout = proc (): ScreenLayout =
    ScreenLayout(width: W, height: H, scaleX: 1, scaleY: 1, uiScale: 100, touch: touchNow)
  windowRelays.refresh = proc () = discard
  windowRelays.setWindowTitle = proc (t: string) = discard
  windowRelays.setCursor = proc (c: CursorKind) = discard
  drawRelays.blitRGBA = proc (p: ptr UncheckedArray[uint32]; w, h: int;
                              dst: Rect; f: RGBAFormat): bool =
    for y in 0 ..< h:
      for x in 0 ..< w:
        let i = (dst.y + y) * W + dst.x + x
        if i >= 0 and i < pixels.len: pixels[i] = p[y * w + x]
    true
  inputRelays.pollEvent = proc (e: var Event; fl: set[InputFlag]): bool =
    if queue.len == 0: return false
    e = queue[0]
    queue.delete(0)
    true
  inputRelays.waitEvent = proc (e: var Event; t: int; fl: set[InputFlag]): bool =
    inputRelays.pollEvent(e, fl)
  inputRelays.getTicks = proc (): int = ticks
  inputRelays.shutdown = proc () = discard
  clipboardRelays.getText = proc (): string = clip
  clipboardRelays.putText = proc (t: string) = clip = t
  fontRelays.openFont = proc (path: string; size: int; style: FontStyles;
                              metrics: var FontMetrics): Font = Font(0)
  fontRelays.closeFont = proc (f: Font) = discard
  fontRelays.getFontMetrics = proc (f: Font): FontMetrics = FontMetrics()
  fontRelays.measureText = proc (f: Font; text: string): TextExtent = TextExtent()
  fontRelays.drawText = proc (f: Font; x, y: int; text: string;
                              fg, bg: Color): TextExtent = TextExtent()
  fontRelays.drawMeasuredText = nil

proc run(n = 1) =
  var i = 0
  while i < n or queue.len > 0:
    if i > 200:
      echo "too many frames; queue: ", queue.len
      quit 1
    if not beginFrame():
      echo "the app ended"
      quit 1
    view()
    endFrame()
    inc i
    ticks += 16

proc resize(w, h: int; touch: bool) =
  W = w
  H = h
  touchNow = touch
  pixels = newSeq[uint32](W * H)
  queue.add Event(kind: WindowResizeEvent, x: W, y: H)
  run(2)

# ---- the controls ----------------------------------------------------------------------------------

type
  ShotState = enum
    ssNormal = "Normal", ssFocused = "Keyboard focus", ssHover = "Mouse over",
    ssPressed = "Pressed", ssOpen = "Clicked / open", ssDisabled = "Disabled",
    ssTouch = "Touch screen", ssDark = "Dark scheme"
  Shot = object
    name, category, title: string
    apis: seq[string]
    w, h: int
    states: seq[ShotState]
    code: string
    draw: proc ()

var
  shots: seq[Shot]
  shotEnabled = true          ## false while the Disabled picture is drawn
  target: Rect                ## where the mouse goes (`aim` after the widget)
  aimed = false

template aim() =
  ## The widget drawn last is the one the mouse goes to.
  target = ui.lastRect
  aimed = true

template aimAt(fx, fy: float) =
  ## The mouse goes to this point of the widget drawn last (fractions of
  ## its width and height).
  target = rect(ui.lastRect.x + int(ui.lastRect.w.float * fx),
                ui.lastRect.y + int(ui.lastRect.h.float * fy), 0, 0)
  aimed = true

const
  basic = @[ssNormal, ssFocused, ssHover, ssPressed, ssDisabled, ssTouch, ssDark]
  basicNoHover = @[ssNormal, ssFocused, ssPressed, ssDisabled, ssTouch, ssDark]
  static3 = @[ssNormal, ssTouch, ssDark]
  input4 = @[ssNormal, ssFocused, ssDisabled, ssTouch, ssDark]
  popup4 = @[ssNormal, ssFocused, ssOpen, ssTouch, ssDark]

template example(nm, cat, ttl: string; ww, hh: int; apiNames: openArray[string];
                 st: seq[ShotState]; body: untyped) =
  shots.add Shot(name: nm, category: cat, title: ttl, apis: @apiNames, w: ww, h: hh,
                 states: st, code: astToStr(body), draw: proc () = body)

# state the examples are bound to
var
  okClicks = 0
  autoSave = true
  backups = false
  size = 1
  wifi = true
  view2 = 1
  stars = 3
  tags = @["nim", "retro", "ui"]
  tagOn = @[true, false, false]
  name = "Sultan"
  secret = "hunter2"
  notes = "Line one\nLine two\nLine three"
  query = "invoices"
  phone = "96891234"
  city = "Ber"
  hotkey = "Ctrl+Shift+S"
  copies = 2
  qty = 12
  amount = 1234.5
  volume = 40
  day = date(2026, 10, 27)
  fromDay = date(2026, 10, 1)
  toDay = date(2026, 10, 31)
  hh = 9
  mm = 30
  pick = color(0, 128, 128)
  fruits = @["Apple", "Banana", "Cherry", "Dates", "Figs", "Grapes"]
  fruit = 1
  fruitCombo = 2
  checks = @[true, false, true, false]
  cols = @[column("Item", 130), numberColumn("Qty", 50), numberColumn("Price", 70)]
  gridSel = 1
  orderCols = @[column("Order", 120), numberColumn("Amount", 70), colorColumn("DA", 30),
                colorColumn("PD", 30), checkColumn("S", 28),
                choiceColumn("Store", ["Engineering", "Kitchen", "Cafeteria"], 100),
                buttonColumn("", 56)]
  orders = @[@["Pool glass door", "70.000", "green", "green", "1", "Engineering", "Open"],
             @["Stewarding", "51.800", "green", "blue", "0", "Kitchen", "Open"],
             @["Bread for canteen", "54.155", "orange", "green", "0", "Cafeteria", "Open"]]
  orderSel = 0
  treeSel = "My computer/Documents"
  treeOpen = true
  treeOpen2 = false
  iconSel = 0
  iconMarked: seq[bool]
  logSel = 3
  avail = @["Cash", "Bank", "Sales"]
  chosen = @["Rent", "Salaries"]
  props = @[textProp("Name", "Main store", "General", "What the store is called"),
            boolProp("Active", true, "General"),
            choiceProp("Region", ["North", "South", "East"], 1, "General"),
            numberProp("Budget", 1500.5, 2, "Money"),
            colorProp("Label", color(0, 128, 0), "Look")]
  propSel = 0
  accCols = @[column("Account", 170), numberColumn("Balance", 90)]
  accRows = @[TreeRow(level: 0, cells: @["Assets", "15,000.00"], open: true),
              TreeRow(level: 1, cells: @["Cash", "5,000.00"]),
              TreeRow(level: 1, cells: @["Bank", "10,000.00"]),
              TreeRow(level: 0, cells: @["Liabilities", "4,000.00"])]
  accSel = 1
  recPos = 2
  tabSel = 0
  docTab = 0
  docTabs = @["Report.txt", "Notes.md", "Budget.csv"]
  more = true
  split1 = 140
  paneW = 150
  paneH = 100
  dlgOpen = true
  msgOpen = true
  inputOpen = true
  inputText = "Untitled"
  wizOpen = true
  wizStep = 1
  aboutOpen = true
  page = 3
  nav = 0
  setOn = true
  setChoice = 1
  setLevel = 60
  setCombo = 0
  findState = FindState(open: true, what: "cat", replacing: true)
  mdi1 = MdiWindow(title: "Accounts", r: rect(8, 8, 200, 110), open: true)
  mdi2 = MdiWindow(title: "Invoices", r: rect(120, 50, 200, 110), open: true)
  mdi3 = MdiWindow(title: "Notes", open: true, minimized: true)
  stepAt = 1
  zoomV = 0.0

# Text
example("label", "Text", "label, paragraph, heading", 360, 120, ["label", "paragraph", "heading"], static3):
  heading("Quarterly report", 2)
  label "&Name: (a label with a mnemonic)"
  paragraph("A paragraph wraps to the room it has, as 3.1's static text did.")
example("styledtext", "Text", "styledText, link, badge", 360, 90, ["styledText", "link", "badge"], static3):
  styledText("Bold, italic and mono", style(bold = true))
  styledText("Italic, underlined", style(italic = true, underline = true))
  row:
    if link("Open the website"): discard
    badge("3")
    badge("NEW", color(0, 128, 0))
example("icons", "Text", "icon, iconLabel (pixel icons and Nerd icons)", 360, 90, ["icon", "iconLabel"], static3):
  row:
    for g in [pxFolder, pxComputer, pxTrashFull, pxWarning, pxPrint, pxSave]: icon(g, size = 2.0)
  iconLabel(pxDocuments, "Documents")
  iconLabel(nfGithub, "Nerd Fonts icons too", iconColor = color(0, 0, 128))

# Buttons
example("button", "Buttons", "button", 300, 60, ["button"], basic):
  row:
    if button("&OK", isDefault = true, enabled = shotEnabled): inc okClicks
    aim()
    button("Cancel", enabled = shotEnabled)
example("toolbar", "Buttons", "toolbar, toolButton, toolSeparator", 360, 70, ["toolbar", "toolButton", "toolSeparator"], @[ssNormal, ssHover, ssPressed, ssTouch, ssDark]):
  toolbar:
    toolButton(pxNew, "New")
    aim()
    toolButton(pxOpen, "Open")
    toolButton(pxSave, "Save", enabled = shotEnabled)
    toolSeparator()
    toolButton(pxCut, "Cut")
    toolButton(pxCopy, "Copy")
    toolButton(pxPaste, "Paste", down = true)
example("segmented", "Buttons", "segmented", 300, 60, ["segmented"], basicNoHover):
  segmented(["Day", "Week", "Month"], view2, enabled = shotEnabled)
  aim()

# Choices
example("checkbox", "Choices", "checkbox", 300, 70, ["checkbox"], basicNoHover):
  checkbox("&Auto save", autoSave, enabled = shotEnabled)
  aim()
  checkbox("Keep &backups", backups, enabled = shotEnabled)
example("radio", "Choices", "radio", 300, 90, ["radio"], basicNoHover):
  radio("&Small", size, 0, enabled = shotEnabled)
  radio("&Medium", size, 1, enabled = shotEnabled)
  aim()
  radio("&Large", size, 2, enabled = shotEnabled)
example("toggle", "Choices", "toggle (a 3.1 slide switch)", 300, 60, ["toggle", "switchSize"], basicNoHover):
  toggle("&Wi-Fi", wifi, enabled = shotEnabled)
  aim()
example("chips", "Choices", "chips", 340, 60, ["chips"], @[ssNormal, ssFocused, ssHover, ssTouch, ssDark]):
  let ev = chips(tags, tagOn, closable = true, enabled = shotEnabled)
  aimAt(0.5, 0.5)
  if ev.clicked >= 0: tagOn[ev.clicked] = not tagOn[ev.clicked]
example("rating", "Choices", "rating", 300, 60, ["rating"], basic):
  rating(stars, enabled = shotEnabled)
  aim()

# Text input
example("edit", "Text input", "edit", 320, 90, ["edit"], @[ssNormal, ssFocused, ssDisabled, ssTouch, ssDark]):
  form 0:
    field "&Name:": edit(name, enabled = shotEnabled)
    field "&Password:": edit(secret, password = true, enabled = shotEnabled)
example("editarea", "Text input", "editArea", 320, 110, ["editArea"], input4):
  editArea(notes, lines = 4, enabled = shotEnabled)
example("searchbox", "Text input", "searchBox", 320, 60, ["searchBox"], input4):
  searchBox(query, "Search invoices", enabled = shotEnabled)
example("maskededit", "Text input", "maskedEdit", 320, 60, ["maskedEdit", "maskFormat", "maskFull", "maskRaw"], input4):
  row:
    label "&Phone:"
    maskedEdit(phone, "+### #### ####", enabled = shotEnabled)
example("comboedit", "Text input", "comboEdit (suggests as you type)", 320, 170, ["comboEdit"], @[ssNormal, ssOpen, ssTouch, ssDark]):
  comboEdit(city, ["Berlin", "Bern", "Beirut", "Muscat", "Sohar"], w = 180, enabled = shotEnabled)
  aim()
example("hotkeyedit", "Text input", "hotkeyEdit", 320, 60, ["hotkeyEdit", "hotkeyText", "parseHotkey", "hotkeyPressed"], input4):
  row:
    label "&Save as:"
    hotkeyEdit(hotkey, enabled = shotEnabled)

# Numbers, dates, colors
example("numbers", "Numbers, dates, colors", "spin, intEdit, numberEdit", 340, 100, ["spin", "intEdit", "numberEdit"], input4):
  form 0:
    field "&Copies:": spin(copies, 1, 99, enabled = shotEnabled)
    field "&Quantity:": intEdit(qty, enabled = shotEnabled)
    field "&Amount:": numberEdit(amount, enabled = shotEnabled)
example("slider", "Numbers, dates, colors", "slider, progress", 340, 80, ["slider", "progress"], basicNoHover):
  slider(volume, 0, 100, enabled = shotEnabled)
  aim()
  progress(0.62)
example("datepicker", "Numbers, dates, colors", "datePicker", 320, 230, ["datePicker"], @[ssNormal, ssFocused, ssOpen, ssDisabled, ssTouch, ssDark]):
  datePicker(day, enabled = shotEnabled)
  aim()
example("calendar", "Numbers, dates, colors", "calendar", 300, 210, ["calendar"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  calendar(day, enabled = shotEnabled)
example("daterange", "Numbers, dates, colors", "dateRange, presetRange", 460, 60, ["dateRange", "presetRange"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  dateRange(fromDay, toDay)
example("timepicker", "Numbers, dates, colors", "timePicker", 300, 60, ["timePicker"], input4):
  timePicker(hh, mm, enabled = shotEnabled)
example("colorpicker", "Numbers, dates, colors", "colorPicker", 320, 180, ["colorPicker"], @[ssNormal, ssFocused, ssDisabled, ssDark]):
  colorPicker(pick, enabled = shotEnabled)

# Lists
example("listbox", "Lists", "listbox", 260, 130, ["listbox"], @[ssNormal, ssFocused, ssHover, ssDisabled, ssTouch, ssDark]):
  listbox(fruits, fruit, rows = 5, enabled = shotEnabled)
  aim()
example("combo", "Lists", "combo", 260, 190, ["combo"], @[ssNormal, ssFocused, ssOpen, ssDisabled, ssTouch, ssDark]):
  combo(fruits, fruitCombo, w = 160, enabled = shotEnabled)
  aim()
example("checklist", "Lists", "checkList", 260, 110, ["checkList"], input4):
  checkList(["Cash", "Bank", "Cards", "Vouchers"], checks, rows = 4, enabled = shotEnabled)
example("grid", "Lists", "grid", 300, 120, ["grid", "column", "sortRows", "gridEdit"], @[ssNormal, ssFocused, ssDisabled, ssTouch, ssDark]):
  grid(cols, @[@["Paper", "10", "4.50"], @["Ink", "2", "21.00"], @["Pens", "40", "0.80"]],
       gridSel, height = 4, enabled = shotEnabled)
example("datagrid", "Lists", "grid with cell kinds, colors, record indicator and totals", 600, 150, ["numberColumn", "checkColumn", "colorColumn", "choiceColumn", "buttonColumn", "progressColumn", "linkColumn", "iconColumn", "customColumn", "cellStyle", "namedColor", "isChecked"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  grid(orderCols, orders.len, proc (r, c: int): string = orders[r][c], orderSel,
       height = 3, rowHeaders = true,
       style = proc (r, c: int): CellStyle =
         (if c == 1 and r == 0: cellStyle(fg = color(200, 0, 0), bold = true) else: CellStyle()),
       footer = proc (c: int): string =
         (if c == 0: "Total" elif c == 1: "175.955" else: ""))
example("tree", "Lists", "tree, branch, leaf", 260, 150, ["tree", "branch", "leaf", "beginTree", "beginNode"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  tree(treeSel, 7):
    branch("My computer", treeOpen):
      leaf("Documents")
      branch("Pictures", treeOpen2):
        leaf("Holidays")
      leaf("Music")
example("treegrid", "Lists", "treeGrid", 300, 130, ["treeGrid"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  treeGrid(accCols, accRows, accSel, height = 4)
example("iconview", "Lists", "iconView", 360, 150, ["iconView"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  iconView(6, proc (i: int): string = ["Reports", "Budget", "Photos", "Music", "Notes", "Setup"][i],
           proc (i: int; r: Rect) =
             let g = [pxFolder, pxSheet, pxPictures, pxMusic, pxText, pxApp][i]
             image(r.x + (r.w - 32) div 2, r.y + (r.h - 32) div 2, glyphIcon(g, ui.theme.text, 32)),
           iconSel, iconMarked, height = 130)
example("lineview", "Lists", "lineView (huge texts, logs)", 340, 110, ["lineView"], @[ssNormal, ssFocused, ssDark]):
  lineView(100000, proc (i: int): string = "2026-10-27 10:" & $(i mod 60) & " request " & $i & " ok",
           logSel, height = 100, numbers = true)
example("duallist", "Lists", "dualList", 640, 200, ["dualList"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  dualList(avail, chosen, rows = 5)
example("propertygrid", "Lists", "propertyGrid", 320, 250, ["propertyGrid", "textProp", "numberProp", "intProp", "boolProp", "choiceProp", "colorProp", "dateProp", "infoProp", "valueText"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  propertyGrid(props, propSel, height = 220)

# Status
example("status", "Progress and status", "progressRing, spinner, sparkline, usageBar", 360, 100, ["progressRing", "spinner", "sparkline", "usageBar"], static3):
  row:
    progressRing(0.62)
    spinner()
    col:
      sparkline([3.0, 5, 4, 7, 6, 9, 8, 11], w = 140, h = 30)
      usageBar(62, 100, w = 140)
example("banner", "Progress and status", "banner", 420, 90, ["banner"], @[ssNormal, ssHover, ssTouch, ssDark]):
  discard banner("A new version is ready.", bkInfo, ["Update"])
  aimAt(0.8, 0.5)
  discard banner("Low on storage: 300 MB left.", bkWarning, closable = false)
example("emptystate", "Progress and status", "emptyState, busyState", 360, 110, ["emptyState", "busyState"], static3):
  row([-1, -1]):
    emptyState(pxInbox, "No messages", 100)
    busyState("Loading...", 100)
example("statusbar", "Progress and status", "statusbar", 400, 60, ["statusbar"], static3):
  statusbar("Ready", "NUM", "12:30")

# Containers
example("group", "Containers", "group, card, separator", 380, 120, ["group", "card", "separator"], static3):
  row([-1, -1]):
    group("Group box"):
      label "In a 3.1 group box"
    card("Card"):
      label "A raised panel"
example("tabs", "Containers", "tabs", 340, 110, ["tabs", "beginTabs"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  tabs(tabSel, ["&General", "&Look", "&Advanced"], sameHeight = true):
    label("The page of tab " & $(tabSel + 1))
example("tabstrip", "Containers", "tabStrip (document tabs)", 400, 60, ["tabStrip"], @[ssNormal, ssFocused, ssHover, ssTouch, ssDark]):
  discard tabStrip(docTabs, docTab, [pxText, pxMarkdown, pxSheet])
  aimAt(0.45, 0.5)
example("expander", "Containers", "expander", 300, 90, ["expander"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  expander("Advanced settings", more):
    label "Hidden until it is opened"
example("form", "Containers", "form, field", 340, 100, ["form", "field"], static3):
  form 0:
    field "&Customer:": edit name
    field "&Amount:": numberEdit amount
example("split", "Containers", "split, vsplit", 360, 110, ["split", "vsplit", "splitBar"], static3):
  split(split1, 100):
    listbox(fruits, fruit, rows = -1)
  do:
    paragraph("Drag the bar between the panes.")
example("sidepane", "Containers", "sidePane", 400, 110, ["sidePane", "paneBeside"], static3):
  sidePane(true, paneW, paneH):
    listbox(fruits, fruit, rows = -1)
  do:
    factList({"Name": fruits[fruit], "Kind": "Fruit"})

# Menus and bars
example("menu", "Menus and bars", "menubar, menu, menuItem, submenu", 320, 180, ["menubar", "menu", "menuItem", "submenu", "menuSeparator"], @[ssNormal, ssOpen, ssTouch, ssDark]):
  menubar:
    menu "&File":
      discard menuItem("&New", "Ctrl+N")
      discard menuItem("&Open...", "Ctrl+O")
      menuSeparator()
      discard menuItem("&Save", "Ctrl+S", enabled = false)
      discard menuItem("&Word wrap", checked = true)
    menu "&Edit":
      discard menuItem("&Undo", "Ctrl+Z")
  target = rect(8, 2, 30, 14)
  aimed = true
example("breadcrumb", "Menus and bars", "breadcrumb", 380, 60, ["breadcrumb"], @[ssNormal, ssHover, ssTouch, ssDark]):
  breadcrumb(["C:", "Users", "Foxoman", "Documents"])
  aimAt(0.4, 0.5)
example("pager", "Menus and bars", "pager, stepper", 380, 100, ["pager", "stepper"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  pager(page, 12)
  discard stepper(["Cart", "Address", "Payment"], stepAt)
example("recordnav", "Menus and bars", "recordNav", 640, 60, ["recordNav"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  discard recordNav(recPos, 20, dirty = true)
example("findbar", "Menus and bars", "findBar, findIn, replaceAllIn", 760, 80, ["findBar", "findIn", "replaceAllIn"], @[ssNormal, ssTouch, ssDark]):
  discard findBar(findState)

# Dialogs
example("msgbox", "Dialogs", "msgBox", 400, 170, ["msgBox", "msgIcon"], @[ssNormal, ssTouch, ssDark]):
  discard msgBox(msgOpen, "Retro Files", "Delete \"Budget.csv\" for good?\nThis cannot be undone.",
                 ["&Delete", "Cancel"], miWarning)
example("inputbox", "Dialogs", "inputBox", 400, 160, ["inputBox"], @[ssNormal, ssTouch, ssDark]):
  discard inputBox(inputOpen, "Save as", "&File name:", inputText)
example("dialog", "Dialogs", "dialog", 400, 180, ["dialog", "beginDialog"], @[ssNormal, ssTouch, ssDark]):
  dialog(dlgOpen, "Page setup", 300):
    form 0:
      field "&Copies:": spin(copies, 1, 99)
      field "": checkbox("&Collate", autoSave)
    row:
      spring()
      if button("OK", isDefault = true): dlgOpen = true
      discard button("Cancel")
example("wizard", "Dialogs", "wizard, stepDone", 700, 260, ["wizard", "stepDone"], @[ssNormal, ssTouch, ssDark]):
  discard wizard(wizOpen, "New company", wizStep, ["Name", "Address", "Bank", "Done"], 480):
    label "&Street:"
    edit name
example("aboutbox", "Dialogs", "aboutBox", 500, 400, ["aboutBox"], @[ssNormal, ssDark]):
  aboutBox(aboutOpen, "Ledger", "2.0", ["(c) 2026 Foxoman. Small business accounts."],
           glyph = pxSheet, tagline = "Small business accounts",
           whatsNew = ["Invoices in PDF", "Bank files read"], credits = ["Fonts: Retro Sans (CC BY-SA 3.0)"])

# App parts and settings
example("settings", "App parts", "settingToggle, settingChoice, settingSlider, settingButtons, settingCombo, settingLink", 420, 260, ["settingToggle", "settingChoice", "settingSlider", "settingButtons", "settingCombo", "settingLink"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  settingToggle("Notifications", setOn, "For new messages")
  discard settingChoice("Sync", ["Hourly", "Daily", "Never"], setChoice)
  discard settingSlider("Brightness", setLevel, 0, 100, suffix = "%")
  discard settingCombo("Color scheme", ["Classic", "Ocean", "Desert"], setCombo)
  discard settingButtons("Cache", ["Clear"], "12 MB")
example("avatar", "App parts", "avatar, factList", 360, 100, ["avatar", "initialsOf", "factList"], static3):
  row:
    avatar("Sultan Al-Said")
    avatar("Maryam Ali")
    col:
      factList({"Orders": "10", "Best month": "May"})
example("bottomnav", "App parts", "bottomNav, fab (phone app parts)", 360, 160, ["bottomNav", "fab"], @[ssNormal, ssTouch, ssDark]):
  label "Content"
  discard bottomNav([(pxHome, "Home"), (pxSearch, "Search"), (pxUser, "Me")], nav)
  discard fab(nfPlus, "New")
example("mdi", "App parts", "mdiArea, mdiWindow, mdiWindowMenu", 380, 240, ["mdiArea", "mdiWindow", "mdiWindowMenu", "mdiCascade", "mdiTile", "mdiActivate", "MdiWindow"], @[ssNormal, ssTouch, ssDark]):
  mdiArea(-1):
    mdiWindow(mdi1):
      label "Cash   5,000"
      label "Bank  10,000"
    mdiWindow(mdi2):
      label "Invoice 42"
    mdiWindow(mdi3):
      label "Notes"

# Files
example("pathbar", "Files", "pathBar (as in Explorer: folders to click, arrows for their folders)", 480, 50, ["pathBar"], @[ssNormal, ssHover, ssTouch, ssDark]):
  discard pathBar("/home/sultan/Documents/Reports/2026")
  aimAt(0.3, 0.5)
example("drivebar", "Files", "driveBar (the drive buttons of File Manager)", 480, 50, ["driveBar"], @[ssNormal, ssHover, ssTouch, ssDark]):
  discard driveBar(getHomeDir(), ["/home/sultan/Projects"])

# Charts
var
  chMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
  salesTable = parseCsv("Month,Sales,Costs,Staff,Target,Open,High,Low,Close\n" &
                   "Jan,120,80,5,130,10,14,8,12\nFeb,150,95,6,140,12,15,10,11\n" &
                   "Mar,90,70,4,150,11,13,7,9\nApr,180,100,7,160,9,16,8,15\n" &
                   "May,210,120,8,170,15,19,13,18\nJun,250,130,9,180,18,22,16,17")

proc kindCols(k: ChartKind): seq[string] =
  case k
  of chScatter: @["Sales", "Costs"]
  of chBubble: @["Sales", "Costs", "Staff"]
  of chCandle: @["Open", "High", "Low", "Close"]
  of chBullet: @["Sales", "Target"]
  of chPie, chDonut, chFunnel, chTreemap, chWaterfall, chHistogram, chGauge: @["Sales"]
  of chHeatmap: @["Sales", "Costs", "Target"]
  else: @["Sales", "Costs"]

example("chart", "Charts", "chart", 440, 240, ["chart", "series", "lineSeries", "xySeries", "ohlcSeries", "chartColors"], @[ssNormal, ssFocused, ssHover, ssTouch, ssDark]):
  chart("Sales by month", chBar, chMonths,
        [series("2025", [120.0, 150, 90, 180, 210, 250]),
         series("2026", [140.0, 170, 130, 190, 240, 280])], height = 220)
  aimAt(0.77, 0.6)
example("chartcombo", "Charts", "a combo chart: bars, and a line on a second axis", 440, 240, [], @[ssNormal, ssDark]):
  chart(chCombo, chMonths,
        [series("Revenue", [120.0, 150, 90, 180, 210, 250]),
         lineSeries("Margin", [0.21, 0.25, 0.18, 0.27, 0.3, 0.33])],
        ChartOpts(title: "Revenue and margin", format: NumFormat(prefix: "$", suffix: "K"),
                  format2: NumFormat(percent: true), dataLabels: false), height = 220)
example("gauge", "Charts", "gauge", 260, 200, ["gauge"], @[ssNormal, ssDark]):
  gauge("Sales vs target", 78, hi = 100, target = 90, format = NumFormat(suffix: "%"),
        height = 180)
example("chartkinds", "Charts", "the 21 kinds of chart, from one CSV table", 960, 1200, ["parseCsv", "readCsv", "tableSeries", "exportPng"], @[ssNormal]):
  adaptive(230):
    for k in ChartKind:
      card($k):
        chart("", k, salesTable, "Month", kindCols(k), height = 150)

# Planning
var
  kanbanLanes = @[
    KanbanLane(title: "To do", cards: @[
      KanbanCard(title: "Price list", detail: "For the new menu", tag: color(219, 68, 55),
                 who: "Sultan Al-Said", due: date(2026, 10, 30)),
      KanbanCard(title: "Staff rota", who: "Amal Z")]),
    KanbanLane(title: "Doing", limit: 2, cards: @[
      KanbanCard(title: "Pool repair", detail: "Pump and filter", tag: color(66, 133, 244))]),
    KanbanLane(title: "Done", cards: @[KanbanCard(title: "Fire drill")])]
  kanbanSel: KanbanPos = (0, 0)
  ganttTasks = @[
    GanttTask(name: "Opening", start: date(2026, 10, 20), finish: date(2026, 11, 12)),
    GanttTask(name: "Kitchen", start: date(2026, 10, 20), finish: date(2026, 10, 28),
              progress: 0.7, level: 1, color: color(219, 68, 55)),
    GanttTask(name: "Rooms", start: date(2026, 10, 25), finish: date(2026, 11, 4),
              progress: 0.3, level: 1, deps: @[1]),
    GanttTask(name: "Soft opening", start: date(2026, 11, 10), finish: date(2026, 11, 10),
              level: 1, milestone: true, deps: @[2])]
  taskSel = 1
  ganttScale = gsDay
  agendaItems = @[
    Appointment(title: "Audit", day: date(2026, 10, 27), start: 9 * 60, finish: 11 * 60),
    Appointment(title: "Holiday", day: date(2026, 10, 29), allDay: true, color: color(15, 157, 88)),
    Appointment(title: "Review", day: date(2026, 10, 28), start: 14 * 60, finish: 15 * 60 + 30)]
  agendaDay = date(2026, 10, 27)
  agendaMode = amMonth
  orgStaff = @[
    OrgNode(name: "Amal Al-Harthy", title: "General manager", parent: -1),
    OrgNode(name: "Badr Al-Kindi", title: "Rooms", parent: 0, color: color(66, 133, 244)),
    OrgNode(name: "Dana Al-Said", title: "Food & beverage", parent: 0, color: color(219, 68, 55)),
    OrgNode(name: "Eid Saleh", title: "Front office", parent: 1),
    OrgNode(name: "Huda Nasser", title: "Restaurant", parent: 2)]
  orgSel = 0

example("kpi", "Planning and dashboards", "kpiTile, statCard, kpiRow", 660, 150, ["kpiTile", "statCard", "kpiRow"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  kpiRow:
    kpiTile("Revenue", "OMR 84,120", 0.125, "vs last month",
            trend = [3.0, 4, 3.5, 5, 6, 5.5, 7], target = 0.68)
    kpiTile("Complaints", "12", -0.2, "vs last month", lowerIsBetter = true,
            color = color(219, 68, 55))
    statCard(pxUser, "Guests", "214", "38 arriving today", color(15, 157, 88))
example("kanban", "Planning and dashboards", "kanbanBoard", 640, 260, ["kanbanBoard"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  kanbanBoard(kanbanLanes, kanbanSel)
example("gantt", "Planning and dashboards", "ganttView", 680, 200, ["ganttView"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  ganttView(ganttTasks, taskSel, ganttScale)
example("agenda", "Planning and dashboards", "agendaView", 600, 330, ["agendaView"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  agendaView(agendaItems, agendaDay, agendaMode)
example("orgchart", "Planning and dashboards", "orgChart", 560, 240, ["orgChart"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  orgChart(orgStaff, orgSel)

# Maps and 3D
var
  worldMap = MapState()
  modelScene = Scene3()
  modelCam = camera3()
  barsScene = bars3d(@[@[12.0, 18, 9, 22], @[8.0, 14, 16, 11]], ["North", "South"],
                ["Q1", "Q2", "Q3", "Q4"], showValues = true)
  barsCam = camera3(yaw = 30, pitch = 28)
block:
  var b = box(1.2, 0.6, 0.8, color(0, 0, 160), name = "Base")
  b.edges = true
  discard modelScene.add b
  var sp = sphere(0.45, color(200, 0, 0), name = "Ball")
  sp.pos = vec3(0, 0.75, 0)
  discard modelScene.add sp
  modelScene.addGrid(4, 8, -0.3)
  fitView(modelScene, modelCam)
  fitView(barsScene, barsCam)

example("mapview", "Maps and 3D", "mapView", 600, 320, ["mapView", "cityMarker", "fitTo", "zoomTo", "resetView", "countryName", "countryCode", "latLonOf"], @[ssNormal, ssHover, ssTouch, ssDark]):
  mapView(worldMap, height = 300,
          values = [("OM", 120.0), ("AE", 340.0), ("SA", 510.0), ("IN", 800.0),
                    ("GB", 380.0), ("US", 950.0)],
          markers = [cityMarker("Muscat", size = 6), cityMarker("London")],
          routes = [MapRoute(fromLat: 23.59, fromLon: 58.41, toLat: 51.51, toLon: -0.13)],
          legendTitle = "Sales")
  aimAt(0.24, 0.5)
example("view3d", "Maps and 3D", "view3d", 380, 260, ["view3d", "box", "sphere", "cylinder", "cone", "plane", "loadModel", "addGrid", "addAxes", "fitView", "camera3", "render3d"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  view3d(modelScene, modelCam, height = 240)
example("bars3d", "Maps and 3D", "bars3d (a 3D bar chart)", 380, 260, ["bars3d"], @[ssNormal, ssDark]):
  view3d(barsScene, barsCam, height = 240)

# Web, HTML and Markdown
example("htmlview", "HTML and Markdown", "htmlView, htmlBlock", 420, 230, ["htmlView", "htmlBlock", "htmlToMarkdown", "webView"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  htmlView("<h3>Sales <u>report</u></h3><p>Up <b>12%</b>, costs " &
           "<span style=\"color:#c00\">down</span>, <mark>new store</mark> open.</p>" &
           "<table><tr><th>Month</th><th align=right>Sales</th></tr>" &
           "<tr><td>August</td><td align=right>1,020</td></tr>" &
           "<tr><td>September</td><td align=right>980</td></tr></table>" &
           "<ul><li>North<li>South</ul>", height = 210)
example("markdownview", "HTML and Markdown", "markdownView, markdown", 420, 230, ["markdownView", "markdown"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  markdownView("# Notes\n\nSome **bold**, *italic* and `code`.\n\n" &
               "- [x] Invoices sent\n- [ ] Stock count\n\n" &
               "| Item | Qty |\n|---|--:|\n| Paper | 10 |\n| Ink | 2 |\n", height = 210)

# Canvas
example("canvas2d", "Canvas and reports", "canvas2d (the HTML5 Canvas 2D API)", 380, 230, ["canvas2d", "canvas2dWith", "beginCanvas2D", "newCanvas2D", "createLinearGradient", "createRadialGradient", "addColorStop", "fillText", "isPointInPath", "drawImage", "getImageData"], @[ssNormal, ssDark]):
  canvas2d(ctx, 360, 210):
    let sky = ctx.createLinearGradient(0, 0, 0, 210)
    sky.addColorStop(0, "#000080")
    sky.addColorStop(1, "#1084d0")
    ctx.fillStyle = sky
    ctx.fillRect(0, 0, 360, 210)
    ctx.fillStyle = "#2e7d32"
    ctx.beginPath()
    ctx.moveTo(0, 210)
    ctx.bezierCurveTo(110, 100, 220, 220, 360, 130)
    ctx.lineTo(360, 210)
    ctx.closePath()
    ctx.fill()
    ctx.shadowColor = "rgba(0, 0, 0, 0.5)"
    ctx.shadowBlur = 8
    ctx.shadowOffsetX = 4
    ctx.shadowOffsetY = 4
    ctx.fillStyle = "gold"
    ctx.beginPath()
    ctx.arc(270, 60, 34, 0, 2 * PI)
    ctx.fill()
    ctx.shadowColor = "transparent"
    ctx.font = "bold 20px sans-serif"
    ctx.fillStyle = "white"
    ctx.fillText("Retro canvas", 16, 34)

# Reports
const shotTemplate = """
<header><span>Gulf Print House</span><span>Quote {{number}}</span></header>
<footer><span></span><span>Page {page} of {pages}</span></footer>
<h1>Quote {{number}}</h1><p>For <b>{{customer}}</b>:</p>
<table><thead><tr><th width="60%">Item</th><th align="right">Qty</th><th align="right">Amount</th></tr></thead>
<tbody>{{#lines}}<tr><td>{{name}}</td><td>{{qty}}</td><td>{{amount|n3}}</td></tr>{{/lines}}</tbody>
<tfoot><tr><td colspan="2" align="right">Total (OMR)</td><td>{{total|n3}}</td></tr></tfoot></table>"""
let shotReport = reportFromHtml(renderTemplate(shotTemplate, %*{"number": "Q-118",
  "customer": "Al Noor Trading", "total": 268.5,
  "lines": [{"name": "Business cards", "qty": 2, "amount": 25.0},
            {"name": "Letterheads", "qty": 3, "amount": 76.5},
            {"name": "Roll-up banner", "qty": 1, "amount": 167.0}]}))
example("reportview", "Canvas and reports", "reportView (from an HTML template: PDF, printing)", 520, 380, ["reportView", "reportFromHtml", "renderTemplate", "newReport", "header", "footer", "newTable", "addRow", "addTotals", "savePdf", "savePng", "printReport", "printPdf"], @[ssNormal, ssFocused, ssTouch, ssDark]):
  reportView(shotReport, height = 360)

# Media
const patternGif = staticRead("../examples/assets/pattern.gif")
let gifFrames = loadGif(patternGif)
example("animation", "Sound and video", "animation (animated GIFs)", 300, 70, ["animation", "loadGif", "playSound", "tone", "beep", "uiSound", "videoView"], static3):
  row:
    animation(gifFrames, height = 48)
    label "An animated GIF"

# ---- reading the API from the sources -------------------------------------------------------------

type ApiDoc = object
  sig, doc, file: string

proc readApi(): Table[string, seq[ApiDoc]] =
  let skip = ["font.nim", "unifontar.nim", "worlddata.nim", "androiddex.nim", "pixelicons.nim",
              "nerdicons.nim", "fontdata.nim"]
  for f in walkDirRec("src"):
    if not f.endsWith(".nim") or f.extractFilename in skip: continue
    let lines = readFile(f).splitLines
    var i = 0
    while i < lines.len:
      let l = lines[i]
      if (l.startsWith("proc ") or l.startsWith("template ") or l.startsWith("func ") or
          l.startsWith("macro ")) and "*" in l.split('(')[0]:
        let head = l.split(' ', 1)[1]
        let name = head.split({'*', '(', '['})[0].strip(chars = {'`'})
        var sig = l
        var j = i
        var forward = false
        while not (lines[j].strip.endsWith("=") or lines[j].strip.endsWith("{.discardable.} =")):
          if j + 1 >= lines.len or j >= i + 8 or lines[j + 1].strip.len == 0 or
             not lines[j + 1].startsWith(" "):
            forward = true                # a forward declaration: the proc comes later
            break
          inc j
          sig.add "\n" & lines[j]
        if forward:
          i = j + 1
          continue
        sig = sig.strip
        if sig.endsWith("="): sig = sig[0 ..< ^1].strip
        var doc: seq[string]
        var k = j + 1
        while k < lines.len and lines[k].strip.startsWith("##"):
          doc.add lines[k].strip[2 .. ^1].strip(trailing = false, chars = {' '})
          inc k
        result.mgetOrPut(name, @[]).add ApiDoc(sig: sig, doc: doc.join("\n"),
                                               file: f.extractFilename)
        i = k
      else: inc i

proc cleanCode(code: string): string =
  ## The example as an app would write it (without the tool's helpers).
  var lines: seq[string]
  for l in code.splitLines:
    if l.strip in ["aim()", "aimed = true"] or l.strip.startsWith("target = ") or
       l.strip.startsWith("aimAt("): continue
    lines.add l.multiReplace((", enabled = shotEnabled", ""), ("enabled = shotEnabled", ""),
                             ("(, ", "("))
  lines.join("\n").strip

proc docText(d: string): string =
  ## The doc comment as Markdown: its code blocks kept as code.
  var outL: seq[string]
  var inCode = false
  for l in d.splitLines:
    if l.startsWith(".. code-block::"):
      outL.add "```nim"
      inCode = true
    elif inCode and l.len > 0 and not l.startsWith("  "):
      outL.add "```"
      inCode = false
      outL.add l
    else: outL.add(if inCode: l.strip(trailing = false, chars = {' '}).indent(0) else: l)
  if inCode: outL.add "```"
  outL.join("\n")

# ---- drawing the pictures ---------------------------------------------------------------------------

proc capture(path: string) =
  let b = newBitmap(W, H)
  for i in 0 ..< W * H: b.px[i] = pixels[i] or 0xFF000000'u32
  writeFile(path, encodePng(b))

proc shoot(s: Shot; st: ShotState; outDir: string): string =
  if existsEnv("SHOTS_VERBOSE"): echo s.name, " ", st
  shotEnabled = st != ssDisabled
  let dark = st == ssDark
  let classic = ui.theme
  if dark:
    for t in builtinThemes:
      if t.name.toLowerAscii.contains("dark"): ui.theme = t.theme
  resize(s.w, s.h, st == ssTouch)
  ui.popup = 0
  ui.focus = 0
  queue.add Event(kind: MouseMoveEvent, x: W + 50, y: H + 50)
  view = proc () =
    # a focusable spot out of sight takes the focus first, so "Normal"
    # shows no focus and Tab gives it to the control
    discard interact(Id(0x5ec0ffee'u32), rect(-40, -40, 1, 1))
    if closeRequested(): cancelClose()       # (Esc and Back close the app otherwise)
    aimed = false
    s.draw()
    if not aimed: target = ui.lastRect
  run(4)
  let cx = target.x + min(target.w div 2, dp(24))
  let cy = target.y + target.h div 2
  case st
  of ssFocused:
    queue.add Event(kind: KeyDownEvent, key: KeyTab)
    queue.add Event(kind: KeyUpEvent, key: KeyTab)
    run(3)
  of ssHover:
    queue.add Event(kind: MouseMoveEvent, x: cx, y: cy)
    run(3)
  of ssPressed:
    queue.add Event(kind: MouseMoveEvent, x: cx, y: cy)
    queue.add Event(kind: MouseDownEvent, x: cx, y: cy, button: LeftButton, clicks: 1)
    run(2)
  of ssOpen:
    queue.add Event(kind: MouseMoveEvent, x: cx, y: cy)
    queue.add Event(kind: MouseDownEvent, x: cx, y: cy, button: LeftButton, clicks: 1)
    run(1)
    queue.add Event(kind: MouseUpEvent, x: cx, y: cy, button: LeftButton)
    run(3)
  else: discard
  let file = s.name & "-" & ($st).toLowerAscii.replace(" ", "-").replace("/", "") & ".png"
  capture(outDir / file)
  # let go away from it, close what opened
  queue.add Event(kind: MouseMoveEvent, x: W + 50, y: H + 50)
  queue.add Event(kind: MouseUpEvent, x: W + 50, y: H + 50, button: LeftButton)
  queue.add Event(kind: KeyDownEvent, key: KeyEsc)
  queue.add Event(kind: KeyUpEvent, key: KeyEsc)
  run(2)
  ui.popup = 0
  ui.theme = classic
  shotEnabled = true
  dlgOpen = true
  msgOpen = true
  inputOpen = true
  wizOpen = true
  aboutOpen = true
  findState.open = true
  file

proc main() =
  let outDir = "docs" / "controls"
  createDir(outDir)
  for f in walkFiles(outDir / "*.png"): removeFile(f)
  fakeDriver()
  pixels = newSeq[uint32](W * H)
  view = proc () = discard
  startApp("shots", W, H)
  let api = readApi()
  var md = "# Controls\n\n" &
    "Every control of Retro Nim UI: what it does, how to call it, and how it looks in\n" &
    "its states. The pictures are drawn by `tools/shots.nim` from the example code\n" &
    "shown with each control (headless, with the built-in fonts), so they always\n" &
    "match the toolkit. `nim c -r -d:release tools/shots.nim` makes them again.\n\n" &
    "Every control works with the mouse, the keyboard (Tab, arrows, Space, Enter,\n" &
    "Esc, `&` mnemonics, the menu key) and fingers (tap, drag to scroll, long press\n" &
    "for the menu). \"Disabled\" pictures pass `enabled = false`.\n\n"
  var cats: seq[string]
  for s in shots:
    if s.category notin cats: cats.add s.category
  md.add "**Contents:** "
  md.add cats.mapIt("[" & it & "](#" & it.toLowerAscii.replace(",", "").replace(" ", "-") & ")").join(" · ")
  md.add "\n\n"
  var count = 0
  for c in cats:
    md.add "## " & c & "\n\n"
    for s in shots:
      if s.category != c: continue
      md.add "### " & s.title & "\n\n"
      var shown: seq[string]
      # report.nim, pdf.nim and canvas2d.nim have procs of the same names as
      # widgets (paragraph, heading, fill...): each control shows its own
      let drawing = ["report.nim", "pdf.nim", "canvas2d.nim"]
      for a in s.apis:
        if a in shown: continue
        shown.add a
        let all = api.getOrDefault(a)
        let ours = all.filterIt((it.file in drawing) == (s.category == "Canvas and reports"))
        for d in (if ours.len > 0: ours else: all):
          md.add "```nim\n" & d.sig & "\n```\n\n"
          if d.doc.len > 0: md.add docText(d.doc) & "\n\n"
      md.add "Example:\n\n```nim\n" & cleanCode(s.code) & "\n```\n\n"
      var heads, cells: seq[string]
      for st in s.states:
        let file = shoot(s, st, outDir)
        heads.add $st
        cells.add "![" & s.name & " " & $st & "](controls/" & file & ")"
        inc count
      md.add "| " & heads.join(" | ") & " |\n|" & heads.mapIt("---").join("|") & "|\n| " &
             cells.join(" | ") & " |\n\n"
  writeFile("docs" / "controls.md", md)
  echo shots.len, " controls, ", count, " pictures in ", outDir

main()
