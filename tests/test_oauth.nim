## Tests of retroui/oauth (and retroui/sha2): SHA-256 and HMAC vectors, PKCE
## as RFC 7636 shows it, the providers' addresses, and whole sign-ins
## against a fake sign-in service of the test's own (its authorize page
## sends the browser back to the app's loopback address with a code; its
## token endpoint checks the PKCE pair) -- with `openBrowser` doing the
## browser's part through retroui/http. Also: a wrong state refused, other
## pages and repeated hits, a refused sign-in, cancelling, refreshing.

import std/[net, os, strutils, times, json, locks, typedthreads, nativesockets, base64]
import retroui/[http, oauth, sha2]

# ---- SHA-256 ------------------------------------------------------------------------------

block sha256Vectors:
  doAssert sha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  doAssert sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  doAssert sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
           "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
  doAssert sha256Hex("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu") ==
           "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"
  let million = 'a'.repeat(1_000_000)
  doAssert sha256Hex(million) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
  # a piece at a time, in pieces of every length around the block's 64
  for size in [1, 3, 55, 56, 63, 64, 65, 127, 1000]:
    var h = initSha256()
    var i = 0
    while i < million.len:
      h.update(million[i ..< min(i + size, million.len)])
      i += size
    doAssert h.finish().toHex == sha256Hex(million), $size
  for n in 0 .. 130:                       # every padding case against one-shot
    let s = 'x'.repeat(n)
    var h = initSha256()
    h.update(s[0 ..< n div 2])
    h.update(s[n div 2 .. ^1])
    doAssert h.finish() == sha256(s)
  var bytes = newSeq[byte](3)
  bytes[0] = byte('a'); bytes[1] = byte('b'); bytes[2] = byte('c')
  doAssert sha256(bytes).toHex == sha256Hex("abc") and sha256("abc").toBinary.len == 32
  # HMAC-SHA-256, RFC 4231 cases 1, 2 and 6
  doAssert hmacSha256('\x0b'.repeat(20), "Hi There").toHex ==
           "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
  doAssert hmacSha256("Jefe", "what do ya want for nothing?").toHex ==
           "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
  doAssert hmacSha256('\xaa'.repeat(131), "Test Using Larger Than Block-Size Key - Hash Key First").toHex ==
           "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"

proc b64url(s: string): string = encode(s, safe = true).strip(leading = false, chars = {'='})

block pkceVector:
  # RFC 7636, appendix B
  doAssert b64url(sha256("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk").toBinary) ==
           "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

# ---- the providers --------------------------------------------------------------------------

block providers:
  let ms = microsoftProvider("ms-id", scopes = ["https://graph.microsoft.com/Mail.ReadWrite"])
  doAssert ms.name == "Microsoft" and ms.clientId == "ms-id" and ms.clientSecret == ""
  doAssert ms.authUrl == "https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize"
  doAssert ms.tokenUrl == "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"
  doAssert ms.scopes == @["https://graph.microsoft.com/Mail.ReadWrite", "openid", "profile", "email",
                          "offline_access"]
  doAssert ms.redirectHost == "localhost" and ms.scopeOnRefresh and ms.authParams.len == 0
  let common = microsoftProvider("ms-id", "common", ["offline_access", "User.Read"])
  doAssert common.authUrl == "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
  doAssert common.scopes == @["offline_access", "User.Read", "openid", "profile", "email"]
  let g = googleProvider("g-id", "g-secret", ["https://mail.google.com/"])
  doAssert g.name == "Google" and g.clientSecret == "g-secret"
  doAssert g.authUrl == "https://accounts.google.com/o/oauth2/v2/auth"
  doAssert g.tokenUrl == "https://oauth2.googleapis.com/token"
  doAssert g.scopes == @["https://mail.google.com/", "openid", "email", "profile"]
  doAssert ("access_type", "offline") in g.authParams and ("prompt", "consent") in g.authParams
  doAssert g.redirectHost == "127.0.0.1" and not g.scopeOnRefresh

block tokensJson:
  let t = OAuthTokens(accessToken: "a", refreshToken: "r", idToken: "i.d.t", scope: "s t",
                      expiresAt: 1234567890.5)
  doAssert toTokens(%t) == t
  doAssert toTokens(parseJson($(%t))) == t
  doAssert toTokens(parseJson("""{"accessToken": "x"}""")) == OAuthTokens(accessToken: "x")
  doAssert toTokens(newJNull()) == OAuthTokens() and toTokens(nil) == OAuthTokens()
  doAssert claims(OAuthTokens()).len == 0 and claims(OAuthTokens(idToken: "a.!!!.c")).len == 0

# ---- the fake sign-in service -------------------------------------------------------------------

let idPayload = """{"email":"sultan@example.com","name":"Sultan Al Isaiee","preferred_username":"sultan@example.com"}"""
let idToken = b64url("""{"alg":"none"}""") & "." & b64url(idPayload) & ".c2ln"

var
  mockLock: Lock
  codes: seq[tuple[code, challenge, redirect, client: string]]   # guarded by mockLock
  authorizeSeen: seq[(string, string)]                           # the last authorize's query
  tokenCalls = 0
  lastScope = ""
  nextCode = 1

initLock(mockLock)

type Request = object
  meth, path, query, body: string
  headers: seq[(string, string)]

proc param(fields: seq[(string, string)]; name: string): string =
  for (k, v) in fields:
    if k == name: return v

proc answer(c: Socket; status: int; headers: openArray[(string, string)]; body: string) =
  var head = "HTTP/1.1 " & $status & " X\r\n"
  for (k, v) in headers: head.add k & ": " & v & "\r\n"
  head.add "Content-Length: " & $body.len & "\r\nConnection: close\r\n\r\n"
  c.send(head & body)

proc tokenError(c: Socket; code, description: string) =
  c.answer(400, {"Content-Type": "application/json"},
           $(%*{"error": code, "error_description": description}))

proc serveToken(c: Socket; form: seq[(string, string)]) =
  {.cast(gcsafe).}:
    withLock mockLock:
      inc tokenCalls
      lastScope = form.param("scope")
    case form.param("grant_type")
    of "authorization_code":
      var found = -1
      var entry: tuple[code, challenge, redirect, client: string]
      withLock mockLock:
        for i, e in codes:
          if e.code == form.param("code"): found = i
        if found >= 0:
          entry = codes[found]
          codes.delete(found)                      # a code works once
      if found < 0:
        c.tokenError("invalid_grant", "The code is not known or was used.")
        return
      if form.param("redirect_uri") != entry.redirect or form.param("client_id") != entry.client:
        c.tokenError("invalid_grant", "The redirect address or client does not match.")
      elif entry.client == "google-client" and form.param("client_secret") != "not-secret":
        c.tokenError("invalid_client", "Unauthorized")
      elif b64url(sha256(form.param("code_verifier")).toBinary) != entry.challenge:
        c.tokenError("invalid_grant", "AADSTS501481: The Code_Verifier does not match the " &
                     "code_challenge supplied in the authorization request.\r\nTrace ID: 1f2e\r\n")
      else:
        c.answer(200, {"Content-Type": "application/json"},
                 $(%*{"access_token": "at-1", "refresh_token": "rt-1", "id_token": idToken,
                      "expires_in": 3600, "scope": "openid email", "token_type": "Bearer"}))
    of "refresh_token":
      if form.param("refresh_token") == "rt-1":
        c.answer(200, {"Content-Type": "application/json"},
                 $(%*{"access_token": "at-2", "expires_in": "1800", "token_type": "Bearer"}))
      elif form.param("refresh_token") == "rotating":
        c.answer(200, {"Content-Type": "application/json"},
                 $(%*{"access_token": "at-3", "refresh_token": "rotated", "expires_in": 60}))
      else:
        c.tokenError("invalid_grant", "AADSTS700082: The refresh token has expired due to inactivity.")
    else:
      c.tokenError("unsupported_grant_type", "")

proc handle(c: Socket) =
  var r: Request
  let first = c.recvLine(timeout = 10_000).split(' ')
  if first.len < 3: return
  r.meth = first[0]
  let q = first[1].find('?')
  r.path = if q < 0: first[1] else: first[1][0 ..< q]
  r.query = if q < 0: "" else: first[1][q + 1 .. ^1]
  var length = 0
  while true:
    let line = c.recvLine(timeout = 10_000)
    if line.len == 0 or line == "\r\n": break
    if line.toLowerAscii.startsWith("content-length:"): length = parseInt(line[15 .. ^1].strip)
  if length > 0: r.body = c.recv(length, timeout = 10_000)
  let query = formDecode(r.query)
  case r.path
  of "/authorize", "/authorize-deny":
    {.cast(gcsafe).}:
      withLock mockLock: authorizeSeen = query
    let redirect = query.param("redirect_uri")
    if query.param("response_type") != "code" or query.param("code_challenge_method") != "S256" or
        query.param("code_challenge").len != 43 or redirect.len == 0:
      c.answer(400, {:}, "bad authorize request")
      return
    var to = redirect & "?state=" & urlEncode(query.param("state"))
    if r.path == "/authorize-deny":
      to.add "&error=access_denied&error_description=" & urlEncode("The user said no.")
    else:
      var code: string
      {.cast(gcsafe).}:
        withLock mockLock:
          code = "code-" & $nextCode
          inc nextCode
          codes.add (code, query.param("code_challenge"), redirect, query.param("client_id"))
      to.add "&code=" & code
    c.answer(302, {"Location": to}, "")
  of "/token":
    c.serveToken(formDecode(r.body))
  else:
    c.answer(404, {:}, "no")

proc worker(fd: SocketHandle) {.thread.} =
  let server = newSocket(fd, AF_INET, SOCK_STREAM, IPPROTO_TCP)
  while true:
    var c: Socket
    try: server.accept(c)
    except OSError: continue
    try: handle(c)
    except CatchableError: discard
    c.close()

var workers: array[8, Thread[SocketHandle]]

proc startServer(): int =
  let s = newSocket()
  s.bindAddr(Port(0), "127.0.0.1")
  s.listen()
  result = int(s.getLocalAddr()[1])
  for w in workers.mitems: createThread(w, worker, s.getFd)

let base = "http://127.0.0.1:" & $startServer()

# ---- the browser's part ---------------------------------------------------------------------------

var
  pages: seq[tuple[status: int; body: string]]    # what "the browser" saw (main thread)
  loopback = ""                                    # the app's redirect address, as the page had it

proc redirectOf(url: string): string =
  formDecode(url[url.find('?') + 1 .. ^1]).param("redirect_uri")

proc browse(url: string) {.gcsafe.} =
  ## The browser: opens the page and follows it back to the app.
  {.cast(gcsafe).}:
    loopback = redirectOf(url)
    let r = httpRequest("GET", url)
    pages.add (r.status, r.body)

proc noBrowser(url: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    loopback = redirectOf(url)

proc waitEnd(f: OAuthFlow; seconds = 10.0): OAuthState =
  let until = epochTime() + seconds
  while f.state == osWaiting and epochTime() < until: sleep(20)
  f.state

proc mock(p: OAuthProvider): OAuthProvider =
  result = p
  result.authUrl = base & "/authorize"
  result.tokenUrl = base & "/token"

var google = mock(googleProvider("google-client", "not-secret", ["https://mail.google.com/"]))
var microsoft = mock(microsoftProvider("ms-client", scopes = ["https://graph.microsoft.com/Mail.ReadWrite"]))

# ---- sign-ins -------------------------------------------------------------------------------------

block googleSignIn:
  pages.setLen(0)
  let f = beginSignIn(google, loginHint = "sultan@example.com", openBrowser = browse)
  doAssert f.waitEnd() == osDone, f.error
  let t = f.tokens
  doAssert t.accessToken == "at-1" and t.refreshToken == "rt-1" and t.idToken == idToken
  doAssert t.scope == "openid email" and abs(t.expiresAt - (epochTime() + 3600)) < 30
  doAssert f.error == ""
  let who = claims(t)
  doAssert who["email"].getStr == "sultan@example.com" and who["name"].getStr == "Sultan Al Isaiee"
  # the browser's last page: plain, no script
  doAssert pages.len == 1 and pages[0].status == 200, $pages
  doAssert "Signed in" in pages[0].body and "with Google" in pages[0].body
  doAssert "<script" notin pages[0].body.toLowerAscii
  # the sign-in page's address had all it needs
  let q = formDecode(f.url[f.url.find('?') + 1 .. ^1])
  doAssert f.url.startsWith(base & "/authorize?")
  doAssert q.param("client_id") == "google-client" and q.param("response_type") == "code"
  doAssert q.param("redirect_uri").startsWith("http://127.0.0.1:") and q.param("redirect_uri").endsWith("/")
  doAssert q.param("scope") == "https://mail.google.com/ openid email profile"
  doAssert q.param("code_challenge_method") == "S256" and q.param("code_challenge").len == 43
  doAssert q.param("state").len >= 16 and q.param("login_hint") == "sultan@example.com"
  doAssert q.param("access_type") == "offline" and q.param("prompt") == "consent"
  doAssert q.param("client_secret") == ""                    # (never on the page)
  # the app no longer listens: a second visit finds no one
  sleep(100)
  let again = httpRequest("GET", loopback & "?code=x&state=" & q.param("state"), timeoutSec = 3)
  doAssert again.status == 0, $again.status

block microsoftSignIn:
  pages.setLen(0)
  let f = beginSignIn(microsoft, openBrowser = browse)
  doAssert f.waitEnd() == osDone, f.error
  doAssert f.tokens.accessToken == "at-1"
  doAssert loopback.startsWith("http://localhost:") and loopback.endsWith("/"), loopback
  doAssert "with Microsoft" in pages[^1].body
  withLock mockLock:
    doAssert authorizeSeen.param("login_hint") == "" and authorizeSeen.param("client_id") == "ms-client"
    doAssert "offline_access" in authorizeSeen.param("scope")

block wrongStateAndOtherPages:
  pages.setLen(0)
  let f = beginSignIn(google, openBrowser = noBrowser)
  doAssert f.state == osWaiting
  let wrong = httpRequest("GET", loopback & "?code=stolen&state=not-the-one")
  doAssert wrong.status == 400 and "another sign-in" in wrong.body
  let icon = httpRequest("GET", loopback & "favicon.ico")
  doAssert icon.status == 404
  let bare = httpRequest("GET", loopback)
  doAssert bare.status == 400
  let noCode = httpRequest("GET", loopback & "?state=x")
  doAssert noCode.status == 400
  let posted = httpRequest("POST", loopback & "?code=a&state=b", body = "x")
  doAssert posted.status == 404
  # raw garbage, and a connection that says nothing
  let port = parseInt(loopback.split(':')[2].strip(chars = {'/'}))
  let junk = newSocket()
  junk.connect("127.0.0.1", Port(port))
  junk.send("\x00\xff garbage\r\n\r\n")
  discard junk.recv(100, timeout = 2000)
  junk.close()
  let idle = newSocket()
  idle.connect("127.0.0.1", Port(port))
  doAssert f.state == osWaiting
  # then the real answer
  browse(f.url)
  doAssert f.waitEnd() == osDone, f.error
  doAssert f.tokens.refreshToken == "rt-1"
  idle.close()

block refused:
  pages.setLen(0)
  proc deny(url: string) {.gcsafe.} = browse(url.replace("/authorize?", "/authorize-deny?"))
  let f = beginSignIn(google, openBrowser = deny)
  doAssert f.waitEnd() == osFailed
  doAssert "refused or cancelled" in f.error and "access_denied" in f.error and "The user said no." in f.error, f.error
  doAssert f.tokens.accessToken == ""
  doAssert "did not work" in pages[^1].body

block pkceChecked:
  # the token endpoint refuses a verifier that is not the challenge's
  pages.setLen(0)
  proc tamper(url: string) {.gcsafe.} =
    let q = formDecode(url[url.find('?') + 1 .. ^1])
    browse(url.replace("code_challenge=" & q.param("code_challenge"),
                       "code_challenge=" & b64url(sha256("another verifier").toBinary)))
  let f = beginSignIn(google, openBrowser = tamper)
  doAssert f.waitEnd() == osFailed
  doAssert "sign in again" in f.error and "invalid_grant" in f.error and "AADSTS501481" in f.error, f.error
  doAssert "Trace ID" notin f.error
  doAssert "did not work" in pages[^1].body
  # and a code works once
  let direct = httpRequest("POST", base & "/token", {"Content-Type": "application/x-www-form-urlencoded"},
                           formEncode({"grant_type": "authorization_code", "code": "code-1",
                                       "client_id": "google-client"}))
  doAssert direct.status == 400 and "invalid_grant" in direct.body

block wrongSecret:
  var bad = google
  bad.clientSecret = "guessed"
  let f = beginSignIn(bad, openBrowser = browse)
  doAssert f.waitEnd() == osFailed and "client id or secret" in f.error, f.error

block cancelling:
  let f = beginSignIn(google, loginHint = "x@example.com", openBrowser = noBrowser)
  doAssert f.state == osWaiting and f.url.len > 0
  let addressBefore = loopback
  f.cancel()
  doAssert f.state == osCancelled and f.error == "" and f.tokens.accessToken == ""
  sleep(600)                                   # (the thread sees it within 0.2 s)
  let after = httpRequest("GET", addressBefore & "?code=x&state=y", timeoutSec = 3)
  doAssert after.status == 0, "the port is let go"
  # cancelling after the end changes nothing
  let g = beginSignIn(google, openBrowser = browse)
  doAssert g.waitEnd() == osDone
  g.cancel()
  doAssert g.state == osDone

block manySignIns:
  # more than can run at once, one after another: the ended ones make room
  for i in 0 ..< 12:
    let f = beginSignIn(google, openBrowser = browse)
    doAssert f.waitEnd() == osDone, $i & ": " & f.error
  for i in 0 ..< 3:                            # flows dropped while waiting
    discard beginSignIn(google, openBrowser = noBrowser)
  sleep(500)
  let f = beginSignIn(google, openBrowser = browse)
  doAssert f.waitEnd() == osDone, f.error

# ---- refreshing ----------------------------------------------------------------------------------

block refreshing:
  let f = beginSignIn(google, openBrowser = browse)
  doAssert f.waitEnd() == osDone
  var t = f.tokens
  let first = t
  doAssert google.refresh(t) == ""
  doAssert t.accessToken == "at-2" and t.refreshToken == "rt-1", "the old refresh token is kept"
  doAssert t.idToken == first.idToken and t.scope == first.scope
  doAssert abs(t.expiresAt - (epochTime() + 1800)) < 30
  withLock mockLock: doAssert lastScope == "", "Google gets no scopes when refreshing"
  # fresh enough: nothing is asked
  var calls: int
  withLock mockLock: calls = tokenCalls
  doAssert google.ensureFresh(t) == ""
  withLock mockLock: doAssert tokenCalls == calls
  # within the margin: refreshed
  t.accessToken = "old"
  t.expiresAt = epochTime() + 60
  doAssert google.ensureFresh(t) == "" and t.accessToken == "at-2"
  withLock mockLock: doAssert tokenCalls == calls + 1
  # Microsoft: the scopes go along; a new refresh token replaces the old one
  var m = OAuthTokens(accessToken: "a", refreshToken: "rotating", expiresAt: 0)
  doAssert microsoft.ensureFresh(m) == "" and m.accessToken == "at-3" and m.refreshToken == "rotated"
  withLock mockLock: doAssert "offline_access" in lastScope and "Mail.ReadWrite" in lastScope
  # a refresh token that ran out: in words, and the tokens stay as they were
  var gone = OAuthTokens(accessToken: "a", refreshToken: "expired", expiresAt: epochTime() - 5)
  let err = microsoft.ensureFresh(gone)
  doAssert "sign in again" in err and "AADSTS700082" in err, err
  doAssert gone.refreshToken == "expired" and gone.accessToken == "a"
  # ...but while the old token still has time, it is good to use
  var still = OAuthTokens(accessToken: "a", refreshToken: "expired", expiresAt: epochTime() + 60)
  doAssert microsoft.ensureFresh(still) == "" and still.accessToken == "a"
  var none = OAuthTokens(accessToken: "a")
  doAssert "no refresh token" in google.refresh(none)
  var away = google
  away.tokenUrl = "http://127.0.0.1:1/token"
  var t2 = OAuthTokens(refreshToken: "rt-1")
  doAssert google.refresh(t2) == "" and away.refresh(t2).startsWith("could not reach Google")

echo "oauth: ok"
