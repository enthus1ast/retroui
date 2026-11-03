## Retro Mail 1.0.2's new engine parts against the stand-in services
## (tests/mailmock.py): meeting invitations (and the iCalendar reading and
## writing under them), automatic replies, the assistant (summary,
## translation, replies), rules, forwarding as an attachment.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, osproc, json, strutils, times, net, exitprocs, sequtils]
from std/unicode import validateUtf8
import retro/[http, mime]
import ../examples/mail/[store, api, graph, gmail, ical, invites, autoreply, assist, rules, forward]

proc freePort(): int =
  let s = newSocket()
  s.bindAddr(Port(0), "127.0.0.1")
  result = int s.getLocalAddr()[1]
  s.close()

let port = freePort()
let base = "http://127.0.0.1:" & $port
let home = getTempDir() / "retro-mailextra-test-" & $getCurrentProcessId()
removeDir(home)
createDir(home)
putEnv("RETRO_MAIL_HOME", home)
putEnv("RETRO_MAIL_GRAPH", base & "/v1.0")
putEnv("RETRO_MAIL_GMAIL", base)
putEnv("RETRO_MAIL_GCAL", base & "/calendar/v3")
putEnv("RETRO_MAIL_AI", base & "/ai")

let mock = startProcess("python3", args = [currentSourcePath().parentDir / "mailmock.py", $port],
                        options = {poUsePath, poParentStreams})
addExitProc(proc () = mock.terminate())
for i in 0 .. 50:
  if httpRequest("GET", base & "/test/state").status == 200: break
  sleep(100)

var failures = 0
template check(cond: bool; what: string) =
  if cond: echo "  ok   ", what
  else:
    echo "  FAIL ", what
    inc failures

proc extraState(): JsonNode = parseJson(httpRequest("GET", base & "/test/extra").body)

proc tokenFrom(url: string): string =
  let r = httpRequest("POST", url, [("Content-Type", "application/x-www-form-urlencoded")],
                      formEncode({"grant_type": "refresh_token", "refresh_token": "rt-test",
                                  "client_id": "test"}))
  parseJson(r.body){"access_token"}.getStr

proc utcT(y, mo, d, h, mi: int): float =
  dateTime(y, Month(mo), d, h, mi, 0, 0, utc()).toTime.toUnixFloat

proc localDay(y, mo, d: int): float =
  dateTime(y, Month(mo), d, 0, 0, 0, 0, local()).toTime.toUnixFloat

let mtok = tokenFrom(base & "/ms/organizations/oauth2/v2.0/token")
let gtok = tokenFrom(base & "/g/token")
let msA = Account(id: 1, kind: akGraph, email: "sultan@contoso.com", name: "Sultan Al Isaiee")
let gmA = Account(id: 2, kind: akGmail, email: "foxoman@gmail.example", name: "Sultan")

# ---- iCalendar ------------------------------------------------------------------------------

echo "iCalendar"
check contentLines("A:one\r\n two\r\n\tthree\r\nB:x\nC:y\n  z\r\n") == @["A:onetwothree", "B:x", "C:y z"],
      "lines unfolded (CRLF and LF, a space or a tab)"
let ap = parseLine("ATTENDEE;CN=\"Al Isaiee, Sultan: HR\";partstat=needs-action;MEMBER=\"mailto:a@x\"," &
                   "\"mailto:b@x\";X-T=a^'b^nc:MAILTO:Sultan@Contoso.com")
check ap.name == "ATTENDEE" and ap.param("cn") == "Al Isaiee, Sultan: HR" and
      ap.param("PARTSTAT") == "needs-action" and ap.param("member") == "mailto:a@x,mailto:b@x" and
      mailto(ap.value) == "Sultan@Contoso.com", "parameters: quoted (with , and :), several values, any case"
check ap.param("X-T") == "a\"b\nc", "parameters: RFC 6868's ^ escapes"
check unescapeText("a\\, b\\; c\\nd\\Ne\\\\f") == "a, b; c\nd\ne\\f", "text unescaped"
check escapeText("a, b; c\r\nd\\e") == "a\\, b\\; c\\nd\\\\e", "text escaped"
let longLine = "SUMMARY:" & "اجتماع فريق الموارد البشرية ".repeat(4)
let folded = foldLine(longLine)
var foldOk = folded.endsWith("\r\n")
for l in folded[0 ..< ^2].split("\r\n"):
  if l.len > 75 or validateUtf8(l) >= 0: foldOk = false
check foldOk and folded.count("\r\n") > 2 and contentLines(folded) == @[longLine],
      "folded at 75 octets, never inside a character, and unfolded back"
check timeOf(nil, parseLine("DTSTART:20261110T060000Z")) == (utcT(2026, 11, 10, 6, 0), false), "a UTC time"
let custom = parseIcal("BEGIN:VCALENDAR\r\nBEGIN:VTIMEZONE\r\nTZID:Custom/Zone\r\nBEGIN:DAYLIGHT\r\n" &
  "TZOFFSETFROM:-0500\r\nTZOFFSETTO:-0400\r\nDTSTART:19700308T020000\r\nRRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU\r\n" &
  "END:DAYLIGHT\r\nBEGIN:STANDARD\r\nTZOFFSETFROM:-0400\r\nTZOFFSETTO:-0500\r\nDTSTART:19701101T020000\r\n" &
  "RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\nEND:VCALENDAR\r\n").child("VCALENDAR")
proc at(cal: IcalComp; line: string): float = timeOf(cal, parseLine(line)).t
check custom.at("DTSTART;TZID=Custom/Zone:20260715T090000") == utcT(2026, 7, 15, 13, 0) and
      custom.at("DTSTART;TZID=Custom/Zone:20261215T090000") == utcT(2026, 12, 15, 14, 0),
      "TZID through the calendar's VTIMEZONE (summer and winter rules)"
check custom.at("DTSTART;TZID=Custom/Zone:20261101T013000") == utcT(2026, 11, 1, 5, 30) and
      custom.at("DTSTART;TZID=Custom/Zone:20260308T023000") == utcT(2026, 3, 8, 7, 30),
      "TZID: the repeated hour (the first) and the skipped one (the offset before)"
check at(nil, "DTSTART;TZID=Europe/Paris:20260715T090000") == utcT(2026, 7, 15, 7, 0) and
      at(nil, "DTSTART;TZID=Europe/Paris:20260115T090000") == utcT(2026, 1, 15, 8, 0) and
      at(nil, "DTSTART;TZID=America/New_York:20260715T090000") == utcT(2026, 7, 15, 13, 0),
      "TZID without a VTIMEZONE: well-known zones with their summer time"
check at(nil, "DTSTART;TZID=Arabian Standard Time:20261110T100000") == utcT(2026, 11, 10, 6, 0) and
      at(nil, "DTSTART;TZID=/mozilla.org/20070129_1/Asia/Muscat:20261110T100000") == utcT(2026, 11, 10, 6, 0) and
      at(nil, "DTSTART;TZID=\"(UTC+04:00) Abu Dhabi, Muscat\":20261110T100000") == utcT(2026, 11, 10, 6, 0),
      "TZID: Windows' names, Mozilla's prefix, Outlook's old \"(UTC+04:00)\""
check at(nil, "DTSTART;TZID=Nowhere/Land:20261110T100000") == at(nil, "DTSTART:20261110T100000"),
      "a zone not known: the device's time, as a floating one"
check timeOf(nil, parseLine("DTSTART;VALUE=DATE:20261118")) == (localDay(2026, 11, 18), true) and
      timeOf(nil, parseLine("DTSTART:20261118")).allDay, "whole days at the local midnight"
check durationSecs("PT1H30M") == 5400 and durationSecs("P1D") == 86400 and durationSecs("-PT15M") == -900 and
      durationSecs("P2W") == 1209600, "durations"
check zoneToUtc("2026-11-20T08:00:00.0000000", "Arabian Standard Time") == utcT(2026, 11, 20, 4, 0) and
      zoneToUtc("2026-11-20T08:00:00", "UTC") == utcT(2026, 11, 20, 8, 0), "Graph's dateTime and timeZone"
check not parseStamp("20260230T100000").ok and not parseStamp("2026111").ok, "impossible dates refused"

const reqIcs = "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nBEGIN:VEVENT\r\nUID:abc-1\r\nRECURRENCE-ID:20261117T060000Z\r\n" &
  "DTSTART:20261117T070000Z\r\nSUMMARY:Moved\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:abc-1\r\nSEQUENCE:3\r\n" &
  "DTSTART:20261110T060000Z\r\nDURATION:PT45M\r\nSUMMARY:Review\\, round 2\r\n" &
  "ORGANIZER;CN=\"Rawahi, Ahmed\":mailto:ahmed@contoso.com\r\n" &
  "ATTENDEE;PARTSTAT=ACCEPTED;CN=Ahmed:mailto:ahmed@contoso.com\r\n" &
  "ATTENDEE;PARTSTAT=TENTATIVE;RSVP=TRUE;CN=Sultan:mailto:sultan@contoso.com\r\nRRULE:FREQ=WEEKLY\r\n" &
  "END:VEVENT\r\nEND:VCALENDAR\r\n"
let pi = parseInvite(reqIcs, "SULTAN@contoso.com")
check pi.kind == ikRequest and pi.uid == "abc-1" and pi.sequence == 3 and pi.title == "Review, round 2" and
      pi.recurring and pi.recurrenceId == "", "a request: the series, not one moved occurrence"
check pi.start == utcT(2026, 11, 10, 6, 0) and pi.finish == pi.start + 2700, "a DURATION for the end"
check pi.organizerName == "Rawahi, Ahmed" and pi.organizerEmail == "ahmed@contoso.com" and
      pi.attendeeEmail == "sultan@contoso.com" and pi.answer == iaTentative and pi.rsvp,
      "the organizer, and the account's own line among the attendees (any case)"
check parseInvite(reqIcs.replace("METHOD:REQUEST", "METHOD:CANCEL"), "x").kind == ikCancel and
      parseInvite(reqIcs.replace("SEQUENCE:3", "SEQUENCE:3\r\nSTATUS:CANCELLED"), "x").kind == ikCancel,
      "cancelled (METHOD:CANCEL, or STATUS:CANCELLED)"
let rep = parseInvite("BEGIN:VCALENDAR\r\nMETHOD:REPLY\r\nBEGIN:VEVENT\r\nUID:u\r\n" &
  "ATTENDEE;PARTSTAT=DECLINED;CN=Muna:mailto:muna@contoso.com\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n", "x")
check rep.kind == ikReply and rep.replyEmail == "muna@contoso.com" and rep.replyName == "Muna" and
      rep.replyAnswer == iaDecline, "someone's answer (METHOD:REPLY)"
check parseInvite(reqIcs.replace("METHOD:REQUEST", "METHOD:PUBLISH"), "x").kind == ikNone and
      parseInvite("hello", "x").kind == ikNone and parseInvite("BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nEND:VCALENDAR", "x").kind == ikNone,
      "not invitations: a published calendar, text, no event"
check parseInvite(reqIcs.replace("METHOD:REQUEST\r\n", ""), "x", methodHint = "request").kind == ikRequest,
      "no METHOD: the part's method= says"

var inv = Invite(kind: ikRequest, uid: "7kq3trip2026@google.com", sequence: 2, title: "Trip planning, day 1",
                 start: utcT(2026, 11, 10, 6, 0), finish: utcT(2026, 11, 10, 7, 30),
                 organizerName: "Khalid Al Siyabi", organizerEmail: "khalid@example.om",
                 attendeeEmail: "foxoman@gmail.example", msgId: "<gi1@mail.gmail.example>")
let stamp = utcT(2026, 11, 3, 9, 15)
check replyIcs(inv, iaAccept, "Sultan", "foxoman@gmail.example", "See you there; I'll drive", stamp) ==
  "BEGIN:VCALENDAR\r\nPRODID:-//foxoman.net//Retro Mail//EN\r\nVERSION:2.0\r\nCALSCALE:GREGORIAN\r\n" &
  "METHOD:REPLY\r\nBEGIN:VEVENT\r\nUID:7kq3trip2026@google.com\r\nSEQUENCE:2\r\nDTSTAMP:20261103T091500Z\r\n" &
  "DTSTART:20261110T060000Z\r\nDTEND:20261110T073000Z\r\nSUMMARY:Trip planning\\, day 1\r\n" &
  "ORGANIZER;CN=Khalid Al Siyabi:mailto:khalid@example.om\r\n" &
  "ATTENDEE;PARTSTAT=ACCEPTED;CN=Sultan:mailto:foxoman@gmail.example\r\n" &
  "COMMENT:See you there\\; I'll drive\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n", "the REPLY, line by line"
var day = inv
day.allDay = true
day.start = localDay(2026, 11, 18)
day.finish = localDay(2026, 11, 20)
day.recurrenceId = "20261118"
day.organizerName = "Al Balushi, Muna"
let dayLines = contentLines(replyIcs(day, iaDecline, "", "foxoman@gmail.example", now = stamp))
check "DTSTART;VALUE=DATE:20261118" in dayLines and "DTEND;VALUE=DATE:20261120" in dayLines and
      "RECURRENCE-ID;VALUE=DATE:20261118" in dayLines and
      "ORGANIZER;CN=\"Al Balushi, Muna\":mailto:khalid@example.om" in dayLines and
      "ATTENDEE;PARTSTAT=DECLINED:mailto:foxoman@gmail.example" in dayLines and
      not dayLines.anyIt(it.startsWith("COMMENT")), "a REPLY for whole days, one occurrence, a quoted CN, declined"
check "ATTENDEE;PARTSTAT=TENTATIVE;CN=S:mailto:foxoman@gmail.example" in
      contentLines(replyIcs(inv, iaTentative, "S", "other@x", now = stamp)),
      "the attendee as the invitation named it"
let rm = parseMime(replyMail(inv, iaAccept, MailAddress(name: "Sultan", email: "foxoman@gmail.example"),
                             "سأحضر الخرائط", stamp))
check rm.contentType == "multipart/alternative" and rm.parts.len == 2 and
      rm.parts[0].contentType == "text/plain" and rm.parts[1].contentType == "text/calendar" and
      rm.parts[1].param("method") == "REPLY", "the reply message: text and text/calendar; method=REPLY"
check "COMMENT:سأحضر الخرائط" in contentLines(textOf(rm.parts[1])) and "سأحضر الخرائط" in textOf(rm.parts[0]),
      "the comment in both (base64 for Arabic)"
check rm.decodedHeader("Subject") == "Accepted: Trip planning, day 1" and "khalid@example.om" in rm.header("To") and
      rm.header("In-Reply-To") == "<gi1@mail.gmail.example>", "its subject, organizer and thread"

# ---- invitations against the services --------------------------------------------------------

echo "invitations: Microsoft 365"
discard httpRequest("POST", base & "/test/invites")
let gi = inviteOf(msA, mtok, Msg(remoteId: "inv1", thread: "cinv1"))
check gi.kind == ikRequest and gi.eventId == "ev-1" and gi.title == "Photo app review" and
      gi.location == "Room 2" and gi.organizerEmail == "ahmed@contoso.com" and gi.answer == iaNone and
      gi.rsvp and gi.uid.startsWith("0400000082"), "an invitation: its event expanded"
check gi.start == utcT(2026, 11, 12, 6, 0) and gi.finish == utcT(2026, 11, 12, 7, 0) and not gi.allDay, "its times"
check inviteOf(msA, mtok, Msg(remoteId: "m1")).kind == ikNone, "other mail: not an invitation"
check inviteOf(msA, mtok, Msg(remoteId: "inv2")).kind == ikCancel, "a cancellation"
respondInvite(msA, mtok, gi, iaAccept, "Fine by me")
respondInvite(msA, mtok, gi, iaTentative, sendReply = false)
respondInvite(msA, mtok, gi, iaDecline)
let ans = extraState()["extra"]["answers"]
check ans.len == 3 and ans[0]["event"].getStr == "ev-1" and ans[0]["action"].getStr == "accept" and
      ans[0]["comment"].getStr == "Fine by me" and ans[0]["sendResponse"].getBool, "accepted, with a comment"
check ans.len == 3 and ans[1]["action"].getStr == "tentativelyAccept" and not ans[1]["sendResponse"].getBool and
      ans[2]["action"].getStr == "decline", "tentatively (without telling the organizer), declined"
check inviteOf(msA, mtok, Msg(remoteId: "inv1")).answer == iaDecline, "the answer seen in the event"
var gone = gi
gone.eventId = "ev-nope"
var e404 = 0
try: respondInvite(msA, mtok, gone, iaAccept)
except ApiError as e: e404 = e.status
var noAnswer = false
try: respondInvite(msA, mtok, gi, iaNone)
except ValueError: noAnswer = true
check e404 == 404 and noAnswer, "an event no longer there: the service's 404; no answer: refused here"

echo "invitations: Gmail"
let g1 = inviteOf(gmA, gtok, Msg(remoteId: "gi1", thread: "ti1"))
check g1.kind == ikRequest and g1.uid == "7kq3trip2026@google.com" and g1.sequence == 2 and
      g1.title == "Trip planning" and g1.location == "Jebel Shams, Al Hamra", "an invitation's text/calendar part"
check g1.description == "Agenda:\n1. Photos, maps and the route\n2. Who drives – رحلة جبل شمس; bring water",
      "a folded, escaped, Arabic description"
check g1.start == utcT(2026, 11, 10, 6, 0) and g1.finish == utcT(2026, 11, 10, 7, 30), "TZID=Asia/Muscat"
check g1.organizerName == "Khalid Al Siyabi" and g1.organizerEmail == "khalid@example.om" and
      g1.attendeeEmail == "foxoman@gmail.example" and g1.answer == iaNone and g1.rsvp and
      g1.threadId == "ti1" and g1.msgId == "<gi1@mail.gmail.example>", "organizer, attendee, thread"
let g2 = inviteOf(gmA, gtok, Msg(remoteId: "gi2"))
check g2.kind == ikRequest and g2.allDay and g2.start == localDay(2026, 11, 18) and
      g2.finish == localDay(2026, 11, 20) and g2.attendeeEmail == "FOXOMAN@gmail.example" and
      g2.title == "National Day holiday", "an Outlook invitation kept as an attachment: whole days"
check inviteOf(gmA, gtok, Msg(remoteId: "g1")).kind == ikNone, "other mail: not an invitation"
respondInvite(gmA, gtok, g1, iaAccept, "I'll bring the maps")
let st1 = extraState()
let raws = st1["extra"]["raw_sent"].getElems
check raws.len == 1 and st1["gsent"].getElems[^1]["threadId"].getStr == "ti1", "the REPLY sent in the invitation's thread"
if raws.len == 1:
  let sm = parseMime(raws[0].getStr)
  var cal: MimePart
  for p in sm.parts:
    if p.contentType == "text/calendar": cal = p
  check sm.decodedHeader("Subject") == "Accepted: Trip planning" and "khalid@example.om" in sm.header("To") and
        "foxoman@gmail.example" in sm.header("From") and sm.header("In-Reply-To") == "<gi1@mail.gmail.example>",
        "to the organizer, from the account, threaded"
  let cl = if cal.isNil: @[] else: contentLines(textOf(cal))
  check not cal.isNil and cal.param("method") == "REPLY" and "METHOD:REPLY" in cl and
        "UID:7kq3trip2026@google.com" in cl and "SEQUENCE:2" in cl and "DTSTART:20261110T060000Z" in cl and
        "ATTENDEE;PARTSTAT=ACCEPTED;CN=Sultan:mailto:foxoman@gmail.example" in cl and
        "ORGANIZER;CN=Khalid Al Siyabi:mailto:khalid@example.om" in cl and "COMMENT:I'll bring the maps" in cl,
        "the REPLY's lines as the server got them"
respondInvite(gmA, gtok, g1, iaDecline, sendReply = false)
check extraState()["extra"]["raw_sent"].len == 1, "without sendReply nothing goes"

# ---- automatic replies -------------------------------------------------------------------------

echo "automatic replies"
let a0 = getAutoReply(msA, mtok)
check not a0.enabled and not a0.scheduled and a0.start == utcT(2026, 11, 20, 4, 0) and
      a0.finish == utcT(2026, 11, 27, 13, 0) and a0.externalAudience == "all",
      "Graph: off, its last schedule read in its own zone (Arabian Standard Time)"
let a1 = AutoReply(enabled: true, scheduled: true, start: utcT(2026, 12, 1, 5, 0), finish: utcT(2026, 12, 8, 13, 0),
                   internalHtml: "<p>Away until 8 December.</p>", externalHtml: "<p>I am away; Muna can help.</p>",
                   externalAudience: "contactsOnly")
setAutoReply(msA, mtok, a1)
var patch = extraState()["extra"]["patches"].getElems[^1]["automaticRepliesSetting"]
check patch["status"].getStr == "scheduled" and patch["externalAudience"].getStr == "contactsOnly" and
      patch["scheduledStartDateTime"]["dateTime"].getStr == "2026-12-01T05:00:00" and
      patch["scheduledStartDateTime"]["timeZone"].getStr == "UTC" and
      patch["scheduledEndDateTime"]["dateTime"].getStr == "2026-12-08T13:00:00", "Graph: the PATCH (scheduled, UTC)"
let a2 = getAutoReply(msA, mtok)
check a2.enabled and a2.scheduled and a2.start == a1.start and a2.finish == a1.finish and
      a2.internalHtml == a1.internalHtml and a2.externalHtml == a1.externalHtml and
      a2.externalAudience == "contactsOnly", "Graph: read back"
setAutoReply(msA, mtok, AutoReply(enabled: true, internalHtml: "<p>x</p>", externalAudience: "none"))
patch = extraState()["extra"]["patches"].getElems[^1]["automaticRepliesSetting"]
check patch["status"].getStr == "alwaysEnabled" and patch{"scheduledStartDateTime"} == nil and
      patch["externalAudience"].getStr == "none", "Graph: on until turned off"
setAutoReply(msA, mtok, AutoReply(enabled: false, externalAudience: "bogus"))
patch = extraState()["extra"]["patches"].getElems[^1]["automaticRepliesSetting"]
check patch["status"].getStr == "disabled" and patch["externalAudience"].getStr == "all", "Graph: off"
var badSchedule = false
try: setAutoReply(msA, mtok, AutoReply(enabled: true, scheduled: true, start: 2000, finish: 1000))
except ValueError: badSchedule = true
check badSchedule, "a schedule that ends before it starts: refused here"

let v0 = getAutoReply(gmA, gtok)
check not v0.enabled and not v0.scheduled, "Gmail: off"
let v1 = AutoReply(enabled: true, scheduled: true, start: utcT(2026, 12, 1, 5, 0), finish: utcT(2026, 12, 8, 13, 0),
                   subject: "Away", internalHtml: "<p>Back on the 8th</p>", externalAudience: "contactsOnly")
setAutoReply(gmA, gtok, v1)
let vac = extraState()["vacation"]
check vac["enableAutoReply"].getBool and vac["startTime"].getStr == $int64(v1.start * 1000) and
      vac["endTime"].getStr == $int64(v1.finish * 1000) and vac["restrictToContacts"].getBool and
      not vac["restrictToDomain"].getBool and vac["responseSubject"].getStr == "Away" and
      vac["responseBodyHtml"].getStr == "<p>Back on the 8th</p>", "Gmail: the PUT (milliseconds as strings)"
let v2 = getAutoReply(gmA, gtok)
check v2.enabled and v2.scheduled and v2.start == v1.start and v2.finish == v1.finish and v2.subject == "Away" and
      v2.internalHtml == v1.internalHtml and v2.externalAudience == "contactsOnly", "Gmail: read back"
let none1 = gmailAutoReplyJson(AutoReply(enabled: true, externalAudience: "none"), "sultan@foxoman.net")
let none2 = gmailAutoReplyJson(AutoReply(enabled: true, externalAudience: "none"), "foxoman@gmail.com")
check none1["restrictToDomain"].getBool and not none1["restrictToContacts"].getBool and
      not none2["restrictToDomain"].getBool and none2["restrictToContacts"].getBool and none1{"startTime"} == nil,
      "Gmail: \"none\" is the domain (Workspace), contacts on gmail.com"
check gmailAutoReply(%*{"enableAutoReply": true, "responseBodyPlainText": "Away <back> soon\nS",
                        "startTime": 1700000000000}).internalHtml == "Away &lt;back&gt; soon<br>S",
      "Gmail: a plain-text message as HTML, a number for the time"

# ---- the assistant -----------------------------------------------------------------------------

echo "the assistant"
let thread = @[(sender: "Ahmed Al Rawahi <ahmed@contoso.com>", date: "Mon, 2 Nov 2026 09:00",
                text: "Can we meet on Tuesday at 2?\nI will bring the test images."),
               (sender: "Sultan <sultan@contoso.com>", date: "Mon, 2 Nov 2026 10:00",
                text: "Tuesday works.\n\nOn Mon, 2 Nov 2026 at 09:00, Ahmed wrote:\n> Can we meet on Tuesday at 2?\n" &
                      "> I will bring the test images.")]
let summary = summarize("sk-ant-test", "", thread, me = "Sultan Al Isaiee")
check "What is asked of you:" in summary and summary.startsWith("- "), "a summary"
var req = extraState()["extra"]["ai"].getElems[^1]
check req["headers"]["x-api-key"].getStr == "sk-ant-test" and req["headers"]["anthropic-version"].getStr == "2023-06-01" and
      req["headers"]["content-type"].getStr.startsWith("application/json"), "the headers (key, version, JSON)"
var body = req["body"]
var sent = body["messages"][0]["content"].getStr
check body["model"].getStr == "claude-haiku-5-5" and body["max_tokens"].getInt > 0 and body["messages"].len == 1 and
      body["messages"][0]["role"].getStr == "user" and "Sultan Al Isaiee" in body["system"].getStr and
      "the language most of the thread" in body["system"].getStr, "the request: default model, one user turn, the reader"
check "From: Ahmed Al Rawahi <ahmed@contoso.com>" in sent and "Tuesday works." in sent and
      sent.count("I will bring the test images.") == 1 and "wrote:" notin sent and "> " notin sent,
      "only the thread's own text (quotes left out)"
var big: seq[tuple[sender, date, text: string]]
for i in 0 ..< 30:
  big.add (sender: "Person " & $i, date: "day " & $i, text: "رسالة رقم " & $i & " " & "نص طويل ".repeat(300))
discard summarize("sk-ant-test", "claude-sonnet-5", big, language = "English")
body = extraState()["extra"]["ai"].getElems[^1]["body"]
sent = body["messages"][0]["content"].getStr
check sent.len <= maxText + 40 and "Person 29" in sent and "Person 0\n" notin sent and
      "earlier messages left out" in sent and validateUtf8(sent) < 0, "a long thread: trimmed to its newest, whole characters"
check body["model"].getStr == "claude-sonnet-5" and "Write in English" in body["system"].getStr, "the model and language asked for"
let tr = translate("sk-ant-test", "", "Hello Ahmed, Tuesday at 2 works.", "Arabic")
body = extraState()["extra"]["ai"].getElems[^1]["body"]
check tr == "مرحبا أحمد، الثلاثاء الساعة 2 مناسب." and body["system"].getStr.startsWith("Translate") and
      "into Arabic" in body["system"].getStr and body["messages"][0]["content"].getStr == "Hello Ahmed, Tuesday at 2 works.",
      "a translation"
discard translate("sk-ant-test", "", "ب".repeat(40000), "English")
check extraState()["extra"]["ai"].getElems[^1]["body"]["messages"][0]["content"].getStr.len <= maxText,
      "a long text: trimmed"
let sugg = suggestReplies("sk-ant-test", "", "From: Ahmed\n\nCan we meet on Tuesday at 2?")
check sugg == @["Yes, Tuesday at 2 works for me.", "Which room is it in?", "Sorry, I cannot make it this week."],
      "three replies"
var e401, e429 = 0
var msg401 = ""
var wait429 = 0.0
try: discard translate("sk-ant-wrong", "", "x", "Arabic")
except ApiError as e: (e401 = e.status; msg401 = e.msg)
try: discard suggestReplies("sk-ant-busy", "", "x")
except ApiError as e: (e429 = e.status; wait429 = e.retryAfter)
check e401 == 401 and "invalid x-api-key" in msg401, "a key refused: the API's message"
check e429 == 429 and wait429 == 7.0, "too many requests: when to try again"
let before = extraState()["extra"]["ai"].len
var noKey = false
try: discard summarize("", "", thread)
except ApiError as e: noKey = e.status == 401
check noKey and extraState()["extra"]["ai"].len == before, "no key: nothing goes"
check withoutQuotes("Fine.\n\n\n\nSultan\n\n________________________________\nFrom: Ahmed\nSent: Monday\nOld") ==
      "Fine.\n\nSultan" and withoutQuotes("موافق\n\nفي الاثنين، كتب أحمد كتب:\nقديم") == "موافق" and
      withoutQuotes("From: Ahmed\nSent: Monday\n\nForwarded text") == "From: Ahmed\nSent: Monday\n\nForwarded text",
      "quoted messages cut (Outlook, Arabic), a forward's own header kept"

# ---- rules -------------------------------------------------------------------------------------

echo "rules"
let mm = Msg(account: 1, fromName: "Muna Al Balushi", fromEmail: "muna@contoso.com", toList: "Sultan <sultan@contoso.com>",
             ccList: "HR Team <hr@contoso.com>", subject: "INVOICE 1047 – École fees, فاتـــورة رقم ١٠٤٧",
             snippet: "Please check the VAT line", hasAtt: true)
proc cond(f: RuleField; t = ""; account = 0): Condition = Condition(field: f, text: t, account: account)
proc rule(id: int; conds: seq[Condition]; all = true): Rule =
  Rule(id: id, name: "r" & $id, enabled: true, matchAll: all, conditions: conds)
check rule(1, @[cond(rfSubject, "invoice")]).matches(mm) and rule(1, @[cond(rfSubject, "ÉCOLE")]).matches(mm),
      "any case, in any script"
check rule(1, @[cond(rfSubject, "فاتورة")]).matches(mm) and
      rule(1, @[cond(rfSubject, "فَاتُورَة")]).matches(mm), "Arabic: tatweel and diacritics do not count"
check not rule(1, @[cond(rfFrom, "muna"), cond(rfSubject, "receipt")]).matches(mm) and
      rule(1, @[cond(rfFrom, "muna"), cond(rfSubject, "receipt")], all = false).matches(mm), "all or any"
check rule(1, @[cond(rfSubject, "receipt; 1047")]).matches(mm) and not rule(1, @[cond(rfSubject, " ; ")]).matches(mm),
      "several words: any of them"
check rule(1, @[cond(rfToCc, "hr@contoso")]).matches(mm) and rule(1, @[cond(rfFrom, "AL BALUSHI")]).matches(mm) and
      rule(1, @[cond(rfAttachment), cond(rfAccount, account = 1)]).matches(mm) and
      not rule(1, @[cond(rfAccount, account = 2)]).matches(mm), "To/Cc, the sender's name, an attachment, the account"
var withText = mm
withText.text = "The total is wrong."
check rule(1, @[cond(rfBody, "vat line")]).matches(mm) and not rule(1, @[cond(rfBody, "vat line")]).matches(withText) and
      rule(1, @[cond(rfBody, "TOTAL")]).matches(withText), "the body: its text, else its preview"
var off = rule(1, @[])
check off.matches(mm) and (off.enabled = false; not off.matches(mm)), "no conditions: every message; off: none"
var r1 = rule(1, @[cond(rfFrom, "contoso.com")])
r1.tags = @["Finance"]
r1.moveTo = "archive"
var r2 = rule(2, @[cond(rfSubject, "nothing like it")])
r2.stop = true
r2.flag = true
var r3 = rule(3, @[cond(rfAttachment)])
r3.tags = @["finance", "Urgent"]
r3.moveTo = "f-proj-retro"
r3.markRead = true
r3.stop = true
var r4 = rule(4, @[])
r4.flag = true
r4.delete = true
let res = ruleActions(@[r1, r2, r3, r4], mm)
check res.matched == @[1, 3] and res.tags == @["Finance", "Urgent"] and res.moveTo == "archive" and res.markRead and
      not res.flag and not res.delete, "in order: tags once, the first move, stop honoured (and only when matched)"
check ruleActions(@[r4, r1], mm).delete and ruleActions(@[r4, r1], mm).flag, "delete and flag"
let rs = @[r1, r3, Rule(id: 9, name: "acct", enabled: false, conditions: @[cond(rfAccount, account = 2),
                                                                           cond(rfBody, "x;y")])]
check rulesFromJson(parseJson($rs.toJson)) == rs, "kept as JSON and read back"
let loose = fromJson(%*{"name": "x", "conditions": [{"field": "nope"}, {"field": "subject", "text": "a"}]})
check loose.enabled and loose.matchAll and loose.conditions.len == 1 and loose.tags.len == 0 and not loose.stop,
      "JSON with fields missing or not known"

# ---- forwarding as an attachment -------------------------------------------------------------------

echo "forwarding as an attachment"
let raw5 = rawMessage(msA, mtok, "m5")
let p5 = parseMime(raw5)
check p5.decodedHeader("Subject") == "تجربة البريد العربي" and "مرحبا سلطان" in p5.bodies.html, "Graph: the message's $value"
let raw3 = rawMessage(gmA, gtok, "g3")
check parseMime(raw3).decodedHeader("Subject") == "عرض خاص" and "Big sale" in parseMime(raw3).bodies.html,
      "Gmail: format=raw, base64url decoded"
check attachmentName("Re: Invoice 1047 / Q3?") == "Re_ Invoice 1047 _ Q3_.eml" and attachmentName("") == "message.eml" and
      attachmentName("  ...  ") == "message.eml" and attachmentName("CON") == "_CON.eml" and
      attachmentName("a\tb\r\n  c") == "a b c.eml", "file names: what Windows refuses, spaces, nothing"
let longName = attachmentName("تقرير ".repeat(40))
check longName.endsWith(".eml") and longName.len <= 84 and validateUtf8(longName) < 0, "a long subject: cut on a character"
let fa = forwardAttachment(msA, mtok, Msg(remoteId: "m4", subject: "Invoice 1047 -- please check"), home / "outbox")
check fileExists(fa["path"].getStr) and fa["name"].getStr == "Invoice 1047 -- please check.eml" and
      fa["mime"].getStr == "message/rfc822" and fa["copy"].getBool, "saved for sending ({path, name, mime, copy})"
let rawM4 = readFile(fa["path"].getStr)
graphSend(mtok, %*{"mode": "new", "to": [{"name": "Ahmed", "email": "ahmed@contoso.com"}], "cc": [], "bcc": [],
                   "subject": "Fw: Invoice 1047", "html": "<p>See the attached message.</p>", "attachments": [fa]})
let gs = extraState()["sent"].getElems
let gatt = if gs.len > 0 and gs[^1]["attachments"].len > 0: gs[^1]["attachments"][0] else: newJObject()
check gatt{"contentType"}.getStr == "message/rfc822" and gatt{"name"}.getStr == "Invoice 1047 -- please check.eml" and
      parseMime(rawM4).decodedHeader("Subject") == "Invoice 1047 -- please check", "Graph: sent as message/rfc822"
let fraw = buildRaw(%*{"to": [{"name": "Ahmed", "email": "ahmed@contoso.com"}], "subject": "Fw: Invoice 1047",
                       "html": "<p>See the attached message.</p>", "text": "See the attached message.",
                       "attachments": [fa]}, MailAddress(name: "Sultan", email: "foxoman@gmail.example"))
gmailSend(gtok, fraw, "")
let gm = extraState()["gsent"].getElems[^1]
check "message/rfc822" in gm["parts"].getElems.mapIt(it.getStr) and
      "Invoice 1047 -- please check.eml" in gm["attachments"].getElems.mapIt(it.getStr), "Gmail: sent as message/rfc822"
let back = parseMime(fraw).attachments
check back.len == 1 and back[0].contentType == "message/rfc822" and "Invoice 1047 -- please check" in back[0].data,
      "the attached message whole"

removeDir(home)
if failures > 0:
  echo failures, " failed"
  quit 1
echo "all passed"
