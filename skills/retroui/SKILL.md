---
name: retroui
description: Build desktop and mobile apps with Retro Nim UI (the retroui Nim package, github.com/foxoman/retroui): Windows 3.1 style, immediate mode, Windows, macOS, Linux, Android, iOS. Use for any app, form or tool made with retroui, or to fix or package one.
---

# Building apps with Retro Nim UI (`retroui`)

Retro Nim UI is a Windows 3.1 style UI toolkit for Nim by Sultan Al Isaiee
(@foxoman). It is immediate mode, has no dependencies to install (its own
fonts, icons, PDF writer, image decoders), and builds the same app for
Windows, macOS, Linux/BSD (X11, Wayland through XWayland), Android and iOS.

## 1. Read the latest docs first

The toolkit changes between releases. Before writing code, read the
current documents from the official repository (main branch) and follow
them where they differ from this file:

1. https://github.com/foxoman/retroui/blob/main/README.md -- what is in the kit, how it works
2. https://github.com/foxoman/retroui/blob/main/docs/controls.md -- every control: signature, example, pictures
3. https://github.com/foxoman/retroui/blob/main/CHANGELOG.md -- what changed (the top section is the newest)
4. https://github.com/foxoman/retroui/blob/main/BUILDING.md -- desktop (Windows, macOS, Linux), Android and iOS builds, signing
5. https://github.com/foxoman/retroui/blob/main/AGENTS.md -- rules for working on the kit itself
6. https://github.com/foxoman/retroui/blob/main/skills/retroui/SKILL.md -- the newest copy of this skill

In a clone, read the same files locally; `nimble docs` makes the full API
reference in `docs/api`. When you are unsure of a proc's parameters, look
at its signature in `src/retroui/*.nim` (every exported symbol has a doc
comment) instead of guessing.

## 2. Install and start a project

```sh
nimble install retroui                 # the library and its tools: retrokit, retroapk, retroios
retrokit doctor                        # checks the C compiler, the screen libraries, Android tools
retrokit new myapp --kind:business     # kinds: hello, form, business, files, charts
cd myapp && nimble run
```

Needs Nim 2.0+ (2.2 recommended) and a C compiler. Build with
`-d:release -d:useMalloc` (memory goes back to the system).

## 3. The shape of every app

```nim
import retroui

var name = "World"
var greeting = ""

app "Hello", 320, 120:                 # title, width, height, then the frame's code
  row([50, -1]):                       # widths: pixels, -1 = the rest
    label "&Name:"
    edit name                          # edits `name` in place
  row:
    if button("&Greet", isDefault = true):
      greeting = "Hello, " & name & "!"
    if button("E&xit"): quitApp()
  label greeting
```

`app` runs its block once per frame until the window closes. Options go by
name after the size: `theme`, `frame` (wfAsBuilt, wfSystem, wfClassic),
`userFrame`, `gpu` (gmAuto, gmGpu, gmCpu), `scale`, `font` (ufSans, ufSerif,
ufMono), `zoom`, `id`, `icon` (PNG bytes, `staticRead`), `look` (keeps the
look the user picks). A misspelled option is a compile error. An app with
its own loop uses `openApp(...)`, `while beginFrame(): ...; endFrame();
appFrameDone()`, `closeApp()`.

## 4. Immediate mode: the rules that prevent most mistakes

- Controls are proc calls made **every frame**; there are no widget
  objects or callbacks. A control returns true when it was clicked or
  changed something: `if button("OK"): save()`.
- **State lives in your variables** (globals or an object you keep), never
  in locals of the frame block: a local is new every frame.
- **Ids:** a control is known by its variable or label. Controls drawn in
  a loop need their own ids: `for i, r in rows: withId(i): ...` (or
  `pushId(i)` / `popId()`, or a control's `key` parameter).
- **Never block the frame.** Long work goes off the UI thread:
  `retroui/background` (`pictureAsync`, `folderAsync`, results by
  callback or `finished()`), `retroui/parallel` (`parallelFor`,
  `parallelRows`), `httpRequest` from a thread; `busy("Saving..."): ...`
  shows a busy box for work that must run on the UI thread. Ask for a
  frame later with `wakeIn(ms)`; for something that moves by itself where
  it is drawn (an animation, a clock), `wakeInShown(rect, ms)`: no frames
  while it is out of view, so an app at rest takes no CPU.
- `&` in a label underlines the next letter (Alt+letter). `isDefault = true`
  makes Enter press the button.
- Dialogs and popups are drawn by the same frame code, opened by a
  variable (`var showAbout = false` ... `aboutBox(showAbout, "My App", ...)`).
- `aboutBox` shows the toolkit's credit (`RetroCredit`, with its web site
  and mail) on its first page by itself: do not pass it again. Its
  `credits` page is for others: `credits = [RetroFontCredit, "Icons: ..."]`.
- **Keyboard shortcuts:** the shortcut text of `menuItem("&Open...", "Ctrl+O")`
  is only shown in the menu. Handle the key every frame, outside the
  `menubar` block: `if hotkeyPressed("Ctrl+O"): openDlg = true` (on a Mac
  "Ctrl+O" is Cmd+O).
- **Focus:** call `focusFirstText()` when a screen or dialog opens so the
  user can type at once (`focusFirstText(inDialog = true)` for a dialog
  opened this frame); `focusNext()` moves to the next control. Clicking a
  `numberEdit` / `intEdit` selects its text, so typing replaces it.

## 5. Layout

`row:` / `row([w1, w2, -1]):` (left to right), plain statements stack top
to bottom, `group "Title":`, `card`, `form(labelWidth): field("&Name:"): edit x`,
`spring()` (pushes the rest to the far side), `space(n)`, `adaptive(minW): ...`
(columns that fold into one on a phone), `scrollPanel`/`panel(h)`/`pane`,
`tabs`, `split`/`vsplit`, `sidePane`, `menubar: menu "&File": if menuItem("&Open", "Ctrl+O"): ...`,
`toolbar:`, `statusbar(...)`, MDI windows (`mdiArea`, `mdiWindow`), docking (`retroui/dock`).
Sizes are design pixels; the kit scales them to the screen (`dp(n)` for your own).

Forms: `form(90): field("&Name:"): edit name` -- `90` is the caption
column in design pixels (`form(0)`: as wide as the widest caption). The
control fills the rest of the row; give it `w = ...` to make it narrower,
or put several in a `row:` inside the `field`. `field("")` lines a control
up under the others. When the row is narrower than the captions plus about
200 pixels (a phone), each caption goes above its control.

## 6. Controls (docs/controls.md has all 291, with pictures)

Text: `label`, `paragraph`, `heading`, `styledText`, `link`, `badge`, `icon`, `iconLabel`, `image`, `tooltip`.
Buttons: `button`, `segmented`, `menuButton`, `splitButton`, `buttonRow`.
Choices: `checkbox`, `radio`, `toggle`, `chips`, `tagInput`, `rating`.
Text input: `edit`, `editArea`, `searchBox`, `autocomplete`, `maskedEdit`, `comboEdit`, `hotkeyEdit`, rich text (`richEdit`, `richToolbar`).
Numbers, dates, colors: `spin`, `intEdit`, `numberEdit`, `slider`, `progress`, `datePicker`, `calendar`, `timePicker`, `colorPicker`, `colorWell`.
Lists and data: `listbox`, `combo`, `grid` (the data grid with editing, sorting, totals), `tree`.
Files: `fileDialog`, `fileList`, `folderTree`, `filePicker`, `filePreview`, `placesView`.
Charts and more: `chart` (21 kinds, from your numbers or a CSV table), `barChart`, `lineChart`, `pieChart`, maps (`retroui/mapview`), 3D (`retroui/view3d`),
HTML and Markdown (`htmlView`), canvas (`canvas`, `retroui/canvas2d`), reports and PDF (`retroui/report`),
sound and video (`retroui/media`), spreadsheets (`retroui/xlsx`).

**Grid sorting:** the grid does not reorder your data. Keep the order in
your own variables, pass it in for the header's arrow, and sort a list of
row numbers when a header is clicked:

```nim
import std/[algorithm, sequtils]       # sort, toSeq

var people: seq[Person]
var order: seq[int]                    # people[order[i]] is row i
var sortCol = -1
var sortDesc = false
var cols = @[Column(title: "Name", width: 160), Column(title: "Salary", width: 90)]

proc cellOf(row, col: int): string =
  let p = people[order[row]]
  if col == 0: p.name else: formatNumber(p.salary, 2)

# in the frame:
if order.len != people.len: order = toSeq(0 ..< people.len)
let ev = grid(cols, order.len, cellOf, sel, height = -1,
              sortColumn = sortCol, sortDescending = sortDesc)
if ev.sorted:
  sortCol = ev.sortColumn
  sortDesc = ev.sortDescending
  order.sort(proc (a, b: int): int =
    let c = if sortCol == 0: cmp(people[a].name, people[b].name)
            else: cmp(people[a].salary, people[b].salary)
    if sortDesc: -c else: c)
if ev.activated: editPerson(order[sel])        # double click or Enter
if ev.edited: discard                          # ev.row, ev.col, ev.text: the new cell text
```

The `GridEvent` fields: `selChanged`, `activated`, `sorted` (`sortColumn`,
`sortDescending`), `edited` (`row`, `col`, `text`), `toggled`, `clicked`,
`rightClicked`, `hot`, drag and drop (`dragStarted`, `dropOver`, `dropped`).
Rows on screen are the only ones `cell` is asked for, so a large table
costs what its visible rows cost.

## 7. Files, settings and CSV

- **Where to keep files:** `dataDir("myapp") / "people.csv"` -- a folder
  only this app writes to (on Android and iOS the app's own folder); `/`
  for paths comes from `std/os`, which `import retroui` does not bring.
- **Settings:** `var s = loadSettings("myapp")` (an ordered table of
  strings, empty the first time); `s["lastFile"] = path;
  saveSettings("myapp", s)` (written safely; false when it could not be).
- **CSV:** `readCsv(path)` / `parseCsv(text)` give a `DataTable`
  (`headers`, `rows`, `error`; `cell(row, col)`, `column("Sales")` as
  numbers, `colIndex("Name")`). Write one with `writeCsv(path, table)` or
  `toCsv(table)`; `csvLine(cells)` and `csvField(s)` quote as needed.
  All of them are in `retroui/charts` (part of `import retroui`).

## 8. Looks, text and the window

- Themes: `ui.theme = Dark` (`builtinThemes`), or the `theme` option.
- Text size: 13.5 pixels per em at 100 % on desktops and tablets, 16.5 on
  phones; controls grow with the text. `setTextScale(120)` (the user's text
  size), `setUiScale(125)` (everything), `setBaseTextSize(15)` (your app's
  100 %).
- Fonts: FreeSans (default), FreeSerif, FreeMono, built in with Arabic;
  `loadUiFontFile(path)` for a font of your own; `appearanceSettings` lets
  the user choose (theme, font, text size, Sharp text, window frame) and
  `look = "myapp"` keeps it.
- Arabic and right-to-left text work everywhere (joined, bidi);
  `setRtlInterface(true)` mirrors the interface.
- The window frame: the system's or the Windows 3.1 frame (`frame` option;
  users switch from the control or system menu; kept per app).

## 9. Build and package

```sh
nim c -r -d:release -d:useMalloc app.nim                      # this computer
nim c -d:release -d:mingw --cpu:amd64 --app:gui app.nim        # Windows .exe from Linux/macOS (MinGW)
retroapk app.nim --name:"My App" --id:com.me.myapp             # Android APK: no SDK, no NDK needed
retroios app.nim --simulator --run                             # iOS, on a Mac with Xcode
retrokit small app.nim                                         # smallest desktop build
```

`retroapk` needs only clang with lld (or Zig); without either it fetches
the NDK. Keep `~/.retro/android` (the signing key) for updates. Details per
OS in BUILDING.md.

## 10. Check your work

- Compile and run it; look at it. On a headless Linux, under `Xvfb` (with
  no window manager the window sits at the top left, so crop the screen to
  the app's size):

  ```sh
  Xvfb :99 -screen 0 1280x900x24 & sleep 1
  DISPLAY=:99 ./app & sleep 2
  DISPLAY=:99 import -window root -crop 640x480+0+0 +repage shot.png   # the app's width x height
  ```
- Headless tests: the kit's fake driver (`tests/harness.nim` in the repo:
  `fakeDriver()`, `startApp`, `run()`, `click`, `key`, `px(x, y)`) drives an
  app without a screen.
- `RETRO_SIZE=420x840 RETRO_TOUCH=1 ./app` tries a phone's size on a desktop.

## 11. Common mistakes

- Keeping state in a local inside the frame block (it resets every frame).
- The same control drawn twice in a loop without `withId` (they share state).
- Blocking work (big files, network) in the frame code: the window freezes.
- Calling controls outside the `app` block (or outside `beginFrame` ... `endFrame`).
- Guessing a parameter name: check the signature in the source or docs.
- A shortcut written only in `menuItem(..., "Ctrl+S")`: it is a label; handle it
  with `hotkeyPressed("Ctrl+S")`.
- Passing `RetroCredit` to `aboutBox`: it is there already (it would show twice).
- Expecting `grid` to sort the data: it reports the header click (`ev.sorted`);
  you sort.
- Using the old name `retro` (`import retro`, `nimble install retro`): the package
  and its modules are `retroui` (`import retroui`, `import retroui/http`).
