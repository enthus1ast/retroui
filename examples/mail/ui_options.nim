# Retro Mail: Tools > Options, in Outlook Express's tabs -- General,
# Accounts, Signatures, Swipe, Tags, Look -- and the About box. Included
# by examples/mail.nim.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

var
  optAcct = 0
  optSig = 0
  optSigName = ""
  optSigDoc: RichDoc
  optSigLoaded = -1
  optTag = 0
  optTagName = ""
  optTagColor = 0
  askRemove = false

const intervals = [1, 2, 5, 10, 15, 30]
const keepDays = [(30, "1 month"), (90, "3 months"), (365, "1 year"), (1095, "3 years")]

proc sigChoices(): seq[string] =
  result = @["(none)"]
  for s in sigsC: result.add s.name

proc sigPrefIndex(key: string): int =
  let id = prefInt(key, -2)
  if id == -1: return 0
  for i, s in sigsC:
    if s.id == id: return i + 1
  if id == -2 and sigsC.len > 0: 1 else: 0

proc optionsDialog() =
  if not optOpen: return
  if sigsC.len == 0 or optSigLoaded == -1: sigsC = store0.signatures()
  let width = if isCompact(): ui.w - dp(16) else: dp(640)
  dialog optOpen, "Options", width:
    tabs(optTab, ["General", "Accounts", "Signatures", "Swipe", "Tags", "Look"]):
      case optTab
      of 0:
        group "Send and receive":
          form dp(220):
            field "Check for new mail every:":
              block:
                var names: seq[string]
                for m in intervals: names.add $m & (if m == 1: " minute" else: " minutes")
                var i = max(0, intervals.find(prefInt("interval", 1)))
                if combo(names, i, w = dp(140)):
                  prefs.put("interval", intervals[i])
                  link.cmds.send(SyncCmd(kind: scSettings, count: intervals[i]))
            field "Keep mail to read offline:":
              block:
                var names: seq[string]
                for (_, n) in keepDays: names.add n
                var i = 1
                for k, (d, _) in keepDays:
                  if d == prefInt("syncDays", 90): i = k
                if combo(names, i, w = dp(140)):
                  prefs.put("syncDays", keepDays[i][0])
                  store0.exec("UPDATE accounts SET sync_days = ?", keepDays[i][0])
        group "Read":
          var b = prefBool("threads", true)
          if checkbox("Show messages as &threads (conversations)", b): prefs.put("threads", b); changed()
          b = prefBool("focused", true)
          if checkbox("&Focused Inbox: what matters first, the rest under Other", b):
            prefs.put("focused", b)
            changed()
          form dp(220):
            field "Mark a message read after:":
              block:
                let opts = [0, 1, 2, 5, 9999]
                var i = max(0, opts.find(prefInt("readDelay", 2)))
                if combo(["At once", "1 second", "2 seconds", "5 seconds", "Never by itself"], i,
                         w = dp(140)):
                  prefs.put("readDelay", opts[i])
            field "Pictures from the web:":
              block:
                var i = prefInt("pictures", 0)
                if combo(["Ask each time", "Always show them"], i, w = dp(140)):
                  prefs.put("pictures", i)
            field "Reading pane:":
              block:
                let ks = ["bottom", "right", "off"]
                var i = max(0, ks.find(pref("pane", "bottom")))
                if combo(["Below the list", "Beside the list", "Off"], i, w = dp(140)):
                  prefs.put("pane", ks[i])
          b = prefBool("startInbox", false)
          if checkbox("When Retro Mail starts, go directly to my &Inbox", b): prefs.put("startInbox", b)
          b = prefBool("myday", true)
          if checkbox("Show &My Day beside the mail", b): prefs.put("myday", b)
          b = prefBool("notify", true)
          if checkbox("Tell me when &new mail comes", b): prefs.put("notify", b)
        group "Write":
          var rb = prefBool("replyBlue", true)
          if checkbox("Write replies and forwards in &blue, as Outlook did", rb):
            prefs.put("replyBlue", rb)
      of 1:
        group "Accounts":
          var names: seq[string]
          for a in accountsC:
            names.add a.email & "   (" & (if a.kind == akGmail: "Gmail" else: "Microsoft") &
                      (if a.state == "signin": ", sign in again" elif a.state.len > 0: ", " & a.state
                       else: "") & ")"
          row([-1, dp(140)]):
            listbox(names, optAcct, rows = 6)
            col:
              if button("&Add...", w = dp(140)):
                optOpen = false
                openWizard()
              if button("&Sign In Again", w = dp(140), enabled = optAcct in 0 ..< accountsC.len):
                optOpen = false
                signInAgain(accountsC[optAcct])
              if button("&Remove", w = dp(140), enabled = optAcct in 0 ..< accountsC.len):
                askRemove = true
          if optAcct in 0 ..< accountsC.len:
            let a = accountsC[optAcct]
            label "Name shown to others: " & (if a.name.len > 0: a.name else: "(none)")
            label "Messages kept here: " & $int(store0.value("SELECT count(*) FROM messages " &
                  "WHERE account = ?", a.id).num), color = ui.theme.gray
          let waiting = store0.actionsWaiting()
          if waiting > 0: label $waiting & " changes are waiting to reach the server.", color = ui.theme.gray
          for f in store0.failedActions():
            label "Not done: " & f.kind & " -- " & fit(f.error, dp(440)), color = rgb(200, 0, 0)
      of 2:
        group "Signatures":
          var names: seq[string]
          for s in sigsC: names.add s.name
          row([-1, dp(140)]):
            listbox(names, optSig, rows = 4)
            col:
              if button("&New", w = dp(140)):
                discard store0.saveSignature(0, "Signature " & $(sigsC.len + 1),
                  "<p>" & esc(if accountsC.len > 0: accountsC[0].name else: "") & "</p>")
                sigsC = store0.signatures()
                optSig = sigsC.high
                optSigLoaded = -2
              if button("&Remove", w = dp(140), enabled = optSig in 0 ..< sigsC.len):
                store0.deleteSignature(sigsC[optSig].id)
                sigsC = store0.signatures()
                optSig = max(0, optSig - 1)
                optSigLoaded = -2
        if optSig in 0 ..< sigsC.len:
          if optSigLoaded != sigsC[optSig].id:
            optSigLoaded = sigsC[optSig].id
            optSigName = sigsC[optSig].name
            optSigDoc = richFromHtml(sigsC[optSig].html)
          group "Edit Signature":
            form dp(60):
              field "&Name:": edit optSigName
            richToolbar(optSigDoc, compact = true)
            discard richEdit(optSigDoc, height = dp(110), key = "sigedit")
            if button("&Save Signature"):
              discard store0.saveSignature(sigsC[optSig].id, optSigName, toHtml(optSigDoc))
              sigsC = store0.signatures()
        group "Use for each account":
          let choices = sigChoices()
          for a in accountsC:
            label a.email, bold = true
            form dp(220):
              field "New messages:":
                block:
                  var i = sigPrefIndex("sigNew" & $a.id)
                  if combo(choices, i, w = dp(200)):
                    prefs.put("sigNew" & $a.id, if i == 0: -1 else: sigsC[i - 1].id)
              field "Replies and forwards:":
                block:
                  var i = sigPrefIndex("sigReply" & $a.id)
                  if combo(choices, i, w = dp(200)):
                    prefs.put("sigReply" & $a.id, if i == 0: -1 else: sigsC[i - 1].id)
      of 3:
        group "Swipe a message (touch screens)":
          form dp(120):
            field "Swipe &right:":
              block:
                var i = prefInt("swipeRight", 0)
                if combo(swipeChoices, i, w = dp(180)): prefs.put("swipeRight", i)
            field "Swipe &left:":
              block:
                var i = prefInt("swipeLeft", 1)
                if combo(swipeChoices, i, w = dp(180)): prefs.put("swipeLeft", i)
          var b = prefBool("mouseSwipe", false)
          if checkbox("Swipe with the &mouse too (drag a message sideways)", b):
            prefs.put("mouseSwipe", b)
        group "How it looks":
          let lh = lineHeight()
          let r = place(available(), 2 * (lh + dp(16)) + dp(8), fill = true)
          for k in 0 .. 1:
            let rr = rect(r.x, r.y + k * (lh + dp(20)), r.w, lh + dp(16))
            let dx = if k == 0: dp(130) else: -dp(130)
            swipeUnder(rr, dx)
            let rowR = rect(rr.x + dx, rr.y, rr.w, rr.h)
            pushClip(rr)
            fill(rowR, ui.theme.field)
            box(rowR, ui.theme.shadow)
            image(rowR.x + dp(8), rowR.y + (rowR.h - 16) div 2, pixelIcon(pxMail))
            text(rowR.x + dp(30), rowR.y + dp(8),
                 if k == 0: "A message swiped to the right" else: "A message swiped to the left",
                 ui.theme.text)
            popClip()
        label "With a keyboard: Backspace archives, Del deletes.", color = ui.theme.gray
      of 4:
        group "Tags":
          var data: seq[seq[string]]
          for t in tagsC:
            let c = tagColor(t.name)
            data.add @["#" & toHex(int c.r, 2) & toHex(int c.g, 2) & toHex(int c.b, 2), t.name,
                       $store0.tagCount(t.name)]
          var cols = @[colorColumn("Color", 50), column("Tag", 220), numberColumn("Messages", 80)]
          row([-1, dp(140)]):
            grid(cols, data, optTag, height = 7)
            col:
              if button("&New...", w = dp(140)): newTagOpen = true
              if button("&Delete", w = dp(140), enabled = optTag in 0 ..< tagsC.len):
                store0.deleteTag(tagsC[optTag].name)
                changed()
          if optTag in 0 ..< tagsC.len:
            form dp(80):
              field "Re&name:":
                block:
                  if optTagName.len == 0: optTagName = tagsC[optTag].name
                  edit optTagName
              field "&Color:":
                block:
                  var names: seq[string]
                  for (n, _) in tagPalette: names.add n
                  if combo(names, optTagColor):
                    store0.setTagColor(tagsC[optTag].name, tagPalette[optTagColor][1])
                    changed()
            if button("Apply the &Name", enabled = optTagName.strip.len > 0 and
                      optTagName != tagsC[optTag].name):
              store0.renameTag(tagsC[optTag].name, optTagName.strip)
              optTagName = ""
              changed()
          paragraph "Microsoft 365 keeps tags as Outlook categories and Gmail as labels: " &
                    "they show in Outlook and Gmail too."
      else:
        if appearanceSettings():
          storeAppearance(prefs)
    row:
      space available() - 2 * (dp(84) + Gap) + Gap
      if button("OK", isDefault = true, w = dp(84)):
        savePrefs()
        optOpen = false
      if button("Cancel", w = dp(84)):
        prefs = loadSettings("retro-mail")
        optOpen = false
  if not optOpen: savePrefs()
  case msgBox(askRemove, "Remove Account", "Remove " &
              (if optAcct in 0 ..< accountsC.len: accountsC[optAcct].email else: "") &
              " and the mail kept for it here? (Nothing is deleted on the server.)",
              ["&Remove", "Cancel"], miQuestion)
  of 1:
    if optAcct in 0 ..< accountsC.len:
      let a = accountsC[optAcct]
      store0.removeAccount(a.id)
      deleteSecret(secretApp, tokenKey(a.id))
      deleteSecret(secretApp, secretKey(a.id))
      link.cmds.send(SyncCmd(kind: scAccounts))
      optAcct = 0
      changed()
  else: discard

proc aboutDialog() =
  dialog aboutOpen, "About " & appName, dp(380):
    row:
      image(pixelIcon(pxMail, big = true))
      col:
        label appName & " " & appVersion, bold = true
        label "Microsoft 365, Outlook.com and Gmail, the 1997 way."
        label "Built with Retro Nim UI."
    paragraph credit
    if link("www.foxoman.net"): discard openUrl("https://www.foxoman.net")
    row:
      space available() - dp(80)
      if button("OK", isDefault = true, w = dp(80)): aboutOpen = false
