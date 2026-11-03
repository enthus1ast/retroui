## retro/notify: the Linux way through fake `gdbus`, `notify-send` and
## `termux-notification` programs that write down how they were called
## (quoting, Arabic text, tags replacing the notification before, a slow
## or broken service never holding up the caller); the Android way against
## a fake Java side that answers as tools/android/RetroNative.java does
## (the channel, the permission asked once, the badge, no Java objects
## left kept); on Windows the notification area's balloon -- no crash, no
## hang, the icon taken away at the end:
##
## .. code-block:: sh
##   nim c -r --hints:off tests/test_notify.nim
##   nim c --hints:off -d:mingw --cpu:amd64 -o:/tmp/test_notify.exe tests/test_notify.nim
##   WINEDEBUG=-all wine /tmp/test_notify.exe

include retro/notify           # (its inner parts too: the Android way runs anywhere)
import std/[monotimes, sequtils]
import retro/uirelays/services

block text:
  doAssert cleanText("  a\tb\nc\x01d\x7F ", 50) == "a\tb\nc d"
  doAssert cleanText("ok\xC3(bad", 50) == "ok\uFFFD(bad"
  doAssert cleanText("\r\n", 50) == ""
  let long = cleanText(repeat("\u0628", 700), MaxBody)       # (Arabic letters: 2 bytes each)
  doAssert long.runeLen == MaxBody + 1 and long.endsWith("\u2026")
  doAssert not notify("", "  "), "nothing to say: no notification"

# ---- Linux, BSD, Termux: fake programs on the PATH ----------------------------------------------------

when not defined(windows):
  let root = getTempDir() / "retro-notify-test"
  removeDir(root)
  let bin = root / "bin"             # gdbus and notify-send
  let only = root / "only"           # notify-send alone
  let termux = root / "termux"       # termux-notification
  for d in [bin, only, termux]: createDir(d)
  let logFile = root / "log"
  let sleepExe = findExe("sleep")

  proc fake(path, answer: string) =
    ## A program that writes its arguments down (NUL after each, "@CALL"
    ## first), may be slow ("slow") or fail ("fail"), and answers.
    writeFile(path, "#!/bin/sh\n" &
      "printf '%s\\0' @CALL \"${0##*/}\" \"$@\" >> '" & logFile & "'\n" &
      "if [ -e '" & root & "/slow' ]; then " & sleepExe & " 1; fi\n" &
      "if [ -e '" & root & "/fail' ]; then echo 'Error: ServiceUnknown' >&2; exit 1; fi\n" &
      "n=0; if [ -e '" & root & "/next' ]; then read n < '" & root & "/next'; fi\n" &
      "n=$((n + 1)); echo $n > '" & root & "/next'\n" & answer & "\n")
    setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})

  fake(bin / "gdbus", "case \"$*\" in *GetServerInformation*) echo \"('fake', 'retro', '1', '1.2')\";; " &
                      "*Notify*) echo \"(uint32 $n,)\";; *) echo '()';; esac")
  fake(bin / "notify-send", "echo $n")
  fake(only / "notify-send", "case \"$1\" in --help) echo '  -r, --replace-id=REPLACE_ID';; " &
                             "*) case \"$*\" in *-p*) echo $n;; esac;; esac")
  fake(termux / "termux-notification", "true")
  fake(termux / "termux-notification-remove", "true")

  proc calls(): seq[seq[string]] =
    ## The calls written down: the program's name and its arguments.
    if not fileExists(logFile): return
    for f in readFile(logFile).split('\0'):
      if f == "@CALL": result.add @[]
      elif result.len > 0: result[^1].add f
    for c in result.mitems:
      if c.len > 0 and c[^1] == "": c.setLen(c.len - 1)

  proc lastCall(): seq[string] =
    let c = calls()
    doAssert c.len > 0, "nothing was run"
    c[^1]

  proc unGv(s: string): string =
    ## A GVariant string read back ("..." with backslash escapes).
    doAssert s.len >= 2 and s[0] == '"' and s[^1] == '"', s
    var i = 1
    while i < s.len - 1:
      if s[i] == '\\':
        inc i
        case s[i]
        of 'n': result.add '\n'
        of 't': result.add '\t'
        of 'r': result.add '\r'
        of 'u':
          result.add $Rune(parseHexInt(s[i + 1 .. i + 4]))
          i += 4
        else: result.add s[i]
      else: result.add s[i]
      inc i

  proc fresh() =
    ## The log emptied; the routes looked for again.
    removeFile(logFile)
    routeAt = -100

  let pathBefore = getEnv("PATH")
  putEnv("PATH", bin & ":" & pathBefore)
  putEnv("DBUS_SESSION_BUS_ADDRESS", "unix:path=" & root & "/no-bus")
  delEnv("TERMUX_VERSION")
  fresh()

  block probe:
    doAssert notifyAvailable(), "gdbus and a session bus: there"
    doAssert notifyWait()
    let c = lastCall()
    doAssert c[0] == "gdbus" and c[^1] == "org.freedesktop.Notifications.GetServerInformation", $c
    doAssert notifyAvailable()

  block quoting:
    fresh()
    let title = "Q&A: \"quoted\" 'single' $(touch " & root & "/pwned) `id` \\ back"
    let body = "\u0631\u0633\u0627\u0644\u0629 \u062C\u062F\u064A\u062F\u0629 \u0645\u0646 \u062E\u0627\u0644\u062F\n" &
               "line two: <b>not bold</b> & \u{1F600} -- $HOME"
    doAssert notify(title, body, app = "Retro Mail", icon = "mail-unread")
    doAssert notifyWait()
    let c = lastCall()
    doAssert c[0] == "gdbus" and c[1] == "call" and "--session" in c, $c
    let m = c.find("--method")
    doAssert c[m + 1] == "org.freedesktop.Notifications.Notify", $c
    let a = c[m + 2 .. ^1]
    doAssert a.len == 8, $a
    doAssert unGv(a[0]) == "Retro Mail"
    doAssert a[1] == "uint32 0"
    doAssert unGv(a[2]) == "mail-unread"
    doAssert unGv(a[3]) == title, unGv(a[3])
    doAssert unGv(a[4]) == body.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"), unGv(a[4])
    doAssert a[5] == "@as []" and a[6] == "@a{sv} {}" and a[7] == "int32 -1", $a
    doAssert not fileExists(root / "pwned"), "the shell ran a part of the title"

  block tags:
    fresh()
    notify("New mail", "one", tag = "inbox")
    notify("New mail", "two", tag = "inbox")
    notify("Sent", "three", tag = "sent")
    notify("Other", "four")
    notify("New mail", "five", tag = "inbox")
    doAssert notifyWait()
    let c = calls()
    doAssert c.len == 5, $c
    proc replaces(k: int): string = c[k][c[k].find("--method") + 3]
    proc answered(k: int): int = parseInt(replaces(k)[7 .. ^1])
    doAssert replaces(0) == "uint32 0", replaces(0)
    let first = parseInt(readFile(root / "next").strip) - 4     # (the number the first one got)
    doAssert replaces(1) == "uint32 " & $first, replaces(1) & " " & $first
    doAssert replaces(2) == "uint32 0" and replaces(3) == "uint32 0"
    doAssert answered(4) == first + 1, "the tag's newest number: " & replaces(4)
    # taken away: the one tag, then all the tagged ones left
    fresh()
    clearNotification("inbox")
    doAssert notifyWait()
    var l = lastCall()
    doAssert l[l.find("--method") + 1] == "org.freedesktop.Notifications.CloseNotification" and
             l[^1] == "uint32 " & $(first + 4), $l
    fresh()
    clearNotification()
    doAssert notifyWait()
    l = lastCall()
    doAssert l[^1] == "uint32 " & $(first + 2), $l               # ("sent")
    fresh()
    clearNotification("inbox")                                   # (gone already: nothing run)
    doAssert notifyWait() and calls().len == 0

  block neverWaits:
    fresh()
    writeFile(root / "slow", "")
    var worst = 0'i64
    for i in 0 ..< 3:
      let t0 = getMonoTime()
      doAssert notify("Slow", "service " & $i, tag = "slow")
      worst = max(worst, (getMonoTime() - t0).inMilliseconds)
    doAssert worst < 100, "notify waited " & $worst & " ms"
    doAssert not notifyWait(200), "the slow service is still busy"
    doAssert notifyWait(10_000)
    doAssert calls().len == 3
    removeFile(root / "slow")

  block broken:
    fresh()
    writeFile(root / "fail", "")
    doAssert notify("Broken", "service")      # (not known yet)
    doAssert notifyWait()
    doAssert not notifyAvailable(), "a failure is remembered"
    doAssert not notify("Broken", "again"), "then the app shows a toast"
    removeFile(root / "fail")
    withLock lock: failedAt -= 120            # (a minute later)
    doAssert notifyAvailable()
    doAssert notifyWait()
    doAssert notify("Working", "again")
    doAssert notifyWait() and notifyAvailable()

  block notifySendOnly:
    fresh()
    putEnv("PATH", only)
    doAssert notifyAvailable()
    doAssert notify("-starts like an option", "body & <more>", app = "Retro Mail", icon = "mail",
                    tag = "ns")
    doAssert notifyWait()
    var c = calls().filterIt(it[0] == "notify-send" and it[1] != "--help")
    doAssert c.len == 1, $calls()
    let a = c[0][1 .. ^1]
    doAssert a == @["-a", "Retro Mail", "-i", "mail", "-p", "\u200B-starts like an option",
                    "body &amp; &lt;more&gt;"], $a
    let id = readFile(root / "next").strip
    fresh()
    notify("Second", "same tag", tag = "ns")
    doAssert notifyWait()
    c = calls().filterIt(it[0] == "notify-send")
    doAssert c.len == 1 and c[0][1 .. ^1] == @["-p", "-r", id, "Second", "same tag"], $c

  block termuxWay:
    fresh()
    putEnv("PATH", termux & ":" & bin)
    putEnv("TERMUX_VERSION", "0.118")
    doAssert notifyAvailable()
    doAssert notify("New mail", "it's here", tag = "inbox")
    doAssert notify("New mail", "no tag")
    clearNotification("inbox")
    doAssert notifyWait()
    let c = calls().filterIt(it[0].startsWith("termux"))
    doAssert c.len == 3, $calls()
    doAssert c[0] == @["termux-notification", "--id", "retro-inbox", "--title", "New mail",
                       "--content", "it's here"], $c[0]
    doAssert c[1][2].startsWith("retro-") and c[1][2] != "retro-inbox"
    doAssert c[2] == @["termux-notification-remove", "retro-inbox"], $c[2]
    delEnv("TERMUX_VERSION")

  block noService:
    fresh()
    putEnv("PATH", root / "nothing")
    doAssert not notifyAvailable() and not notify("No", "way")
    putEnv("PATH", bin & ":" & pathBefore)
    fresh()
    delEnv("DBUS_SESSION_BUS_ADDRESS")
    let rt = getEnv("XDG_RUNTIME_DIR")
    putEnv("XDG_RUNTIME_DIR", root / "nothing")
    doAssert not notifyAvailable(), "no session bus"
    putEnv("XDG_RUNTIME_DIR", rt)
    putEnv("PATH", pathBefore)

  removeDir(root)
  echo "notify: the Linux way passed"

# ---- Windows: the notification area ------------------------------------------------------------

when defined(windows):
  block balloon:
    doAssert notifyAvailable()
    let t0 = getMonoTime()
    doAssert notify("New mail", "\u0631\u0633\u0627\u0644\u0629 \u062C\u062F\u064A\u062F\u0629 -- " &
                    repeat("a long line ", 40), app = "Retro Mail", tag = "inbox")
    doAssert (getMonoTime() - t0).inMilliseconds < 500, "notify waited"
    doAssert notifyWait(10_000), "the notification area's thread hangs"
    let shown = notifyAvailable()
    echo "notify: the notification area ", (if shown: "took the balloon" else: "is not there (wine)")
    if shown:
      for i in 0 ..< 20: notify("Mail " & $i, "body " & $i, tag = "inbox")
      doAssert notifyWait(10_000)
      clearNotification()
      doAssert notifyWait(10_000)
      notify("Last", "one left for the end to take away")
      doAssert notifyWait(10_000)
    echo "notify: the Windows way passed"

# ---- Android: a fake Java side --------------------------------------------------------------------

proc unescape(s: string): string =
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len:
      inc i
      result.add(case s[i]
                 of 't': '\t'
                 of 'n': '\n'
                 of 'r': '\r'
                 of '0': '\0'
                 else: s[i])
    else: result.add s[i]
    inc i

var
  jlog: seq[seq[string]]             # each call: its name, then its fields
  kept: seq[int]
  nextHandle = 1
  sdkInt = 34
  granted = false
  enabled = true
  tags: seq[string]                  # what getTag answers, in turn

systemRelays.call = proc (name, arg: string): string {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    var f = @[name]
    for x in arg.split('\t'): f.add unescape(x)
    jlog.add f
    proc handle(): string =
      kept.add nextHandle
      inc nextHandle
      "h" & $(nextHandle - 1)
    case name
    of "native.ping": "s1"
    of "native.count": "s" & $kept.len
    of "native.release":
      for x in f[1 .. ^1]:
        if x.len > 0:
          let k = kept.find(parseInt(x))
          doAssert k >= 0, "released twice or never kept: " & x
          kept.delete(k)
      "n"
    of "native.new": handle()
    of "native.static", "native.method":
      if 'h' in f[3]: return handle()
      case f[2]
      of "SDK_INT": "s" & $sdkInt
      of "RELEASE": "s14"
      of "checkSelfPermission": (if granted: "s0" else: "s-1")
      of "areNotificationsEnabled": (if enabled: "strue" else: "sfalse")
      of "icon": "s2131034112"
      of "getPackageName": "sorg.retro.mail"
      of "getLength": "s2"
      of "getTag":
        let t = if tags.len > 0: tags[0] else: ""
        if tags.len > 0: tags.delete(0)
        if t.len > 0: "s" & t else: "n"
      of "getId": "s7"
      else: "n"
    else: "eNoSuchMethodException"

proc called(member: string): seq[seq[string]] =
  ## The calls of `member` (a method, static or not): their arguments.
  for c in jlog:
    if c[0] in ["native.method", "native.static"] and c[2] == member: result.add c[4 .. ^1]

proc made(cls: string): seq[seq[string]] =
  for c in jlog:
    if c[0] == "native.new" and c[1] == cls: result.add c[3 .. ^1]

block androidPermission:
  jlog.setLen(0)
  doAssert not androidNotify("New mail", "Khalid", "", "inbox", 0), "not allowed yet"
  let arr = called("newInstance")
  doAssert arr.len == 1 and arr[0][0].startsWith("o") and arr[0][1] == "i1", $arr
  let put = called("set")
  doAssert put.len == 1 and put[0][1] == "i0" and put[0][2] == "sandroid.permission.POST_NOTIFICATIONS", $put
  let asked = called("requestPermissions")
  doAssert asked.len == 1 and asked[0][0] == put[0][0] and asked[0][1] == "i7301", $asked
  doAssert kept.len == 0, "objects left: " & $kept
  doAssert not androidNotify("New mail", "Khalid", "", "inbox", 0)
  doAssert called("requestPermissions").len == 1, "asked once"
  doAssert called("notify").len == 0

block androidNotification:
  granted = true
  jlog.setLen(0)
  doAssert androidNotify("New mail", "Khalid: the drill plan", "", "inbox", 0)
  doAssert made("android.app.NotificationChannel") == @[@["smail", "sMail", "i3"]]
  doAssert called("createNotificationChannel").len == 1
  doAssert made("android.app.Notification$Builder") == @[@["a", "smail"]]
  doAssert called("setSmallIcon") == @[@["i2131034112"]]
  doAssert called("setContentTitle") == @[@["sNew mail"]]
  doAssert called("setContentText") == @[@["sKhalid: the drill plan"]]
  doAssert called("bigText") == @[@["sKhalid: the drill plan"]]
  doAssert called("setAutoCancel") == @[@["b1"]]
  doAssert called("setNumber").len == 0
  doAssert called("getLaunchIntentForPackage") == @[@["sorg.retro.mail"]]
  let pi = called("getActivity")
  doAssert pi.len == 1 and pi[0][0] == "a" and pi[0][1] == "i0" and
           pi[0][3] == "i" & $(0x04000000 or 0x08000000), $pi
  let n = called("notify")
  doAssert n.len == 1 and n[0][0] == "sinbox" and n[0][1] == "i1" and n[0][2].startsWith("o"), $n
  doAssert kept.len == 0, "objects left: " & $kept
  # the channel once; no tag: a number of its own; the badge's count rides along
  jlog.setLen(0)
  doAssert androidNotify("Sent", "Re: the plan", "", "", 4)
  doAssert made("android.app.NotificationChannel").len == 0
  doAssert called("setNumber") == @[@["i4"]]
  let n2 = called("notify")
  doAssert n2.len == 1 and n2[0][0] == "n" and n2[0][1] == "i1001", $n2
  doAssert kept.len == 0
  # turned off by the user
  enabled = false
  jlog.setLen(0)
  doAssert not androidNotify("New mail", "off", "", "inbox", 0)
  doAssert called("notify").len == 0 and kept.len == 0
  enabled = true

block androidBadgeAndClear:
  jlog.setLen(0)
  tags = @["inbox", ""]
  androidBadge(3)
  doAssert called("recoverBuilder").len == 2
  doAssert called("setNumber") == @[@["i3"], @["i3"]]
  doAssert called("setOnlyAlertOnce") == @[@["b1"], @["b1"]]
  let n = called("notify")
  doAssert n.len == 2 and n[0][0] == "sinbox" and n[0][1] == "i7" and n[1][0] == "n", $n
  doAssert kept.len == 0, "objects left: " & $kept
  jlog.setLen(0)
  androidBadge(0)
  doAssert called("cancelAll").len == 1 and called("notify").len == 0
  jlog.setLen(0)
  androidClear("inbox")
  doAssert called("cancel") == @[@["sinbox", "i1"]]
  androidClear("")
  doAssert called("cancelAll").len == 1
  doAssert kept.len == 0

block olderAndroid:
  # Android 7: no channel, no permission to ask
  aSdk = -1
  aChannel = false
  sdkInt = 25
  granted = false
  jlog.setLen(0)
  doAssert androidNotify("New mail", "Nougat", "", "inbox", 0)
  doAssert made("android.app.NotificationChannel").len == 0
  doAssert made("android.app.Notification$Builder") == @[@["a"]]
  doAssert called("checkSelfPermission").len == 0
  doAssert kept.len == 0

block badgeKept:
  doAssert badgeCount() == 0
  setBadge(5)
  doAssert badgeCount() == 5
  setBadge(-3)
  doAssert badgeCount() == 0

echo "notify tests passed"
