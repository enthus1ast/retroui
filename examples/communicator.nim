## Retro Communicator -- the look, with made-up people and messages: the
## welcome, creating an account, the account made (an "Add me" code), the
## friends list and a conversation. `$RETRO_COMM` opens one of them:
## "welcome" (the default), "signon", "create", "done", "friends", "chat",
## "main" (the friends list and conversations as windows of one app).
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/os
import retroui
import retroui/qrcode

const
  brand = color(0, 100, 130)          # the bands
  brandSoft = color(200, 228, 236)
  online = color(0, 160, 0)
  away = color(210, 140, 0)
  busy = color(200, 0, 0)
  idle = color(128, 128, 128)
  me = color(192, 0, 0)
  them = color(0, 0, 192)
  good = color(0, 128, 0)

type
  Screen = enum scWelcome, scSignOn, scCreate, scDone, scFriends, scChat, scMain
  Friend = tuple[name, note: string; state: Color]

let groups: seq[(string, seq[Friend], int)] = @[
  ("Friends", @[("SunnyDay88", "at the beach", online), ("PixelPete", "coding", online),
                ("NadiaK", "back in 10", away)], 5),
  ("Family", @[("CousinZed", "", online), ("UncleBob1970", "idle 12m", idle)], 4),
  ("Work", @[("DeskLamp", "in a meeting", busy)], 6)]

var
  screen = (case getEnv("RETRO_COMM")
            of "signon": scSignOn
            of "create": scCreate
            of "done": scDone
            of "friends": scFriends
            of "chat": scChat
            of "main": scMain
            else: scWelcome)
  address = "foxoman@yax.im"
  password = "retro-pass-1"
  savePassword = true
  autoSignOn = true
  newName = "sunnyday88"
  newPassword = "sunny-pass-1"
  showPassword = false
  myState = 0
  myNote = "Building Retro Communicator"
  find = ""
  draft = "Sounds good, see you there!"
  friendsWin = MdiWindow(title: "Friends", r: rect(8, 8, 250, 440), open: true,
                         glyph: pxUser, grip: true)
  chatWin = MdiWindow(title: "SunnyDay88", r: rect(270, 20, 440, 420), open: true,
                      glyph: nfComments, grip: true)

# ---- pieces ---------------------------------------------------------------------------------------

proc band(title, sub: string; tall = false) =
  ## The app's band across the top: its icon, a title, a line under it.
  let h = if tall: 104 else: 50
  let r = place(0, dp(h), fill = true)
  fill(r, brand)
  let s = if tall: 3.4 else: 2.0
  let iw = textWidth(nfComments, style(size = s))
  let ix = r.x + dp(12)
  text(ix, r.y + (r.h - int(float(FontH) * s)) div 2, nfComments,
       color(255, 255, 255), style(size = s))
  let tx = ix + iw + dp(10)
  let ts = if tall: 1.55 else: 1.25
  let lines = (if sub.len > 0: 2 else: 1)
  let th = int(float(FontH) * ts) + (if lines == 2: FontH + dp(2) else: 0)
  let ty = r.y + (r.h - th) div 2
  text(tx, ty, title, color(255, 255, 255), style(bold = true, size = ts))
  if sub.len > 0:
    text(tx, ty + int(float(FontH) * ts) + dp(2), sub, brandSoft, style())

proc note(glyph, s: string; c = good) =
  iconLabel(glyph, s, color = c, iconColor = c)

proc centered(w: int) =
  ## Room before a `w` wide widget so that it is in the middle of the row.
  space(max(0, (ui.w - w) div 2 - dp(12)))

# ---- 1. welcome -----------------------------------------------------------------------------------

proc welcome() =
  band("Retro Communicator", "Talk to your friends, the 1999 way", tall = true)
  space(10)
  heading("Welcome", 2)
  label("Chat with your friends one to one or in rooms, see who is online, " &
        "set an away message.")
  space(6)
  if button("&Create a new account", isDefault = true, w = dp(270)): screen = scCreate
  space(2)
  if button("I &already have an account", w = dp(270)): screen = scSignOn
  space(10)
  note(nfCheck, "Free -- no email, no phone number")
  note(nfCheck, "Works with any XMPP app")
  note(nfCheck, "Your history stays on your device")

# ---- 1b. sign on (an account of before) ------------------------------------------------------------

proc signOnBox() =
  band("Sign On", "Your address and your password")
  space(6)
  form(64):
    field("&Address:"): edit(address)
    field("&Password:"): edit(password, password = true)
  checkbox("&Save password", savePassword)
  checkbox("Sign on a&utomatically", autoSignOn)
  space(4)
  row:
    if button("< &Back", w = 70): screen = scWelcome
    spring()
    if button("Sign &On", isDefault = true, w = 90): screen = scFriends

# ---- 2. create an account -------------------------------------------------------------------------

proc createBox() =
  band("Create your account", "Step 1 of 2 -- a name and a password")
  space(6)
  row:
    avatar("Sunny Day", size = dp(44))
    space(6)
    label("Your picture", bold = true)
    space(6)
    discard link("Choose...")
  space(4)
  form(90):
    field("Screen &name:"): edit(newName)
    field(""):
      note(nfCheck, newName & "@yax.im is free")
    field("&Password:"): edit(newPassword, password = not showPassword)
    field(""):
      row:
        progress(0.8, w = dp(110), showText = false)
        label(" Strong", color = good)
    field(""): checkbox("&Show the password", showPassword)
    field("Provider:"):
      row:
        label "yax.im -- free, since 2013"
        spring()
        discard link("Change")
  space(2)
  iconLabel(pxWarning, "Keep your password safe: it cannot be reset.",
            color = color(150, 80, 0))
  space(4)
  row:
    if button("< &Back", w = 80): screen = scWelcome
    spring()
    if button("&Create Account", isDefault = true, w = 130): screen = scDone

# ---- 3. the account made -------------------------------------------------------------------------

var qrPic: Bitmap

proc doneBox() =
  band("You are in!", "Step 2 of 2 -- add your friends")
  space(8)
  row:
    avatar("Sunny Day", size = dp(40))
    space(6)
    label(newName & "@yax.im\nAvailable", bold = true)
  space(6)
  if qrPic.isNil:
    qrPic = qrBitmap(qrEncode("xmpp:" & newName & "@yax.im?roster"), scale = 3, border = 2)
  row:
    centered(qrPic.w)
    let r = place(qrPic.w, qrPic.h)
    drawBitmap(r, qrPic)
  row:
    centered(textWidth("Friends scan this to add you", style()))
    label("Friends scan this to add you", color = idle)
  space(6)
  if button("&Add a friend by name...", w = dp(270)): discard
  space(2)
  if button("&Open my friends list", isDefault = true, w = dp(270)): screen = scFriends

# ---- 4. the friends list ------------------------------------------------------------------------

proc friendRow(f: Friend) =
  row:
    space(4)
    avatar(f.name, size = dp(26))
    space(4)
    label(f.name, bold = f.state != idle, color = (if f.state == idle: idle else: Color()))
    if f.note.len > 0: label(f.note, color = idle)
    spring()
    icon(nfCircle, f.state, 0.8)

proc friendsList() =
  row:
    avatar("Foxo Man", size = dp(40))
    space(4)
    label("foxoman", bold = true)
    spring()
    combo(["Available", "Away", "Busy", "Invisible"], myState, w = dp(92))
  edit(myNote)
  searchBox(find, "Find a friend")
  panel(dp(290)):
    for (title, people, total) in groups:
      label(title & "  " & $people.len & "/" & $total, bold = true, color = brand)
      for f in people: friendRow(f)
    label("Offline  9", bold = true, color = idle)
  row:
    if button("&Talk", w = 54): screen = scChat
    button("&Room", w = 54)
    button("A&dd", w = 54)
    button("A&way", w = 54)

# ---- 5. a conversation ----------------------------------------------------------------------------

proc said(who, time, text: string; mine: bool) =
  row:
    label(who, bold = true, color = (if mine: me else: them))
    label(time, color = idle)
    label text

proc conversation() =
  row:
    avatar("SunnyDay88", size = dp(36))
    space(4)
    label("SunnyDay88", bold = true)
    label("at the beach", color = idle)
    icon(nfCircle, online, 0.8)
    spring()
    toolButton(nfPaperclip, "Send a file")
    toolButton(nfUser, "Info")
  panel(dp(232)):
    row:
      centered(textWidth("Today", style()))
      label("Today", color = idle)
    said("foxoman", "7:02 PM", "are you coming to the game night?", true)
    said("SunnyDay88", "7:03 PM", "yes! bringing the snacks", false)
    row:
      space(16)
      iconLabel(nfPaperclip, "snack-list.txt   2 KB   Open", color = them)
    said("SunnyDay88", "7:03 PM", "مرحبا، أراك هناك", false)
    row:
      spring()
      label("Seen 7:04 PM", color = idle)
    label("SunnyDay88 is typing...", color = idle)
  row:
    toolButton("B", "Bold", bold = true)
    toolButton("I", "Italic")
    toolButton("U", "Underline")
    toolButton(nfLink, "Link")
  editArea(draft, lines = 2)
  row:
    button("&Block", w = 64)
    spring()
    button("&Send", isDefault = true, w = 80)

# ---- the app --------------------------------------------------------------------------------------

app "Retro Communicator", 740, 480:
  case screen
  of scWelcome: welcome()
  of scSignOn: signOnBox()
  of scCreate: createBox()
  of scDone: doneBox()
  of scFriends: friendsList()
  of scChat: conversation()
  of scMain:
    menubar:
      menu "&Communicator":
        discard menuItem("&Sign Off")
        menuSeparator()
        if menuItem("E&xit", "Alt+F4"): quitApp()
      menu "&People":
        discard menuItem("&Add a Friend...")
        discard menuItem("&Away Message...")
      menu "&Window":
        if menuItem("&Cascade"): mdiCascade()
      menu "&Help":
        discard menuItem("&About Retro Communicator")
    mdiArea(-1):
      mdiWindow(friendsWin):
        friendsList()
      mdiWindow(chatWin):
        conversation()
    statusbar("Online as foxoman", "1 conversation")
