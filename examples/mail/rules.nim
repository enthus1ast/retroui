## Retro Mail's rules: what to do with mail as it arrives, in every
## account, decided here (not on the server). A rule's conditions (who it
## is from, who it is to, the subject, the body, an attachment, the
## account) are matched all or any; its actions put tags on, move, mark
## read, flag, pin or delete, and may stop the rules after it. Pure
## functions: the window keeps the rules, the sync applies the result.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[json, strutils]
from std/unicode import runes, toLower, isWhiteSpace, add
import store

type
  RuleField* = enum
    rfFrom = "from"               ## the sender's name or address contains `text`
    rfToCc = "tocc"               ## To or Cc contains `text`
    rfSubject = "subject"         ## the subject contains `text`
    rfBody = "body"               ## the body (as far as it is here) contains `text`
    rfAttachment = "attachment"   ## it has an attachment
    rfAccount = "account"         ## it came to account `account`
    rfThread = "thread"           ## it is in conversation `text` (Ignore Conversation)
  Condition* = object
    field*: RuleField
    text*: string                 ## what to look for, any case; several: separated by ";"
    account*: int
  Rule* = object
    id*: int
    name*: string
    enabled*: bool
    matchAll*: bool               ## every condition (else any); no conditions: every message
    conditions*: seq[Condition]
    tags*: seq[string]            ## tags to put on
    moveTo*: string               ## a folder's role ("archive") or remote id; "" stays
    markRead*, flag*, pin*, delete*: bool
    stop*: bool                   ## no rule after this one (when it matched)
  RuleResult* = object
    matched*: seq[int]            ## the ids of the rules that matched, in order
    tags*: seq[string]            ## to put on, each once, in the rules' order
    moveTo*: string               ## the first move a matching rule asks ("" none)
    markRead*, flag*, pin*: bool
    delete*: bool                 ## to the trash (it goes before `moveTo`)

proc fold(s: string): string =
  ## For matching: lower case (any script), without Arabic's diacritics
  ## and tatweel, spaces run together.
  var space = false
  for r in s.toLower.runes:
    let c = int(r)
    if c == 0x640 or c in 0x64B .. 0x652 or c == 0x670: continue
    if r.isWhiteSpace:
      if not space: result.add ' '
      space = true
    else:
      result.add r
      space = false

proc holdsAny(hay, needles: string): bool =
  ## `hay` (already folded) holds any of `needles` (";" or line separated).
  for n in needles.replace('\n', ';').split(';'):
    let f = fold(n).strip
    if f.len > 0 and f in hay: return true

proc bodyOf(m: Msg): string =
  if m.text.len > 0: return m.text
  if m.html.len > 0:
    var inTag = false
    for c in m.html:
      if c == '<': inTag = true
      elif c == '>': (inTag = false; result.add ' ')
      elif not inTag: result.add c
    return
  m.snippet

proc test(c: Condition; m: Msg): bool =
  case c.field
  of rfFrom: fold(m.fromName & " " & m.fromEmail).holdsAny(c.text)
  of rfToCc: fold(m.toList & " " & m.ccList).holdsAny(c.text)
  of rfSubject: fold(m.subject).holdsAny(c.text)
  of rfBody: fold(bodyOf(m)).holdsAny(c.text)
  of rfAttachment: m.hasAtt
  of rfAccount: m.account == c.account
  of rfThread: c.text.len > 0 and m.thread == c.text

proc matches*(r: Rule; m: Msg): bool =
  ## The rule applies to `m` (never when it is off).
  if not r.enabled: return false
  if r.conditions.len == 0: return true
  if r.matchAll:
    for c in r.conditions:
      if not c.test(m): return false
    true
  else:
    for c in r.conditions:
      if c.test(m): return true
    false

proc ruleActions*(rules: seq[Rule]; m: Msg): RuleResult =
  ## What the rules, in order, do with `m`, up to one that matches and says
  ## stop.
  for r in rules:
    if not r.matches(m): continue
    result.matched.add r.id
    for t in r.tags:
      let n = t.strip
      if n.len == 0: continue
      var have = false
      for x in result.tags:
        if cmpIgnoreCase(x, n) == 0 or fold(x) == fold(n): (have = true; break)
      if not have: result.tags.add n
    if r.moveTo.len > 0 and result.moveTo.len == 0: result.moveTo = r.moveTo
    result.markRead = result.markRead or r.markRead
    result.flag = result.flag or r.flag
    result.pin = result.pin or r.pin
    result.delete = result.delete or r.delete
    if r.stop: break

# ---- kept as JSON ------------------------------------------------------------------------

proc toJson*(r: Rule): JsonNode =
  var conds = newJArray()
  for c in r.conditions:
    var j = %*{"field": $c.field}
    case c.field
    of rfAccount: j["account"] = %c.account
    of rfAttachment: discard
    else: j["text"] = %c.text
    conds.add j
  %*{"id": r.id, "name": r.name, "enabled": r.enabled, "match": (if r.matchAll: "all" else: "any"),
     "conditions": conds,
     "actions": {"tags": r.tags, "moveTo": r.moveTo, "markRead": r.markRead, "flag": r.flag,
                 "pin": r.pin, "delete": r.delete, "stop": r.stop}}

proc toJson*(rules: seq[Rule]): JsonNode =
  result = newJArray()
  for r in rules: result.add r.toJson

proc fromJson*(j: JsonNode): Rule =
  ## A rule as `toJson` wrote it (what is missing: off for actions, on for
  ## `enabled`, "all" for the match; conditions not known are left out).
  if j == nil or j.kind != JObject: return
  result.id = j{"id"}.getInt
  result.name = j{"name"}.getStr
  result.enabled = j{"enabled"}.getBool(true)
  result.matchAll = j{"match"}.getStr("all") != "any"
  for c in j{"conditions"}.getElems:
    var f: RuleField
    try: f = parseEnum[RuleField](c{"field"}.getStr)
    except ValueError: continue
    result.conditions.add Condition(field: f, text: c{"text"}.getStr, account: c{"account"}.getInt)
  let a = j{"actions"}
  for t in a{"tags"}.getElems:
    if t.getStr.strip.len > 0: result.tags.add t.getStr.strip
  result.moveTo = a{"moveTo"}.getStr
  result.markRead = a{"markRead"}.getBool
  result.flag = a{"flag"}.getBool
  result.pin = a{"pin"}.getBool
  result.delete = a{"delete"}.getBool
  result.stop = a{"stop"}.getBool

proc rulesFromJson*(j: JsonNode): seq[Rule] =
  for x in j.getElems: result.add fromJson(x)
