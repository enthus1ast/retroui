# Building Retro apps: desktop, Android and iOS, step by step

Retro builds its own Android packages: `retroapk` compiles the app and
writes and signs the APK itself. You do **not** need the Android SDK,
Android Studio, Java, Gradle, OpenSSL or apksigner -- and not the Android
NDK either: `retroapk` carries Android's headers and libraries inside
itself (a 1.2 MB sysroot) and builds with any **clang that has lld**, or
with **zig**. Only when neither is there does it fetch the NDK (about
700 MB) once, as a fallback.

iOS apps are built on a Mac with Xcode by `retroios`: no Xcode project.

`retroapk`, `retroios` and `retrokit` come with the package: after
`nimble install retroui` they are on your PATH (in `~/.nimble/bin`).
`retrokit doctor` checks what a machine has and says what is missing.

---

## Desktop: Windows, macOS, Linux and BSD

A desktop app needs Nim and a C compiler, nothing more: the kit links only
what every system has (Windows' own DLLs, Cocoa, libc; X11 is loaded when
the app starts).

```sh
nim c -r -d:release -d:useMalloc app.nim     # build and run on this computer (or: retrokit run app.nim)
retrokit small app.nim                       # the smallest: --opt:size, LTO, stripped
```

**Windows, on Windows:** the Nim zip for Windows comes with MinGW;
`nim c -d:release -d:useMalloc --app:gui app.nim` makes `app.exe`
(`--app:gui`: no console window).

**Windows, from Linux or macOS:** install MinGW-w64 (`apt install
mingw-w64`, `dnf install mingw64-gcc`, `brew install mingw-w64`), then

```sh
nim c -d:release -d:useMalloc -d:mingw --cpu:amd64 --app:gui app.nim
```

One `.exe`, no DLLs beside it. Wine runs it for a first look
(`wine app.exe`). To give it an icon and a version, in a clone of the
repository:

```sh
nim c -r tools/winicon.nim icon.png "My App" 1.0 build/myapp-res.o
nim c -d:release -d:useMalloc -d:mingw --cpu:amd64 --app:gui --passL:build/myapp-res.o app.nim
```

**macOS:** `xcode-select --install` gives the compiler. `sh
tools/macapp.sh program "My App" 1.0 icon.png com.me.myapp out.zip` (in a
clone) makes the `.app` with its icon and zips it.

**Linux:** gcc or clang; no `-dev` packages (libX11 is loaded when the
app starts). `nim c -r tools/appimage.nim program "My App" 1.0
icon.png MyApp-x86_64.AppImage` (in a clone) packs it as an AppImage, one
file with its icon and menu entry.

**BSD:** as on Linux, with the system's clang and X11 from packages.

**The examples** are built only when you ask, one at a time:
`RETRO_APP=photo nimble exe` (Windows, from Linux or macOS),
`RETRO_APP=photo nimble appimage`, `RETRO_APP=photo nimble macapp` (on a
Mac), `RETRO_APP=photo nimble appapk`; the apps are listed in
`retroui.nimble` (`RetroApps`).

---

## Android

What each system needs (Nim builds `retroapk` itself with its usual C
compiler; clang + lld or zig compile the app for Android):

| System | Nim | Android compiler (no NDK) |
|---|---|---|
| Windows 10/11 | the Nim zip (with MinGW) | the LLVM installer, or zig |
| macOS | `brew install nim` | `brew install llvm lld`, or `brew install zig` |
| Linux | choosenim or the distribution's `nim` | `clang` and `lld` packages, or zig |
| FreeBSD, OpenBSD, NetBSD | `nim` from packages | clang and lld (base system or packages), or zig |
| Termux (on the phone) | `pkg install nim` | `pkg install clang ndk-sysroot` |

### Windows 10 or 11

1. **Nim.** Download the Nim zip for Windows (x86_64) from
   <https://nim-lang.org/install_windows.html>, unzip it to `C:\nim`, run
   `C:\nim\finish.exe`, and answer yes to adding Nim to the PATH and to
   downloading MinGW (the C compiler). Open a new terminal (PowerShell or
   cmd) and check: `nim -v`, `gcc -v`.
2. **The Android compiler**, one of:
   - **LLVM:** `winget install LLVM.LLVM`, or the installer
     (`LLVM-<version>-win64.exe`) from
     <https://github.com/llvm/llvm-project/releases>. It goes into
     `C:\Program Files\LLVM` with `clang.exe` and `ld.lld.exe`;
     `retroapk` looks there by itself, on the PATH or not.
   - **Zig:** `winget install zig.zig`, or the zip from
     <https://ziglang.org/download/> with its folder added to the PATH, or
     `pip install ziglang`.
3. **Retro.** `nimble install retroui` (or, from the source folder,
   `nimble install` there).
4. **Build.** In your app's folder:

   ```bat
   retroapk app.nim --name:"My App" --id:com.me.myapp
   ```

   The first build unpacks the sysroot into
   `%USERPROFILE%\.retro\android-sysroot` (once, about 8 MB), then makes
   `app.apk` next to `app.nim`.
5. **Put it on the phone:** see [Installing on the phone](#installing-on-the-phone).

### macOS (Apple Silicon or Intel)

1. **The C compiler for Nim:** `xcode-select --install` (the Command Line
   Tools; the whole Xcode is only needed for iOS).
2. **Nim:** `brew install nim` (Homebrew: <https://brew.sh>), or
   `curl https://nim-lang.org/choosenim/init.sh -sSf | sh`.
3. **The Android compiler:** `brew install llvm lld` -- Apple's own clang
   has no lld, so `retroapk` takes Homebrew's from
   `/opt/homebrew/opt/llvm/bin` (`/usr/local/opt/llvm/bin` on Intel); nothing
   to add to the PATH. Or `brew install zig`.
4. **Retro:** `nimble install retroui`.
5. **Build:**

   ```sh
   retroapk app.nim --name:"My App" --id:com.me.myapp
   ```

### Linux

1. **The C compilers:** Debian/Ubuntu `sudo apt install gcc clang lld`,
   Fedora `sudo dnf install gcc clang lld`, Arch `sudo pacman -S gcc clang lld`
   (or zig instead of clang and lld).
2. **Nim:** `curl https://nim-lang.org/choosenim/init.sh -sSf | sh` (or
   your distribution's `nim` package if it is 2.2 or newer).
3. **Retro:** `nimble install retroui`.
4. **Build:** `retroapk app.nim --name:"My App" --id:com.me.myapp`.

### FreeBSD, OpenBSD, NetBSD

Google makes the NDK for Windows, macOS and Linux only; with the sysroot
in `retroapk` a BSD needs none:

1. **Nim:** `pkg install nim` (FreeBSD), `pkg_add nim` (OpenBSD),
   `pkgin install nim` (NetBSD).
2. **The Android compiler:** a clang and an `ld.lld`: FreeBSD's base
   system has both (or `pkg install llvm`); on OpenBSD and NetBSD, clang
   and lld from packages or ports. Or zig from packages.
3. **Retro and the build** as on Linux.

`retroapk` tries each clang it finds with a small Android library first
and takes the first that works (`retrokit doctor` shows which one); a
clang built without the AArch64 or X86 targets is passed over.

### On the phone itself (Termux)

```sh
pkg install nim clang ndk-sysroot openssl-tool git
nimble install retroui
retroapk app.nim --name:"My App" --install     # the installer asks to confirm
```

Termux's clang builds for the phone's own ABI; with `pkg install lld` the
sysroot in `retroapk` builds the others too (`--abi:x86_64`...).

### A desktop app in Termux, on Termux:X11

The same app also runs in Termux itself, in a window on Termux:X11 (the
Termux:X11 app, from F-Droid or its GitHub releases), with no APK:

```sh
pkg install x11-repo
pkg install termux-x11-nightly libx11 nim clang git
nimble install retroui
termux-x11 :0 &                 # then open the Termux:X11 app
export DISPLAY=:0
nim c -r -d:release -d:useMalloc app.nim
```

In Termux, Nim builds for Android, so the kit decides by what is built:
an APK's library (`--app:lib`, what `retroapk` makes) gets Android's own
driver; a program run from the shell gets the X11 driver, its files and
services as on Linux, and draws on the CPU. With no window manager on
Termux:X11 the window has no title bar and sits at the top left;
`RETRO_SIZE=1200x800` makes it bigger, `RETRO_TOUCH=1` finger-sized.

### How the compiler is chosen

1. `--cc:PATH` or `RETRO_ANDROID_CC` (a compiler of your own);
2. Termux's clang, in Termux;
3. an NDK that is there: `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT`,
   `ANDROID_HOME/ndk/*`, or one fetched before into `~/.retro/ndk`;
4. **no NDK:** a clang with lld -- Homebrew's llvm (macOS), the PATH's
   clang, `C:\Program Files\LLVM\bin` (Windows), `clang-18` and the like --,
   then zig (on the PATH, or pip's `ziglang`), each with the sysroot;
5. none of these: the NDK is fetched into `~/.retro/ndk` (Windows' own
   `curl` and `tar`, the .dmg with `hdiutil` on a Mac, `unzip` on Linux).

`--toolchain:clang`, `--toolchain:zig` or `--toolchain:ndk` (or
`RETRO_ANDROID_TOOLCHAIN`) picks one. The sysroot has arm64-v8a (phones
and tablets) and x86_64 (the emulator, Chromebooks) from API 24 (Android 7,
the kit's lowest); the 32-bit ABIs (`armeabi-v7a`, `x86`) and `--min-sdk`
below 24 use the NDK. Android before 10 has no native thread-local storage,
so below `--min-sdk:29` the libraries use emulated TLS; zig cannot make it in
an LTO link, so with zig `-d:lto` is left out there (a somewhat bigger
library).

The sysroot: bionic's headers and the kernel's uapi headers, the NDK's
`android/*.h`, `log.h`, `jni.h`; for each ABI the crt objects, stubs of
`libc.so`, `libm.so`, `libdl.so`, `liblog.so` and `libandroid.so` (made from
Android's own symbol lists, as the NDK's are; the phone has the real
ones), and LLVM's compiler-rt builtins. `libEGL` and `libGLESv2` are not
linked: the kit opens them at run time. It is unpacked once into
`~/.retro/android-sysroot/api24-<checksum>` (`RETRO_SYSROOT_DIR` puts it, or
a sysroot of your own, elsewhere). `tools/android/mksysroot.sh` makes it
again from the AOSP and LLVM sources at pinned revisions (same sources and
same clang, same archive). Its `NOTICE` and `licenses/` say where each part
comes from: bionic (BSD and Apache-2.0), frameworks/native and
frameworks/base, liblog and libnativehelper (Apache-2.0), compiler-rt
(Apache-2.0 WITH LLVM-exception).

### The options you will use

```sh
retroapk app.nim --name:"My App" --id:com.me.myapp \
  --version:1.2 --code:3 \             # the version shown, and its number (higher for each update)
  --icon:icon.png \                    # 512x512 PNG (else a drawn 3.1 window)
  --abi:arm64-v8a,x86_64 \            # phones (arm64 is the default) and the emulator
  --permission:INTERNET \              # one --permission for each
  --orientation:landscape \            # or portrait (default: any)
  -o:build/MyApp.apk
```

`retroapk --help` lists every option. The examples have tasks:
`nimble galleryapk`, `nimble photoapk`, `nimble apk` (Retro Files),
`nimble mailapk`, `nimble boardapk`, `nimble apks` (all), into `build/`.
`nimble ndk` fetches the NDK now, for machines that will use it.

### Signing

The first build makes a signing key in `~/.retro/android`
(`%USERPROFILE%\.retro\android` on Windows). **Keep that folder** (copy it
somewhere safe): Android installs an update only when it is signed with
the same key as the app on the phone. For a key of your own:
`--key:key.pem --cert:cert.der`; `RETRO_KEYS=folder` keeps the debug key
elsewhere.

### Installing on the phone

- **Without a cable:** copy the .apk to the phone (a USB cable as a
  drive, a cloud folder, an email to yourself), tap it in the phone's
  Files app and allow "Install unknown apps" for that app when asked.
- **With adb** (Android's command-line tool -- "SDK Platform-Tools", a
  small zip of its own, not the SDK:
  <https://developer.android.com/tools/releases/platform-tools>; unzip it
  and add the folder to the PATH): turn on USB debugging on the phone
  (Settings > About phone > tap Build number 7 times; then Developer
  options > USB debugging), plug it in, and

  ```sh
  retroapk app.nim --name:"My App" --run        # builds, installs, starts
  adb logcat -s retro                           # the app's echo output
  ```

### If something goes wrong

- **"... cannot build for x86_64":** that clang lacks the target or
  its lld; `retroapk` goes on to the next clang, then zig. `--verbose`
  shows every command, `--toolchain:zig` skips clang.
- **A damaged sysroot:** delete `~/.retro/android-sysroot`; the next
  build unpacks it again.
- **The NDK download stops half way:** delete `~/.retro/ndk` and build
  again (or `nimble ndk`). Behind a proxy, set `HTTPS_PROXY`; with no
  internet, download the NDK zip yourself and set `RETRO_NDK_URL=file:///path/to/android-ndk-r27c-linux.zip`.
- **You already have an NDK:** set `ANDROID_NDK_HOME` to it (any r23 or
  newer); it is used first and nothing is downloaded.
- **"App not installed" on the phone:** the app is already there signed
  with another key (uninstall it first), or the `--code` is lower than the
  installed one's.

---

## iOS (on a Mac)

### Once

1. **Xcode** from the App Store. Open it once, let it install its
   components, and accept the licence (`sudo xcodebuild -license accept`).
   In Xcode > Settings > Components (Platforms), install the iOS
   Simulator runtime.
2. **Nim:** `brew install nim`.
3. **Retro:** `nimble install retroui` (gives `retroios`).

### In the Simulator

```sh
open -a Simulator                               # starts an iPhone in the Simulator
retroios app.nim --simulator --run              # builds, installs and starts it there
```

The app is built into `build/ios-app/App.app` beside `app.nim` (`build/ios-<file>/<Name>.app`; `-o:` puts it elsewhere).

### On your iPhone or iPad

1. **An Apple ID in Xcode:** Xcode > Settings > Accounts > + > Apple ID. A
   free account can put apps on your own devices (they expire after 7
   days); a paid Apple Developer account (99 USD a year) is needed for a
   year's signing, TestFlight and the App Store.
2. **Developer Mode on the device:** plug it in, trust the Mac, then on
   the device Settings > Privacy & Security > Developer Mode > on (it
   restarts).
3. **A provisioning profile for your app's id.** The simplest way: in
   Xcode, File > New > Project > iOS App, give it the same bundle id you
   will use (`com.me.myapp`), choose your team under Signing &
   Capabilities, pick your device and press Run once. Xcode makes the
   profile; it is in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`
   (older Xcode: `~/Library/MobileDevice/Provisioning Profiles/`). Copy it
   next to your app as `dev.mobileprovision`.
4. **Your signing identity's name:**

   ```sh
   security find-identity -v -p codesigning
   # 1) ABCD... "Apple Development: Sultan Al Isaiee (TEAMID1234)"
   ```

5. **Your device's name:** `xcrun devicectl list devices`.
6. **Build, sign, install and start:**

   ```sh
   retroios app.nim --name:"My App" --id:com.me.myapp \
     --sign:"Apple Development: Sultan Al Isaiee (TEAMID1234)" \
     --profile:dev.mobileprovision --device:"My iPhone" --run
   ```

   The first time, the device may say the developer is not trusted:
   Settings > General > VPN & Device Management > your Apple ID > Trust.

### For TestFlight or the App Store

Sign with an "Apple Distribution" identity and an App Store
provisioning profile (made at <https://developer.apple.com/account>),
then pack the bundle as an .ipa and send it with Apple's Transporter app:

```sh
retroios app.nim --name:"My App" --id:com.me.myapp --version:1.0 --code:1 \
  --sign:"Apple Distribution: Sultan Al Isaiee (TEAMID1234)" --profile:appstore.mobileprovision
mkdir -p Payload && cp -R build/ios-app/MyApp.app Payload/
zip -qr MyApp.ipa Payload
```

(This last route follows Apple's documented .ipa layout; it is not yet
among the verified steps below.)

### Options

`retroios --help`: `--name`, `--id`, `--version`, `--code`, `--icon`
(1024x1024 PNG), `--min-ios` (default 14.0), `--simulator`, `--sign`,
`--profile`, `--device`, `--run`, `--nim:FLAG`, `-o:Dir.app`, `--verbose`.
Without a Mac, `retroios app.nim --sdk:iPhoneOS.sdk` (an iOS SDK copied
from a Mac, and LLVM's `lld`) links an unsigned bundle -- to check that
the app compiles for iOS.

---

### Verified

APKs: built without the NDK on Linux for arm64-v8a and x86_64, with
clang 18 + lld and with zig 0.17; each `libmain.so` checked
(its machine, the libraries it needs, no symbol outside Android's system
libraries, 16 KB page alignment) and each APK verified with `apksigner` and
`aapt`. Built with the NDK's compiler before, and run on an Android tablet.
Windows and macOS find their compilers in the places above and follow the
same steps (a `.cmd` wrapper on Windows); the NDK download for them follows
Google's packages (zip, .dmg). iOS: compiled and linked against the iOS
SDK; the Simulator and device steps are Apple's standard ones.
