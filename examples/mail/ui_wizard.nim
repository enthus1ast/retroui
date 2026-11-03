# Retro Mail: the Add Account wizard and signing in (again) in the browser.
# One click: "Microsoft" or "Google", the browser opens the service's own
# sign-in page, you sign in there, the account is here. (An organisation
# that allows only its own app registrations: "Advanced" takes its ID.)
# Included by examples/mail.nim.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

var
  wizOpen = false
  wizStep = 0               ## 0 choose, 1 an app registration of your own, 2 signing in, 3 done
  wizKind = 0               ## 0 Microsoft (work, school or personal), 2 Google
  wizName, wizMail: string
  wizOwn = false            ## an app registration of your own, not the built-in one
  wizClient, wizSecret, wizTenant: string
  wizFlow: OAuthFlow
  wizError = ""
  wizAccount = 0            ## signing in again to this account (0: a new one)
  wizDoneText = ""

proc testBrowserThread(url: string) {.thread.} =
  ## (tests: the browser's part -- the sign-in page answers with a
  ## redirect to the loopback address, which is followed once)
  {.gcsafe.}:
    sleep(200)
    let r = httpRequest("GET", url, followRedirects = false, timeoutSec = 20)
    let loc = r.header("location")
    if loc.len > 0: discard httpRequest("GET", loc, timeoutSec = 20)

var testBrowserT: Thread[string]

proc testBrowser(url: string) {.gcsafe.} =
  {.gcsafe.}: createThread(testBrowserT, testBrowserThread, url)

proc builtinId(kind: int): string =
  if kind == 2: googleAppId else: microsoftAppId

proc wizAccountObj(): Account =
  let own = wizOwn or builtinId(wizKind).len == 0
  Account(id: wizAccount, kind: (if wizKind == 2: akGmail else: akGraph),
          clientId: (if own: wizClient.strip else: builtinId(wizKind)),
          tenant: (if own and wizTenant.strip.len > 0: wizTenant.strip else: "common"))

proc wizSecretNow(): string =
  if wizKind != 2: ""
  elif wizOwn or googleAppId.len == 0: wizSecret.strip
  else: googleAppSecret

proc openWizard() =
  wizOpen = true
  wizStep = 0
  wizAccount = 0
  wizError = ""
  wizFlow = nil
  wizOwn = false
  wizMail = ""
  wizName = if accountsC.len > 0: accountsC[0].name else: ""
  wizClient = ""
  wizTenant = ""
  wizSecret = ""

proc startSignIn() =
  ## Opens the service's sign-in page in the browser, and waits for it.
  wizError = ""
  wizStep = 2
  let acc = wizAccountObj()
  let p = providerFor(acc, wizSecretNow())
  let browser: proc (url: string) {.gcsafe.} =
    if getEnv("RETRO_MAIL_TEST_BROWSER").len > 0: testBrowser else: nil
  wizFlow = beginSignIn(p, wizMail.strip, browser)

proc chooseService(kind: int) =
  wizKind = kind
  if builtinId(kind).len == 0:
    # (a build without its own registration: yours, once)
    wizOwn = true
    wizClient = pref(if kind == 2: "gClient" else: "msClient")
    wizTenant = if kind == 2: "" else: pref("msTenant")
    wizSecret = if kind == 2: loadSecret(secretApp, "google-client-secret") else: ""
    wizStep = 1
  else:
    startSignIn()

proc signInAgain(acc: Account) =
  openWizard()
  wizAccount = acc.id
  wizKind = if acc.kind == akGmail: 2 else: 0
  wizMail = acc.email
  wizName = acc.name
  wizOwn = acc.clientId != builtinId(wizKind) or builtinId(wizKind).len == 0
  wizClient = acc.clientId
  wizTenant = if acc.tenant in ["organizations", "consumers", "common"]: "" else: acc.tenant
  if acc.kind == akGmail: wizSecret = loadSecret(secretApp, secretKey(acc.id))
  startSignIn()

proc finishSignIn() =
  ## The browser said yes: who is it, then the account is kept.
  let t = wizFlow.tokens
  let acc = wizAccountObj()
  var email = wizMail.strip
  var name = wizName.strip
  try:
    case acc.kind
    of akGraph:
      let me = graphMe(t.accessToken)
      if me.email.len > 0: email = me.email
      if name.len == 0: name = me.name
    of akGmail:
      let p = gmailProfile(t.accessToken)
      if p.email.len > 0: email = p.email
      if name.len == 0: name = claims(t){"name"}.getStr
  except CatchableError as e:
    let c = claims(t)
    if email.len == 0: email = c{"email"}.getStr(c{"preferred_username"}.getStr)
    if email.len == 0:
      wizError = "Signed in, but your address could not be read: " & e.msg
      return
  let id = if wizAccount > 0:
             store0.setAccountState(wizAccount, "")
             wizAccount
           else: store0.addAccount(acc.kind, email, name, acc.clientId, acc.tenant,
                                   prefInt("syncDays", 90))
  discard saveSecret(secretApp, tokenKey(id), $(%t))
  if acc.kind == akGmail: discard saveSecret(secretApp, secretKey(id), wizSecretNow())
  if wizOwn:
    # (your own registration: kept for the next account)
    if acc.kind == akGmail:
      prefs.put("gClient", acc.clientId)
      discard saveSecret(secretApp, "google-client-secret", wizSecretNow())
    else:
      prefs.put("msClient", acc.clientId)
      prefs.put("msTenant", wizTenant.strip)
    savePrefs()
  link.cmds.send(SyncCmd(kind: scAccounts))
  wizDoneText = email
  wizStep = 3
  changed()

proc wizardArt(w, h: int) =
  let r = place(w, h)
  for i in 0 ..< h:
    hline(r.x, r.y + i, r.w, rgb(0, 60 + i * 60 div max(h, 1), 120 + i * 80 div max(h, 1)))
  let globe = pixelIcon(pxGlobe, big = true)
  image(r.x + (w - 2 * globe.w) div 2, r.y + dp(40), globe, 2)
  let m = pixelIcon(pxMail, big = true)
  image(r.x + (w - 3 * m.w) div 2, r.y + dp(140), m, 3)
  sunken(r)

proc serviceButton(px, title, detail: string): bool =
  ## A big button that names a service (Microsoft, Google).
  let lh = lineHeight()
  let r = place(available(), 2 * lh + dp(22), fill = true)
  let hit = interact(idOf("svc" & title), r)
  fill(r, if hit.hover: rgb(232, 232, 244) else: ui.theme.face)
  if hit.down: sunken(r) else: raised(r, 2)
  box(r, ui.theme.frame)
  let ic = pixelIcon(px, big = true)
  image(r.x + dp(10), r.y + (r.h - ic.h) div 2, ic)
  text(r.x + dp(54), r.y + dp(8), title, ui.theme.text, style(bold = true))
  text(r.x + dp(54), r.y + dp(10) + lh, detail, ui.theme.gray)
  if hit.focused: focusDots(inset(r, 4))
  hit.clicked

proc wizardDialog() =
  if wizFlow != nil and wizStep == 2:
    case wizFlow.state
    of osDone:
      finishSignIn()
      wizFlow = nil
    of osFailed:
      wizError = wizFlow.error
      wizFlow = nil
    of osCancelled: wizFlow = nil
    of osWaiting: wakeIn(300)
  let compact = isCompact()
  let width = if compact: ui.w - dp(16) else: dp(640)
  dialog wizOpen, (if wizAccount > 0: "Sign In Again" else: "Add Account Wizard"), width:
    row([(if compact: 0 else: dp(150)), -1]):
      if not compact: wizardArt(dp(150), dp(330))
      col:
        case wizStep
        of 0:
          label "Add an E-mail Account", bold = true
          paragraph "Where is your mail? Retro Mail opens the service's own sign-in page " &
                    "in your browser: sign in there, allow Retro Mail, and come back. It " &
                    "never sees your password."
          space()
          if serviceButton(pxGlobe, "Microsoft 365 or Outlook.com",
                           "Work, school, Outlook.com, Hotmail, Live"):
            chooseService(0)
          space()
          if serviceButton(pxMail, "Gmail or Google Workspace", "Your Google account"):
            chooseService(2)
          space()
          form dp(130):
            field "E-mail (if you like):": edit wizMail
          label "It fills in the sign-in page for you.", color = ui.theme.gray
          if link("Advanced: my organisation's own app registration..."):
            wizOwn = true
            wizClient = pref("msClient")
            wizTenant = pref("msTenant")
            wizStep = 1
        of 1:
          label (if wizKind == 2: "Your Google App" else: "Your Organisation's App"), bold = true
          if wizKind == 2:
            paragraph "In console.cloud.google.com: enable the Gmail and Google Calendar " &
                      "APIs, then Credentials, OAuth client ID, \"Desktop app\"."
            form dp(110):
              field "&Client ID:": edit wizClient
              field "Client &secret:": edit(wizSecret, password = true)
          else:
            paragraph "For an organisation that allows only its own apps: the Application " &
                      "ID of its registration (entra.microsoft.com, App registrations: " &
                      "\"Mobile and desktop\" with http://localhost, public client flows on, " &
                      "Mail.ReadWrite, Mail.Send, Calendars.Read)."
            row:
              radio("&Microsoft", wizKind, 0)
              radio("&Google", wizKind, 2)
            form dp(110):
              field "&Application ID:": edit wizClient
              if wizKind == 0:
                field "&Tenant ID:": edit wizTenant
          label "Kept for your next account.", color = ui.theme.gray
        of 2:
          label "Sign In", bold = true
          if wizFlow != nil:
            row:
              spinner()
              label "Waiting for " & (if wizKind == 2: "Google" else: "Microsoft") & "...", bold = true
            paragraph "Your browser opened the sign-in page. Sign in there and allow Retro " &
                      "Mail to read and send your mail; this window goes on by itself."
            row:
              if link("Open it again"): discard openUrl(wizFlow.url)
              if link("Copy the address"): putClipboardText(wizFlow.url)
            if button("Cancel"):
              wizFlow.cancel()
              wizFlow = nil
              wizStep = 0
          if wizError.len > 0:
            label "It did not work:", bold = true, color = rgb(200, 0, 0)
            paragraph wizError
            if button("Try Again", pxRefresh, isDefault = true): startSignIn()
        else:
          label "Congratulations", bold = true
          paragraph "You are signed in as " & wizDoneText & ". Retro Mail is downloading " &
                    "your mail now: the newest first, so you can start reading at once."
    separator()
    row:
      space available() - 3 * (dp(84) + Gap) + Gap
      if button("< &Back", enabled = wizStep in 1 .. 2 and wizFlow == nil and wizAccount == 0,
                w = dp(84)):
        wizStep = 0
        wizError = ""
      if wizStep == 1:
        let ok = if wizKind == 2: wizClient.strip.len > 10 and wizSecret.strip.len > 4
                 else: wizClient.strip.len > 10
        if button("&Sign In", isDefault = true, enabled = ok, w = dp(84)): startSignIn()
      elif wizStep == 3:
        if button("&Finish", isDefault = true, w = dp(84)):
          wizOpen = false
          view = vMail
          place = Place(kind: plAllInbox)
          treeSel = "fav:inbox"
          changed()
      else:
        button("&Next >", enabled = false, w = dp(84))
      if button((if wizStep == 3: "Close" else: "Cancel"), w = dp(84)):
        if wizFlow != nil: wizFlow.cancel()
        wizFlow = nil
        wizOpen = false
