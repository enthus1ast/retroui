# Retro Mail: the commands by name (the command box, the menus, the keys),
# the keyboard shortcuts' list, and what the window asks of the system.
# Included by examples/mail.nim.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

var shortcutsOpen = false

proc notifySystem(title, body: string) =
  ## The system's own notification, where there is one.
  discard notify(title, body, appName, tag = "followup")

proc nextPane() =
  ## F6: the folders, the list, the search box, round again.
  let listId = listIdC
  if ui.focus == listId: ui.textFocusWanted = true
  elif ui.focus == 0 or ui.focus != listId: ui.focus = listId

proc runCommand(name: string) =
  let ms = selectedMsgs()
  case name
  of "New message": openCompose("new")
  of "Reply": doReply("reply")
  of "Reply all": doReply("replyAll")
  of "Forward": doReply("forward")
  of "New event": newEventNow()
  of "New meeting":
    if ms.len > 0: newMeetingFrom(ms[0]) else: newEventNow()
  of "Delete": deleteMsgs(ms)
  of "Archive": archiveMsgs(ms)
  of "Undo":
    case undoWhat
    of "send": undoSend()
    of "move": undoLastMove()
    else: discard
    undoWhat = ""
    hideSnackbar()
  of "Mark as read": markRead(ms)
  of "Mark as unread":
    markRead(ms, true)
    readMarked = selKey
  of "Flag": toggleFlag(ms)
  of "Follow up tomorrow": followUp(ms, tomorrowAt(9))
  of "Pin": pinMsgs(ms)
  of "Snooze": snoozeOpen = true
  of "Tags": tagMenuOpen = true
  of "Move to folder": moveOpen = ms.len > 0
  of "Go to folder": goFolderOpen = true
  of "Sweep": openSweep()
  of "Quick steps": qsOpen = true
  of "Select all":
    multiSel.clear()
    for i in 0 ..< rows.len:
      if rows[i].group.len == 0 and rows[i].msg < 0: multiSel.incl rowKey(i)
  of "Send and receive": link.cmds.send(SyncCmd(kind: scSyncNow))
  of "Search": ui.textFocusWanted = true
  of "Calendar": view = vCalendar
  of "People": view = vPeople
  of "To do": view = vTodo
  of "Notes": view = vNotes
  of "Reading pane beside the list": prefs.put("pane", "right"); savePrefs()
  of "Reading pane below the list": prefs.put("pane", "bottom"); savePrefs()
  of "Reading pane off": prefs.put("pane", "off"); savePrefs()
  of "Threads on or off":
    prefs.put("threads", not prefBool("threads", true))
    savePrefs()
    changed()
  of "Customize toolbar": customizing = true
  of "Options": optOpen = true
  of "Add an account": openWizard()
  of "Tell me": cmdOpen = true
  of "Next pane": nextPane()
  of "Keyboard shortcuts": shortcutsOpen = true
  of "Forward as attachment": forwardAsAttachment()
  of "Message rules": rulesOpen = true
  of "Automatic replies": oofOpen = accountsC.len > 0
  of "Save message as": saveMessageAs()
  of "Import messages":
    importOpen = true
    importResult = ""
    importFrom = if oeStoreFolders().len > 0: 0 else: 1
  of "Export messages":
    exportPath = downloadsDir() / (placeTitle().multiReplace(("/", "_"), (":", "_")) & ".mbox")
    exportOpen = true
  of "Print": printMessage()
  of "Properties": showProperties()
  of "Message source": showProperties(source = true)
  of "Save search": saveSearch(query)
  of "Ignore conversation": ignoreConversation(ms)
  of "Find message": openFind()
  of "Hide read messages":
    prefs.put("hideRead", not prefBool("hideRead", false))
    savePrefs()
    changed()
  of "Open a saved message":
    openEmlPath = downloadsDir()
    openEmlOpen = true
  else: status = name & ": not here yet"

const shortcutList = [
  ("Ctrl+N", "New message"), ("Ctrl+R / Ctrl+Shift+R", "Reply / Reply to all"),
  ("Ctrl+F", "Forward"), ("Ctrl+Enter, Alt+S", "Send (while writing)"),
  ("Del / Backspace", "Delete / Archive"), ("Ctrl+Z", "Undo (a move, a message being sent)"),
  ("Insert", "Flag"), ("Ctrl+Q / Ctrl+U", "Mark as read / unread"), ("Ctrl+T", "Tags"),
  ("Ctrl+Shift+V", "Move to a folder"), ("Ctrl+Y", "Go to a folder"),
  ("Ctrl+. / Ctrl+,", "Next / previous message"), ("Enter", "Open in a window of its own"),
  ("Shift+arrows, Ctrl+click", "Select several"), ("Ctrl+A", "Select all"),
  ("Letters", "Jump to a sender in the list"), ("F6", "The next pane"),
  ("Ctrl+E / Ctrl+Shift+F", "Search / Find Message"), ("Alt+Q", "Tell me what you want to do"), ("F5", "Send and receive"),
  ("Ctrl+P", "Print"), ("Alt+Enter / Ctrl+F3", "Properties / Message source"),
  ("Ctrl+1 ... Ctrl+5", "Mail, Calendar, People, To Do, Notes"), ("F7", "Spelling (while writing)")]

proc shortcutsDialog() =
  dialog shortcutsOpen, "Keyboard Shortcuts", dp(480):
    var lines: seq[string]
    for (k, what) in shortcutList: lines.add k & "\t" & what
    var sel = -1
    listbox(lines, sel, rows = shortcutList.len, tabs = [dp(190)])
    row:
      space available() - dp(84)
      if button("Close", isDefault = true, w = dp(84)): shortcutsOpen = false
