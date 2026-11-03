# Retro Mail: the Add Account wizard and signing in (again) in the browser.
# Included by examples/mail.nim.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

var
  wizOpen = false
  wizStep = 0
  wizKind = 0               ## 0 Microsoft 365 (work or school), 1 Outlook.com, 2 Gmail
  wizName, wizMail: string
  wizClient, wizSecret, wizTenant: string
  wizRemember = true
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

proc wizAccountObj(): Account =
  Account(id: wizAccount, kind: (if wizKind == 2: akGmail else: akGraph), clientId: wizClient.strip,
          tenant: (if wizKind == 1: "consumers" elif wizTenant.strip.len > 0: wizTenant.strip
                   else: "organizations"))

proc openWizard() =
  wizOpen = true
  wizStep = 0
  wizAccount = 0
  wizError = ""
  wizFlow = nil
  if wizName.len == 0:
    wizName = if accountsC.len > 0: accountsC[0].name else: ""
  wizMail = ""
  wizKind = prefInt("wizKind", 0)
  wizClient = pref(if wizKind == 2: "gClient" else: "msClient")
  wizTenant = pref("msTenant")
  wizSecret = if wizKind == 2: loadSecret(secretApp, "google-client-secret") else: ""

proc signInAgain(acc: Account) =
  openWizard()
  wizAccount = acc.id
  wizKind = if acc.kind == akGmail: 2 elif acc.tenant == "consumers": 1 else: 0
  wizMail = acc.email
  wizName = acc.name
  wizClient = acc.clientId
  wizTenant = if acc.tenant in ["organizations", "consumers", "common"]: "" else: acc.tenant
  if acc.kind == akGmail: wizSecret = loadSecret(secretApp, secretKey(acc.id))
  wizStep = 2

proc startSignIn() =
  wizError = ""
  let acc = wizAccountObj()
  let p = providerFor(acc, wizSecret.strip)
  let browser: proc (url: string) {.gcsafe.} =
    if getEnv("RETRO_MAIL_TEST_BROWSER").len > 0: testBrowser else: nil
  wizFlow = beginSignIn(p, wizMail.strip, browser)

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
  if acc.kind == akGmail: discard saveSecret(secretApp, secretKey(id), wizSecret.strip)
  if wizRemember:
    prefs.put("wizKind", wizKind)
    if acc.kind == akGmail:
      prefs.put("gClient", acc.clientId)
      discard saveSecret(secretApp, "google-client-secret", wizSecret.strip)
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
      if not compact: wizardArt(dp(150), dp(360))
      col:
        case wizStep
        of 0:
          label "Your E-mail Account", bold = true
          paragraph "Step 1 of 3. Your name is what people see in the From field " &
                    "of what you send."
          form dp(110):
            field "&Display name:": edit wizName
            field "&E-mail address:": edit wizMail
          label "My mail is with:"
          if radio("&Microsoft 365 -- work or school", wizKind, 0) or
             radio("&Outlook.com, Hotmail or Live", wizKind, 1):
            wizClient = pref("msClient")
          if radio("&Gmail or Google Workspace", wizKind, 2):
            wizClient = pref("gClient")
            wizSecret = loadSecret(secretApp, "google-client-secret")
          paragraph "Retro Mail signs in with the service's own page, in your browser: it " &
                    "never sees your password and keeps only an encrypted sign-in token."
        of 1:
          if wizKind == 2:
            label "Your Google App", bold = true
            paragraph "Step 2 of 3. Retro Mail talks to Gmail through your own Google Cloud " &
                      "project (no one else's key is in it). In console.cloud.google.com: " &
                      "enable the Gmail API and the Google Calendar API, set up the OAuth " &
                      "consent screen, then Credentials, Create, OAuth client ID, \"Desktop " &
                      "app\". Copy its ID and secret here."
            form dp(110):
              field "&Client ID:": edit wizClient
              field "Client &secret:": edit(wizSecret, password = true)
          else:
            label "Your Microsoft App", bold = true
            paragraph "Step 2 of 3. Retro Mail talks to Microsoft 365 through an app " &
                      "registration of your own (or your IT department's). In " &
                      "entra.microsoft.com: App registrations, New registration; under " &
                      "Authentication add the platform \"Mobile and desktop applications\" " &
                      "with the address http://localhost and allow public client flows; " &
                      "under API permissions add Microsoft Graph's Mail.ReadWrite, Mail.Send, " &
                      "Calendars.Read, MailboxSettings.Read, User.Read and offline_access."
            form dp(110):
              field "&Application ID:": edit wizClient
              if wizKind == 0:
                field "&Tenant ID:": edit wizTenant
            if wizKind == 0:
              label "Tenant: empty for any organisation, or your directory's ID.",
                    color = ui.theme.gray
            paragraph "If your company asks an administrator to approve new apps, they " &
                      "approve this one once."
          checkbox("&Remember these for my next account", wizRemember)
        of 2:
          label "Sign In", bold = true
          if wizFlow == nil:
            paragraph "Step 3 of 3. Your browser opens " &
                      (if wizKind == 2: "Google's" else: "Microsoft's") &
                      " sign-in page. Sign in there and allow Retro Mail to read and send " &
                      "your mail; then come back here."
            if button(if wizKind == 2: "Sign in with Google..." else: "Sign in with Microsoft...",
                      pxKey, isDefault = true):
              startSignIn()
          else:
            row:
              spinner()
              label "Waiting for the browser...", bold = true
            paragraph "Finish signing in in your browser. If it did not open, copy this " &
                      "address into it:"
            row:
              if link("Copy the address"): putClipboardText(wizFlow.url)
              if link("Open it again"): discard openUrl(wizFlow.url)
            if button("Cancel"):
              wizFlow.cancel()
              wizFlow = nil
          if wizError.len > 0:
            label "It did not work:", bold = true, color = rgb(200, 0, 0)
            paragraph wizError
        else:
          label "Congratulations", bold = true
          paragraph "You are signed in as " & wizDoneText & ". Retro Mail is downloading " &
                    "your mail now: the newest first, so you can start reading at once."
    separator()
    row:
      space available() - 3 * (dp(84) + Gap) + Gap
      if button("< &Back", enabled = wizStep in 1 .. 2 and wizFlow == nil and wizAccount == 0,
                w = dp(84)):
        dec wizStep
      if wizStep < 2:
        let ok = if wizStep == 0: true
                 elif wizKind == 2: wizClient.strip.len > 10 and wizSecret.strip.len > 4
                 else: wizClient.strip.len > 10
        if button("&Next >", isDefault = true, enabled = ok, w = dp(84)): inc wizStep
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
