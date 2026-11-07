#> for p in [("Maryam Al Balushi", "9123 4567"), ("Ahmed Al Harthy", "9988 7766"), ("Salim Al Kindi", "9200 1188")]:
#>   key(KeyN, {AltPressed})
#>   typeText(p[0])
#>   key(KeyTab)
#>   typeText(p[1])
#>   key(KeyEnter)
#> key(KeyS, {CtrlPressed})
#> shot("people-list")
#> key(KeyN, {AltPressed})
#> typeText("Aisha Al Said")
#> shot("people-edit")
#> key(KeyEsc)
#> clickMark(1)
#> shot("people-delete")
#> key(KeyEsc)
#> key(KeyH, {AltPressed})
#> key(KeyA)
#> shot("people-about")
import std/os
import retroui

type
  Person = object
    name, phone: string
    active: bool

  State = object                     # everything the app remembers, in one place
    people: seq[Person]
    sel: int
    draft: Person
    showEdit, askDelete, showAbout: bool
    status: string

var s = State(sel: -1)

proc save() =                        # work lives in procs, outside the frame
  var t = DataTable(headers: @["Name", "Phone", "Active"])
  for p in s.people: t.rows.add @[p.name, p.phone, $p.active]
  s.status = if writeCsv(dataDir("people") / "people.csv", t): "Saved " & $s.people.len & " people"
             else: "Could not save"

proc mainMenu() =                    # one proc per part of the window
  menubar:
    menu "&File":
      if menuItem("&Save", "Ctrl+S"): save()
      if menuItem("E&xit"): quitApp()
    menu "&Help":
      if menuItem("&About People..."): s.showAbout = true

proc peopleList() =
  for i, p in s.people:
    withId(i):                       # each row's controls kept apart
      row([-1, 120, 0]):
        if link(p.name): s.sel = i
        label p.phone
        if button("&Delete"):
          s.sel = i
          s.askDelete = true
        mark "del"

proc editDialog() =
  dialog(s.showEdit, "Person", 360):
    form(70):
      field("&Name:"): edit s.draft.name
      field("&Phone:"): edit s.draft.phone
      field(""): checkbox("&Active", s.draft.active)
    row:
      spring()
      if button("OK", isDefault = true):
        s.people.add s.draft
        s.showEdit = false
      if button("Cancel"): s.showEdit = false

proc chosen(): string =
  if s.sel in 0 ..< s.people.len: s.people[s.sel].name else: ""

app "People", 520, 380:
  mainMenu()
  if hotkeyPressed("Ctrl+S"): save()
  row:
    if button("&New..."):
      s.draft = Person(active: true)
      s.showEdit = true
  peopleList()
  statusbar(s.status)
  # the dialogs, last: drawn over the window while their variable is true
  editDialog()
  case msgBox(s.askDelete, "People", "Delete " & chosen() & "?", ["&Yes", "&No"], miQuestion)
  of 1: s.people.delete(s.sel)
  else: discard
  aboutBox(s.showAbout, "People", "1.0", ["A list of people, kept as CSV."])
