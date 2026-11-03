## Work an app does while it is closed: a check the system runs every so
## often with no window -- new mail fetched and told in a notification
## (`retro/notify`), a feed read, a reminder raised.
##
## - **Android:** a periodic job of the system's JobScheduler, run when
##   there is a network and kept across reboots; every 15 minutes at the
##   shortest (Android may wait longer: a low battery, an app seldom
##   opened). When the app is closed the system starts its process for the
##   check: the app's start runs up to `onBackgroundCheck`, without a
##   window, and the check runs; the window opened after that carries on
##   from there. With the app open the check runs beside it, on a thread of
##   its own. The APK needs `retroapk --background`.
## - **Desktops:** nothing is scheduled -- an app runs there until it is
##   quit, and its own timers do the work. `onBackgroundCheck` keeps the
##   proc (`retroBackgroundCheck` runs it, as the tests do).
## - **iOS:** not yet (nothing is scheduled).
##
## The check runs with no window: no drawing, no dialogs, no toasts --
## files, the network, the database, `notify` and `setBadge`. Settings the
## app keeps are read from its files there (the window's variables are not
## set in a process started for a check).
##
## .. code-block:: nim
##   import retro, retro/[notify, bgcheck]
##
##   proc check() {.nimcall, gcsafe.} =
##     let n = fetchNewMail()            # (the app's own)
##     if n > 0: notify("New mail", $n & " new messages", tag = "inbox")
##
##   onBackgroundCheck(check)            # at the start, before the window
##   scheduleBackgroundCheck(15)         # every 15 minutes; 0 stops it
##   app "Mail", 800, 600:
##     label "..."

import std/atomics
import native

type BackgroundCheck* = proc () {.nimcall, gcsafe.}
  ## What the check does (on a thread of its own, with no window).

var
  theCheck: BackgroundCheck          # set at the start; read by the check's thread
  running: Atomic[bool]              # a check is under way (one at a time)
  inCheck {.threadvar.}: bool        # this thread runs the check

when defined(android):
  # android_glue.c's; weak: a program without the Android driver (in
  # Termux) has none, and nothing then waits
  proc bgRegistered() {.importc: "uirelays_bg_registered", cdecl,
                        codegenDecl: "$1 $2$3 __attribute__((weak))".}
  proc bgHeadless(): cint {.importc: "uirelays_bg_headless", cdecl,
                            codegenDecl: "$1 $2$3 __attribute__((weak))".}

  # RetroBackground.nativeCheck (tools/android/RetroBackground.java): the
  # job's native method, passed on to the driver (which knows no class name).
  # Pointers for JNI's types: the same calls, no jni.h needed (Termux).
  {.emit: """
extern int uirelays_bg_native_check(void *env, void *cls, void *dataDir) __attribute__((weak));
__attribute__((visibility("default")))
int Java_org_retro_RetroBackground_nativeCheck(void *env, void *cls, void *dataDir) {
  return uirelays_bg_native_check ? uirelays_bg_native_check(env, cls, dataDir) : 0;
}
""".}

proc onBackgroundCheck*(check: BackgroundCheck) =
  ## Registers what the check does. Call it at the app's start, every
  ## start, before its window opens (before `app`) and before anything
  ## slow: on Android a process started for a check runs the app's start
  ## only this far.
  theCheck = check
  when defined(android):
    if cast[pointer](bgRegistered) != nil: bgRegistered()

proc androidSchedule(minutes: int): bool =
  ## (tools/android/RetroBackground.java, through retro/native)
  let m = if minutes <= 0: 0 else: max(15, minutes)
  javaStatic("org.retro.RetroBackground", "schedule", jactivity(), m) == "true"

proc scheduleBackgroundCheck*(minutes: int): bool {.discardable.} =
  ## Has the system run the check every `minutes` (Android: 15 at the
  ## least), when there is a network, also after a reboot; 0 stops it.
  ## Asked again for the same period it keeps the time already counted, so
  ## the app calls it at every start. False where nothing is scheduled:
  ## the desktops (apps keep running there), iOS, an APK built without
  ## `retroapk --background` (`javaError` says why).
  when defined(android):
    if not javaAvailable(): return false
    androidSchedule(minutes)
  else:
    false

proc inBackgroundCheck*(): bool =
  ## True on the thread that runs the check -- there is no window to draw
  ## in, no dialog to show -- and, on Android, while the app's start runs
  ## for one with no window (the process was started for a check).
  result = inCheck
  when defined(android):
    if not result and cast[pointer](bgHeadless) != nil: result = bgHeadless() != 0

proc retroBackgroundCheck*(): cint {.exportc: "uirelays_background_check", dynlib, cdecl, gcsafe.} =
  ## Runs the registered check once, on the calling thread: the system's
  ## side calls it (android_glue.c, on the job's thread, the app's start
  ## run first). 1 when it ran, 0 when there is none or one is under way.
  ## What it raises is written to stderr (Android's log), not passed on.
  var check: BackgroundCheck
  {.cast(gcsafe).}: check = theCheck
  if check == nil or running.exchange(true): return 0
  inCheck = true
  try:
    check()
  except CatchableError, Defect:
    try: stderr.writeLine "background check: " & getCurrentExceptionMsg()
    except IOError: discard
  inCheck = false
  running.store(false)
  1
