## retro/bgcheck: a check registered, then run through the entry point the
## system's side calls (`retroBackgroundCheck`; on Android the job's own
## thread calls it, so here a thread the app did not make does too) -- once
## a call, `inBackgroundCheck` true only there, one check at a time, what it
## raises kept in; the desktops schedule nothing; the Android way against a
## fake Java side that answers as tools/android/RetroBackground.java does
## through RetroNative (the job asked for, 15 minutes at the least, stopped,
## refused); and notify's Android way from a check: posted, the permission
## never asked from there (the window asks).
##
## .. code-block:: sh
##   nim c -r --hints:off tests/test_bgcheck.nim

import std/[os, strutils, typedthreads]
import retro/bgcheck {.all.}
import retro/notify {.all.}
import retro/[native, uirelays/services]

var
  runs = 0                  # (the check's: one thread at a time writes them)
  sawInCheck = false
  raiseNow = false
  slow = false

proc check() {.nimcall, gcsafe.} =
  {.cast(gcsafe).}:
    inc runs
    sawInCheck = inBackgroundCheck()
    if slow: sleep(400)
    if raiseNow: raise newException(IOError, "the network is down")

var answer: cint
proc job() {.thread.} =
  {.cast(gcsafe).}: answer = retroBackgroundCheck()

when not defined(windows):
  # a thread of C's, as the job's (a Java thread) is: Nim did not make it
  {.emit: """
#include <pthread.h>
extern int uirelays_background_check(void);
static int bgForeignAnswer;
static void *bgForeignMain(void *p) { (void)p; bgForeignAnswer = uirelays_background_check(); return 0; }
static int bgOnForeignThread(void) {
  pthread_t t;
  pthread_attr_t a;
  pthread_attr_init(&a);
  pthread_attr_setstacksize(&a, 8 << 20);
  if (pthread_create(&t, &a, bgForeignMain, 0) != 0) return -1;
  pthread_join(t, 0);
  return bgForeignAnswer;
}
""".}
  proc bgOnForeignThread(): cint {.importc, nodecl.}
else:
  proc bgOnForeignThread(): cint =
    var t: Thread[void]
    createThread(t, job)
    joinThread(t)
    answer

block nothingRegistered:
  doAssert retroBackgroundCheck() == 0, "no check registered: nothing runs"
  doAssert not inBackgroundCheck()

block registeredAndRun:
  onBackgroundCheck(check)
  doAssert runs == 0, "registering runs nothing"
  doAssert retroBackgroundCheck() == 1
  doAssert runs == 1 and sawInCheck, "it ran once, knowing it is the check"
  doAssert not inBackgroundCheck(), "only while it runs"

block onAThreadOfItsOwn:
  sawInCheck = false
  doAssert bgOnForeignThread() == 1, "from a thread Nim did not make (the job's)"
  doAssert runs == 2 and sawInCheck
  var t: Thread[void]
  createThread(t, job)
  joinThread(t)
  doAssert answer == 1 and runs == 3

block oneAtATime:
  slow = true
  var t: Thread[void]
  createThread(t, job)
  sleep(150)
  doAssert not inBackgroundCheck(), "(this thread is not the check's)"
  doAssert retroBackgroundCheck() == 0, "one under way: a second does not start"
  joinThread(t)
  slow = false
  doAssert answer == 1 and runs == 4

block whatItRaisesStaysIn:
  raiseNow = true
  doAssert retroBackgroundCheck() == 1, "it ran (its error written to stderr)"
  raiseNow = false
  doAssert not inBackgroundCheck()
  doAssert retroBackgroundCheck() == 1 and runs == 6, "and the next one runs"

block desktopsScheduleNothing:
  when not defined(android):
    doAssert not scheduleBackgroundCheck(15), "apps keep running here: nothing to schedule"
    doAssert not scheduleBackgroundCheck(0)
    doAssert retroBackgroundCheck() == 1, "the check is still there to run"

# ---- Android: a fake Java side ----------------------------------------------------------------------

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
  jlog: seq[seq[string]]              # each call: its name, then its fields
  kept: seq[int]
  nextHandle = 1
  granted = false
  scheduled = "strue"                 # what RetroBackground.schedule answers

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
      of "schedule": scheduled
      of "SDK_INT": "s34"
      of "checkSelfPermission": (if granted: "s0" else: "s-1")
      of "areNotificationsEnabled": "strue"
      of "icon": "s2131034112"
      of "getPackageName": "sorg.retro.mail"
      else: "n"
    else: "eNoSuchMethodException"

proc called(member: string): seq[seq[string]] =
  ## The calls of `member`: the class (or object) and the arguments.
  for c in jlog:
    if c[0] in ["native.method", "native.static"] and c[2] == member:
      result.add @[c[1]] & c[4 .. ^1]

block androidSchedule:
  jlog.setLen(0)
  doAssert androidSchedule(15)
  doAssert called("schedule") == @[@["org.retro.RetroBackground", "a", "i15"]], $called("schedule")
  doAssert androidSchedule(5), "asked for less: 15 minutes, Android's least"
  doAssert called("schedule")[^1] == @["org.retro.RetroBackground", "a", "i15"]
  doAssert androidSchedule(60)
  doAssert called("schedule")[^1][2] == "i60"
  doAssert androidSchedule(0) and called("schedule")[^1][2] == "i0", "0 stops it"
  doAssert androidSchedule(-3) and called("schedule")[^1][2] == "i0"
  scheduled = "eIllegalArgumentException: No such service ComponentInfo{org.retro.hello/org.retro.RetroBackground}"
  doAssert not androidSchedule(15), "an APK without --background: refused"
  doAssert "No such service" in javaError()
  scheduled = "sfalse"
  doAssert not androidSchedule(15)
  scheduled = "strue"

var posted = false
proc notifying() {.nimcall, gcsafe.} =
  {.cast(gcsafe).}:
    posted = androidNotify("New mail", "Khalid: the drill plan", "", "inbox", 0)

block notifyFromACheck:
  jlog.setLen(0)
  onBackgroundCheck(notifying)
  # Android 13+, not allowed yet: the check posts nothing and asks nothing
  doAssert bgOnForeignThread() == 1
  doAssert not posted
  doAssert called("requestPermissions").len == 0, "a check has no window to ask from"
  doAssert called("newInstance").len == 0
  # the window asks, once
  doAssert not androidNotify("New mail", "Khalid", "", "inbox", 0)
  doAssert called("requestPermissions").len == 1
  # allowed: the check posts it (the Java side puts the app's Context for "a")
  granted = true
  doAssert bgOnForeignThread() == 1
  doAssert posted
  let n = called("notify")
  doAssert n.len == 1 and n[0][1] == "sinbox", $n
  doAssert called("getActivity").len == 1 and called("getActivity")[0][1] == "a",
           "the tap opens the app, from the app's Context"
  doAssert kept.len == 0, "objects left kept: " & $kept

echo "bgcheck: all passed"
