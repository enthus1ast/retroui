# Working on Retro Nim UI

Rules for anyone changing this repository -- people and AI coding agents
alike. To build an app *with* the kit, read `skills/retroui/SKILL.md`.

## The project

- Retro Nim UI (`retroui`), a Windows 3.1 style immediate-mode UI toolkit
  for Nim, by Sultan Al Isaiee (@foxoman) -- www.foxoman.net --
  sultan@foxoman.net. Repository: https://github.com/foxoman/retroui
- `src/retroui.nim` and `src/retroui/` -- the toolkit;
  `src/retroui/uirelays/` -- the platform layer (a fork of nim-lang's
  uirelays, kept generic: see below); `src/retroapk.nim`, `retroios.nim`,
  `retrokit.nim` -- the command-line tools.
- `examples/` -- the example apps (Gallery, Retro Photo, Retro Files,
  Retro Mail, Retro Communicator, Retro Board, HR Book, Notepad, Ledger,
  Charts...). They are
  built only when asked, one at a time (`nimble photo`, `nimble photoexe`,
  `RETRO_APP=photo nimble exe`...), never by `nimble install`. GitHub's
  Release workflow (`.github/workflows/release.yml`, on a `v...` tag or by
  hand) builds Gallery, Files, Photo, Board and Mail for Linux, Windows,
  Android and macOS onto the release.
- `tests/` -- headless tests on a fake screen driver (`tests/harness.nim`).
- `docs/controls.md` -- every control with pictures, made by `tools/shots.nim`.
- Screen readers: `src/retroui/uirelays/access.nim` (the tree, its roles,
  states, requests: generic), `core.nim` builds it while one listens
  (`accessNode`, `accessBegin`/`accessEnd`, `accessPress`, `accessSet`);
  the drivers hand it on: `uirelays/atspi.nim` over `uirelays/dbus.nim`
  (X11), `drivers/winuia.nim` (Windows, included by the WinAPI driver),
  `cocoa_backend.m`, `uikit_backend.m`, `tools/android/RetroAccess.java`.
  A new control adds itself (`accessNode` after its `interact`; parts --
  items, tabs -- with `accessSubId`) and takes a press from `accessPress`.
- Input methods: `TextEditingEvent` (`composing`), `ui.composing`, drawn by
  `editAt`; X11 XIM callbacks, Windows IMM, macOS marked text, GTK 4
  preedit, Android `tools/android/RetroInput.java`.
- The Java of the APKs (`tools/android/*.java`) is compiled into
  `src/retroui/androiddex.nim` by `sh tools/android/build_dex.sh` (javac,
  an android.jar of API 23, dx or dalvik-exchange): run it after changing
  one, and use only calls API 23 has (the APKs start on Android 7).
- `tools/compare/` -- Hello in egui, iced and Slint, and `compare.sh`
  measuring them and the kit the same way (memory, size, CPU).
- `docs/syntax.md` -- the study of the syntax: every form as a whole program
  with a picture of what it draws. The programs are `tools/syntaxshots/ex/`
  (the page's code plus `#>` script lines and `mark` lines it leaves out);
  `sh tools/syntaxshots/make.sh` remakes `docs/syntax/*.png` and checks the
  page's code is the programs' (needs Pillow). `docs/syntax/frame-loop.png`
  is drawn by hand.

## Before you change anything

1. Read `README.md`, the top of `CHANGELOG.md` and the module you touch
   (every exported symbol has a `##` doc comment).
2. Build what you touch and run its tests:
   `nim c -r --hints:off tests/test_<name>.nim`; the whole suite is
   `nimble test` (all must pass before a commit). A change to the
   Android driver (`uirelays/drivers/android*`): `sh
   tests/android_mock/run.sh` too (the driver on a fake Android; a new
   NDK function needs its fake in `tests/android_mock/mock_android.c`).
3. Before a release, run the tests under the sanitizers too (the command
   is at the top of `tests/lsan.supp`); a leak found goes into
   `test_hardening`.

## Rules

- **Nim 2.2 leaks** in three shapes, worked around in the kit: `return x`
  after `result` was already set (keep the value in a local until it is
  returned); `x = y` after `x` was filled in a loop or a branch
  (`swap`, or give `x` a value where it is declared); a call that may raise
  whose result goes into a field (into a `let` first, then the field).

- **Voice:** comments, docs and messages in the repository speak as the
  developer, Sultan Al Isaiee, to his users and developers: plain, short
  sentences. Never as an assistant or a test machine ("tested here", "on
  this machine", "I could not").
- **Doc comments:** every exported proc, template, macro, type, field and
  constant has one (what it does, parameters and defaults, what it
  returns). `nimble docs` must build without warnings. A new control goes
  into `docs/controls.md` (`tools/controlscheck.py` fails otherwise) with
  its example in `tools/shots.nim`.
- **Keep these up to date with every change** to the API, the build or
  the behaviour: `skills/retroui/SKILL.md` (how to build apps with the
  kit), this file, `README.md`, `CHANGELOG.md` (the top section),
  `BUILDING.md` (builds), `docs/controls.md` (controls), `docs/syntax.md`
  (when the syntax or what a form draws changes: run
  `sh tools/syntaxshots/make.sh`), `llms.txt`.
- **Looks:** the Windows 3.1 look and FreeSans drawn in gray (its heights
  on whole pixels, its strokes as the font has them; "Sharp" text is an
  option). Check a change by looking at a screenshot.
- **The same everywhere:** behaviour and looks must match on Windows,
  macOS, Linux/BSD and Android; platform conventions (Cmd on macOS) go in
  the drivers, not in the app code. A frame relay added to `FrameRelays`
  (as `setResizable`) is filled in every desktop driver that can, and the
  ones that cannot are named in its doc comment.
- **Android: an app or a program in Termux.** Nim builds both with
  `--os:android`. `androidApp` (`uirelays/target`) is an APK (the
  activity, JNI, the app's folders); `androidShell` is a program run in
  Termux (X11 on Termux:X11, files and services as on Linux). Use
  `androidApp` for anything of the activity's; `defined(android)` only
  for what Android's libc and system are either way (bionic's malloc,
  /system/fonts, /storage).
- **A driver's C and Objective-C build on their own**: the uirelays tests
  compile `cocoa_backend.m` (and others) as plain C, without Nim. What such
  a file calls in Nim gets a weak stand-in there
  (`__attribute__((weak)) void cocoa_accessListen(void) {}`); the Nim
  side's `exportc` proc takes its place when the program is linked.
- **uirelays** (`src/retroui/uirelays`): generic, in upstream's style, no
  Retro names or app logic (the X11 driver's `x11EventHook`, `x11Display`,
  `x11Window`, `x11Wake` are generic too: what any program that manages
  windows needs; Retro Desktop is one). It is the same code as the `uirelays` branch:
  after changing it, `sh tools/uirelays.sh push "message"`; `sh
  tools/uirelays.sh merge` brings upstream's new commits (nim-lang/uirelays
  master) into the branch, then `pull`. It stays inside the package (no
  separate nimble dependency) until upstream has the branch's work.
- **A frame that changes nothing takes no memory**: no string, seq or
  closure made in the drawing of a control (buffers kept from frame to
  frame, `idOfLabel` instead of `idOf(a & b)`, templates instead of nested
  procs, `swap` a widget's state out and back). `tests/bench.nim` with
  `-d:nimAllocStats` counts them (0 in the gallery's frames).
- **No dependencies to install:** link only what every system has
  (libc; Windows' system DLLs); load anything else at run time and work
  without it.
- **Credits:** the About boxes credit only Sultan Al Isaiee
  (`RetroCredit`). Commits are authored by him; an AI that helped is
  named in a `Co-Authored-By:` line.
- **Never commit** private fonts (Helvetica World), secrets (Retro Mail's
  Google/Microsoft ids: from the environment at build time), build
  outputs, or real personal data in examples and tests (sample data is
  made up: names, and numbers like +968 0000 0123).
- **Commits and pushes:** only the developer pushes.
