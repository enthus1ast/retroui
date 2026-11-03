## What Retro Mail's two services have in common: the addresses of their
## APIs (changeable for tests), calls with a sign-in token, errors.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, json, strutils, times]
import retro/http

type
  ApiError* = object of CatchableError
    status*: int           ## the HTTP status (0: no connection)
    retryAfter*: float     ## seconds the server asked to wait (429, 503)

proc endpoint*(name, default: string): string =
  ## A service's address: RETRO_MAIL_<NAME> overrides it (for tests).
  getEnv("RETRO_MAIL_" & name.toUpperAscii, default)

proc graphBase*(): string = endpoint("graph", "https://graph.microsoft.com/v1.0")
proc gmailBase*(): string = endpoint("gmail", "https://gmail.googleapis.com")
proc gcalBase*(): string = endpoint("gcal", "https://www.googleapis.com/calendar/v3")
proc msLoginBase*(): string = endpoint("mslogin", "https://login.microsoftonline.com")
proc gAuthUrl*(): string = endpoint("gauth", "https://accounts.google.com/o/oauth2/v2/auth")
proc gTokenUrl*(): string = endpoint("gtoken", "https://oauth2.googleapis.com/token")

proc fail*(r: HttpResponse; what: string) {.noreturn.} =
  ## Raises the error a failed answer stands for, with the service's message.
  var msg = ""
  try:
    let j = parseJson(r.body)
    if j.kind == JObject:
      let e = j{"error"}
      if e != nil and e.kind == JObject:
        msg = e{"message"}.getStr
        if msg.len == 0: msg = e{"code"}.getStr
      elif e != nil and e.kind == JString:
        msg = e.getStr & (if j{"error_description"} != nil: ": " & j{"error_description"}.getStr else: "")
  except CatchableError: discard
  if msg.len == 0:
    msg = if r.status == 0: (if r.error.len > 0: r.error else: "no connection")
          else: "the server answered " & $r.status
  var e = newException(ApiError, what & ": " & msg)
  e.status = r.status
  let ra = r.header("retry-after")
  e.retryAfter = try: parseFloat(ra.strip) except ValueError: 0.0
  raise e

proc call*(meth, url, token: string; body = ""; contentType = "application/json";
           extra: openArray[(string, string)] = []; timeout = 60): HttpResponse =
  ## One call with the token; the answer whatever it is.
  var hs = @[("Authorization", "Bearer " & token), ("Accept", "application/json")]
  if body.len > 0 or meth in ["POST", "PATCH", "PUT"]: hs.add ("Content-Type", contentType)
  for h in extra: hs.add h
  httpRequest(meth, url, hs, body, timeoutSec = timeout)

proc callJson*(meth, url, token: string; body: JsonNode = nil;
               extra: openArray[(string, string)] = []; what = "the server"): JsonNode =
  ## A call that must work, its JSON answer (an empty object for none).
  let r = call(meth, url, token, (if body == nil: "" else: $body), extra = extra)
  if not r.ok: fail(r, what)
  if r.body.strip.len == 0: return newJObject()
  try: parseJson(r.body)
  except CatchableError: newJObject()

proc isoTime*(t: float): string =
  ## An instant for an API: 2026-11-03T10:00:00Z.
  fromUnixFloat(t).utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc parseIso*(s: string): float =
  ## An ISO 8601 instant (with Z, an offset or neither: UTC) as epoch seconds.
  if s.len < 19: return 0
  try:
    var base = s[0 ..< 19]
    var t = parse(base, "yyyy-MM-dd'T'HH:mm:ss", utc()).toTime.toUnixFloat
    var rest = s[19 .. ^1]
    if rest.startsWith("."):
      var i = 1
      while i < rest.len and rest[i].isDigit: inc i
      rest = rest[i .. ^1]
    if rest.len >= 6 and rest[0] in {'+', '-'}:
      let sign = if rest[0] == '+': -1.0 else: 1.0
      let h = parseInt(rest[1 .. 2])
      let m = parseInt(rest[4 .. 5])
      t += sign * float(h * 3600 + m * 60)
    t
  except CatchableError: 0.0
