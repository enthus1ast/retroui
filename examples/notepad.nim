## A Notepad in the manner of Windows 3.1: open and save files, cut, copy,
## paste, select all, the time and date (F5), find (Ctrl+F, F3), a status
## bar and a "Save changes?" box on exit.  nim c -r examples/notepad.nim
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, strutils, times]
import retroui

var
  text = "Welcome to Retro Notepad.\n\nOpen a text file with File > Open, or type here.\n"
  saved = text
  path = ""
  askExit = false
  askNew = false
  showAbout = false
  openDlg = false
  saveDlg = false
  picked = ""
  status = ""
  finder = FindState()

proc docName(): string = (if path.len > 0: path.extractFilename else: "(Untitled)")

var editorId: Id
  ## The text area's id (from the frame before): its caret and selection
  ## live in `state(editorId)`.

proc editor(): Id = editorId

proc selection(): (int, int) =
  let st = state(editor())
  (min(st.caret, st.anchor), max(st.caret, st.anchor))

proc select(a, b: int) =
  var st = state(editor())
  st.anchor = clamp(a, 0, text.len)
  st.caret = clamp(b, 0, text.len)
  state(editor()) = st
  ui.focus = editor()
  ui.redraw = true

proc replaceSelection(s: string) =
  let (a, b) = selection()
  text = text[0 ..< a] & s & text[b .. ^1]
  select(a + s.len, a + s.len)

proc saveTo(p: string): bool =
  try:
    writeFile(p, text)
    path = p
    saved = text
    status = "Saved " & p.extractFilename
    true
  except IOError, OSError:
    status = "Could not save " & p
    false

proc save(): bool =
  if path.len == 0:
    saveDlg = true
    false
  else: saveTo(path)

proc load(p: string) =
  try:
    text = readFile(p).replace("\r\n", "\n")
    saved = text
    path = p
    status = ""
    select(0, 0)
  except IOError, OSError:
    status = "Could not open " & p

proc findNext(backwards = false) =
  if finder.what.len == 0:
    finder.open = true
    return
  let (a, b) = selection()
  let at = findIn(text, finder.what, (if backwards: a else: b), finder.matchCase,
                  finder.wholeWord, backwards = backwards)
  if at < 0: status = "Cannot find \"" & finder.what & "\""
  else:
    status = ""
    select(at, at + finder.what.len)

app "Notepad", 620, 420:
  let wanted = "Notepad - " & docName()
  if ui.title != wanted: setTitle(wanted)
  if closeRequested() and text != saved:
    cancelClose()
    askExit = true

  menubar:
    menu "&File":
      if menuItem("&New"):
        if text != saved: askNew = true
        else:
          text = ""
          saved = ""
          path = ""
      if menuItem("&Open...", "Ctrl+O"): openDlg = true
      if menuItem("&Save", "Ctrl+S"): discard save()
      if menuItem("Save &As..."): saveDlg = true
      menuSeparator()
      if menuItem("E&xit"):
        if text != saved: askExit = true else: quitApp()
    menu "&Edit":
      let (a, b) = selection()
      if menuItem("Cu&t", "Ctrl+X", enabled = b > a):
        putClipboardText(text[a ..< b])
        replaceSelection("")
      if menuItem("&Copy", "Ctrl+C", enabled = b > a): putClipboardText(text[a ..< b])
      if menuItem("&Paste", "Ctrl+V"): replaceSelection(getClipboardText())
      if menuItem("De&lete", "Del", enabled = b > a): replaceSelection("")
      menuSeparator()
      if menuItem("Select &All"): select(0, text.len)
      if menuItem("Time/&Date", "F5"): replaceSelection(now().format("HH:mm dd/MM/yyyy"))
    menu "&Search":
      if menuItem("&Find...", "Ctrl+F"): finder.open = true
      if menuItem("Find &Next", "F3"): findNext()
    menu "&Help":
      if menuItem("&About Notepad..."): showAbout = true

  # the keys of the menus that the text area does not handle itself
  if canInput() and not ui.keyUsed:
    let ctrl = CtrlPressed in ui.mods
    if ctrl and ui.key == KeyS:
      ui.keyUsed = true
      discard save()
    elif ctrl and ui.key == KeyO:
      ui.keyUsed = true
      openDlg = true
    elif ctrl and ui.key == KeyF:
      ui.keyUsed = true
      finder.open = true
    elif ui.key == KeyF3:
      ui.keyUsed = true
      findNext(ShiftPressed in ui.mods)
    elif ui.key == KeyF5:
      ui.keyUsed = true
      replaceSelection(now().format("HH:mm dd/MM/yyyy"))

  statusbar(if status.len > 0: status elif text == saved: "Saved" else: "Modified",
            $text.countLines & " lines", $text.len & " bytes")
  let fe = findBar(finder)
  if fe.next: findNext()
  if fe.prev: findNext(backwards = true)
  editArea text, lines = -1
  editorId = ui.lastId

  if filePicker(openDlg, picked, fmOpen, ["*.txt", "*.md", "*.nim", "*.ini", "*.csv", "*"],
                "Open"):
    load(picked)
  if filePicker(saveDlg, picked, fmSave, ["*.txt"], "Save As"):
    discard saveTo(picked)

  case msgBox(askExit, "Notepad", "The text in " & docName() &
              " has changed.\n\nSave the changes?",
              ["&Yes", "&No", "Cancel"], miWarning)
  of 1:
    if save(): quitApp()
  of 2: quitApp()
  else: discard

  case msgBox(askNew, "Notepad", "The text in " & docName() &
              " has changed.\n\nStart a new one without saving?",
              ["&Yes", "&No"], miQuestion)
  of 1:
    text = ""
    saved = ""
    path = ""
  else: discard

  aboutBox(showAbout, "Notepad", RetroVersion,
           ["A small text editor made with Retro Nim UI."],
           tagline = "A small text editor", glyph = pxText)
