## The system's own browser engine for `webView` (in `htmlview`): what the
## app sees of it is the same everywhere -- a page placed over the widget,
## its address, title and loading, Back and Forward, JavaScript run in it,
## messages from the page (`retro.post(text)` in its scripts) and to it (a
## `retro` event on its `window`), the addresses it may open, its zoom.
##
## - Android, in an APK: the phone's WebView (`tools/android/RetroWeb.java`,
##   reached through `systemCall`).
## - Linux and BSD (the X11 driver, Termux:X11 too): WebKitGTK
##   (`libwebkit2gtk-4.1`), loaded when the first page is shown -- nothing to
##   link; without it there is no system engine. It runs in a thread of its
##   own (GTK's), its window put inside the app's.
## - Windows (the WinAPI driver): WebView2, the Edge engine Windows 10 and 11
##   have, found where Windows keeps it (WebView2Loader.dll is used when it is
##   beside the program, and needed by nothing).
## - macOS and iOS (the Cocoa and UIKit drivers): WKWebView (WebKit, part of
##   the system), reached through the Objective-C runtime.
##
## Other drivers (SDL, GTK 4, Siwin) have none: `webView` shows pages the
## kit's way there.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[strutils, uri, os]
import uirelays/target
import uirelays/coords

type
  WebNav* = enum
    ## What `webNativeNav` asks of a page.
    wnBack, wnForward, wnReload, wnStop
  WebNativeState* = object
    ## A page as the system's engine has it now.
    url*, title*: string
    progress*: int              ## 0..100
    canBack*, canForward*: bool
    backOut*: bool              ## (Android) Back with no page before
    notes*: seq[string]         ## what the page posted since the last look
                                ## (`retro.post`; "\1id\1json": a script's answer)
    blocked*: seq[string]       ## addresses it was kept from (not allowed)
    focused*: bool              ## it has the keyboard

const
  NoSystemDriver = defined(sdl2) or defined(sdl3) or defined(gtk4) or
    defined(features.uirelays.siwin) or defined(features.uirelays.figDrawSiwin) or
    defined(figDrawSiwin) or defined(features.uirelays.figDrawWindy) or
    defined(figDrawWindy) or defined(features.uirelays.figDrawSiwinGpu)
  WebGtk = not androidApp and not NoSystemDriver and
    (defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd) or
     defined(dragonfly) or defined(android))
  WebWin = defined(windows) and not NoSystemDriver
  WebWk = (defined(macosx) or defined(ios)) and not NoSystemDriver

proc allowedBy*(hosts: openArray[string]; url: string): bool =
  ## Whether `url` may be opened in a page that is allowed `hosts` (none:
  ## anything): its host is one of them or under one ("nim-lang.org" lets
  ## "forum.nim-lang.org" in). Local pages, `about:`, `data:` and `blob:` always
  ## may.
  if hosts.len == 0: return true
  let l = url.toLowerAscii
  if l.startsWith("file:") or l.startsWith("about:") or l.startsWith("data:") or
     l.startsWith("blob:") or l.startsWith("javascript:"): return true
  let host = try: parseUri(url).hostname.toLowerAscii except CatchableError: ""
  if host.len == 0: return true
  for h in hosts:
    let x = h.toLowerAscii.strip
    if x.len > 0 and (host == x or host.endsWith("." & x)): return true
  false

proc fileUrl*(path: string): string =
  ## A local path as a `file://` address.
  var p = path.replace('\\', '/')
  if p.len >= 2 and p[1] == ':': p = "/" & p          # C:/... -> /C:/...
  result = "file://"
  for c in p:
    if c in {'a'..'z', 'A'..'Z', '0'..'9', '/', '-', '_', '.', '~', ':'}: result.add c
    else: result.add '%' & toHex(ord(c), 2)

proc webToolsWanted(): bool {.used.} =
  ## The engine's developer tools (Inspect Element...) are offered: only with
  ## $RETRO_WEB_TOOLS=1, while making an app.
  getEnv("RETRO_WEB_TOOLS") == "1"

proc shimFor(post: string): string {.used.} =
  ## The script put in every page before its own: `retro.post(text)`.
  "(function(){if(window.retro&&window.retro.post)return;" &
    "window.retro={post:function(m){" & post & "(String(m));}};})();"

# ---- per system -------------------------------------------------------------------------------
#
# (an Android app's WebView is reached through `systemCall` by `htmlview`
#  itself: "web.show", "web.info"... -- the protocol tests fake)

when androidApp:
  proc webNativeAvailable*(): bool = false
    ## Whether the system has a browser engine the kit can show pages in.
  proc webNativeShow*(key: string; r: Rect; url: string; zoom: float) = discard
  proc webNativeHide*(key: string) = discard
  proc webNativeClose*(key: string) = discard
  proc webNativeNav*(key: string; what: WebNav) = discard
  proc webNativeRun*(key: string; js: string) = discard
  proc webNativeAllow*(key: string; hosts: seq[string]) = discard
  proc webNativeTake*(key: string): WebNativeState = discard

# ---- Linux and BSD: WebKitGTK in a thread of its own --------------------------------------------

elif WebGtk:
  include webnative_gtk

# ---- Windows: WebView2 ----------------------------------------------------------------------------

elif WebWin:
  include webnative_win

# ---- macOS and iOS: WKWebView ---------------------------------------------------------------------

elif WebWk:
  include webnative_wk

else:
  proc webNativeAvailable*(): bool = false
  proc webNativeShow*(key: string; r: Rect; url: string; zoom: float) = discard
  proc webNativeHide*(key: string) = discard
  proc webNativeClose*(key: string) = discard
  proc webNativeNav*(key: string; what: WebNav) = discard
  proc webNativeRun*(key: string; js: string) = discard
  proc webNativeAllow*(key: string; hosts: seq[string]) = discard
  proc webNativeTake*(key: string): WebNativeState = discard
