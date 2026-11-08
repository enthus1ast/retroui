## (included by webnative) macOS and iOS: WKWebView, WebKit as the system has
## it, loaded when the first page is shown and reached through the
## Objective-C runtime (nothing to link). Each page is a WKWebView put in the
## app's window over the widget; a class of the kit's made at run time hears
## what the page posts (`retro.post`) and decides where it may go.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[dynlib, os]
import native

type
  CGRect {.bycopy.} = object
    x, y, w, h: float64
  WkView = object
    key: string
    view: ObjcId
    url: string
    zoom: float
    hosts: seq[string]
    st: WebNativeState
    shown: bool

var
  wkState = 0            ## 0 not tried, 1 ready, -1 none
  wkHandler: ObjcId      ## the kit's script message handler and navigation delegate
  wkViews: seq[WkView]

proc objc_allocateClassPair(super: pointer; name: cstring; extra: int): pointer {.importc, cdecl.}
proc objc_registerClassPair(cls: pointer) {.importc, cdecl.}
proc class_addMethod(cls, name, imp: pointer; types: cstring): bool {.importc, cdecl.}
proc class_addProtocol(cls, protocol: pointer): bool {.importc, cdecl.}
proc objc_getProtocol(name: cstring): pointer {.importc, cdecl.}

proc indexOf(view: ObjcId): int =
  for i, v in wkViews:
    if v.view == view: return i
  -1

proc indexOf(key: string): int =
  for i, v in wkViews:
    if v.key == key and v.view != nil: return i
  -1

proc urlOf(u: ObjcId): string =
  if u == nil: "" else: toNim(objcSend(ObjcId, u, "absoluteString"))

proc onScriptMessage(self, cmd, controller, message: ObjcId) {.cdecl.} =
  ## `retro.post(text)` in a page.
  let i = indexOf(objcSend(ObjcId, message, "webView"))
  if i < 0: return
  let body = objcSend(ObjcId, message, "body")
  if body != nil: wkViews[i].st.notes.add toNim(objcSend(ObjcId, body, "description"))

proc callDecision(handler: pointer; policy: int) =
  ## (WebKit's decision handler is a block: its function is 16 bytes in)
  let invoke = cast[ptr pointer](cast[uint](handler) + 16)[]
  cast[proc (blk: pointer; policy: int) {.cdecl.}](invoke)(handler, policy)

proc onDecide(self, cmd, webView, action: ObjcId; decision: pointer) {.cdecl.} =
  ## Where a page goes: an address it is not allowed is kept from it (the app
  ## is told); a new window opens in the same view.
  let i = indexOf(webView)
  let req = objcSend(ObjcId, action, "request")
  let url = urlOf(objcSend(ObjcId, req, "URL"))
  if i >= 0 and not allowedBy(wkViews[i].hosts, url):
    wkViews[i].st.blocked.add url
    callDecision(decision, 0)                                # cancel
    return
  if objcSend(ObjcId, action, "targetFrame") == nil:
    callDecision(decision, 0)
    discard objcSend(ObjcId, webView, "loadRequest:", req)
    return
  callDecision(decision, 1)                                  # allow

proc loadWebKit(): bool =
  ## WebKit, and the kit's class that hears its pages.
  if loadLib("/System/Library/Frameworks/WebKit.framework/WebKit") == nil: return false
  if objcClass("WKWebView") == nil: return false
  var cls = objcClass("RetroWebHandler")
  if cls == nil:
    cls = objc_allocateClassPair(objcClass("NSObject"), "RetroWebHandler", 0)
    if cls == nil: return false
    discard class_addMethod(cls, sel("userContentController:didReceiveScriptMessage:"),
                            cast[pointer](onScriptMessage), "v@:@@")
    discard class_addMethod(cls, sel("webView:decidePolicyForNavigationAction:decisionHandler:"),
                            cast[pointer](onDecide), "v@:@@@?")
    for p in ["WKScriptMessageHandler", "WKNavigationDelegate"]:
      let proto = objc_getProtocol(cstring(p))
      if proto != nil: discard class_addProtocol(cls, proto)
    objc_registerClassPair(cls)
  wkHandler = objcSend(ObjcId, objcSend(ObjcId, cls, "alloc"), "init")
  wkHandler != nil

proc hostView(): ObjcId =
  ## The view the pages go into: the window's content (macOS), its root
  ## view (iOS).
  when defined(ios):
    let app = objcSend(ObjcId, objcClass("UIApplication"), "sharedApplication")
    var win = objcSend(ObjcId, app, "keyWindow")
    if win == nil:
      let wins = objcSend(ObjcId, app, "windows")
      if wins != nil and objcSend(int, wins, "count") > 0: win = objcSend(ObjcId, wins, "firstObject")
    if win == nil: return nil
    let root = objcSend(ObjcId, win, "rootViewController")
    if root != nil: objcSend(ObjcId, root, "view") else: win
  else:
    let app = objcSend(ObjcId, objcClass("NSApplication"), "sharedApplication")
    var win = objcSend(ObjcId, app, "mainWindow")
    if win == nil:
      let wins = objcSend(ObjcId, app, "windows")
      if wins != nil and objcSend(int, wins, "count") > 0: win = objcSend(ObjcId, wins, "firstObject")
    if win == nil: nil else: objcSend(ObjcId, win, "contentView")

proc frameFor(host: ObjcId; r: Rect): CGRect =
  ## Window pixels as the host view's points (macOS counts from the bottom
  ## unless the view is flipped).
  when defined(ios):
    let scale = objcSend(float64, objcSend(ObjcId, objcClass("UIScreen"), "mainScreen"), "scale")
    let k = if scale > 0: scale else: 1.0
    CGRect(x: float(r.x) / k, y: float(r.y) / k, w: float(r.w) / k, h: float(r.h) / k)
  else:
    let win = objcSend(ObjcId, host, "window")
    let scale = if win != nil: objcSend(float64, win, "backingScaleFactor") else: 1.0
    let k = if scale > 0: scale else: 1.0
    let b = objcSend(CGRect, host, "bounds")
    var f = CGRect(x: float(r.x) / k, y: float(r.y) / k, w: float(r.w) / k, h: float(r.h) / k)
    if not objcSend(bool, host, "isFlipped"): f.y = b.h - f.y - f.h
    f

proc loadInto(v: var WkView; url: string) =
  v.url = url
  v.st.progress = 0
  if url.startsWith("html:"):
    discard objcSend(ObjcId, v.view, "loadHTMLString:baseURL:", nsString(url[5 .. ^1]), ObjcId(nil))
  elif url.len > 0 and url[0] == '/':
    let file = objcSend(ObjcId, objcClass("NSURL"), "fileURLWithPath:", nsString(url))
    let dir = objcSend(ObjcId, objcClass("NSURL"), "fileURLWithPath:", nsString(url.parentDir))
    discard objcSend(ObjcId, v.view, "loadFileURL:allowingReadAccessToURL:", file, dir)
  else:
    let u = objcSend(ObjcId, objcClass("NSURL"), "URLWithString:", nsString(url))
    if u == nil: return
    let req = objcSend(ObjcId, objcClass("NSURLRequest"), "requestWithURL:", u)
    discard objcSend(ObjcId, v.view, "loadRequest:", req)

proc makeView(host: ObjcId; frame: CGRect): ObjcId =
  let config = objcSend(ObjcId, objcSend(ObjcId, objcClass("WKWebViewConfiguration"), "alloc"), "init")
  let ucc = objcSend(ObjcId, config, "userContentController")
  objcSend(void, ucc, "addScriptMessageHandler:name:", wkHandler, nsString("retro"))
  let script = objcSend(ObjcId, objcSend(ObjcId, objcClass("WKUserScript"), "alloc"),
                        "initWithSource:injectionTime:forMainFrameOnly:",
                        nsString(shimFor("window.webkit.messageHandlers.retro.postMessage")), 0, true)
  objcSend(void, ucc, "addUserScript:", script)
  objcSend(void, script, "release")
  result = objcSend(ObjcId, objcSend(ObjcId, objcClass("WKWebView"), "alloc"),
                    "initWithFrame:configuration:", frame, config)
  objcSend(void, config, "release")
  objcSend(void, result, "setNavigationDelegate:", wkHandler)
  # (Safari's Web Inspector reaches it only when asked for: macOS 13.3, iOS 16.4)
  if webToolsWanted() and respondsTo(result, "setInspectable:"):
    objcSend(void, result, "setInspectable:", true)
  objcSend(void, host, "addSubview:", result)

# ---- in the app's thread ------------------------------------------------------------------------

proc webNativeAvailable*(): bool =
  ## Whether the system has a browser engine the kit can show pages in
  ## (WKWebView here).
  if wkState == 0: wkState = if loadWebKit(): 1 else: -1
  wkState == 1 and hostView() != nil

proc webNativeShow*(key: string; r: Rect; url: string; zoom: float) =
  ## The page `key` placed at `r` (window pixels), showing `url`; `zoom`
  ## (> 0) the size of its text and pictures.
  if not webNativeAvailable(): return
  autoreleasePool:
    let host = hostView()
    let frame = frameFor(host, r)
    var i = indexOf(key)
    if i < 0:
      wkViews.add WkView(key: key, view: makeView(host, frame))
      i = wkViews.high
    else:
      objcSend(void, wkViews[i].view, "setFrame:", frame)
    objcSend(void, wkViews[i].view, "setHidden:", false)
    wkViews[i].shown = true
    # (WebKit sizes pages for the screen's scale itself; this is the app's zoom)
    let scale = when defined(ios): objcSend(float64, objcSend(ObjcId, objcClass("UIScreen"), "mainScreen"), "scale")
                else: objcSend(float64, objcSend(ObjcId, host, "window"), "backingScaleFactor")
    let z = if zoom > 0: zoom / max(1.0, scale) else: 1.0
    if z != wkViews[i].zoom and respondsTo(wkViews[i].view, "setPageZoom:"):
      wkViews[i].zoom = z
      objcSend(void, wkViews[i].view, "setPageZoom:", z)
    if url != wkViews[i].url: wkViews[i].loadInto(url)

proc webNativeHide*(key: string) =
  ## Hides the page (kept with its place in history).
  let i = indexOf(key)
  if i < 0: return
  objcSend(void, wkViews[i].view, "setHidden:", true)
  wkViews[i].shown = false

proc webNativeClose*(key: string) =
  ## Lets the page go.
  let i = indexOf(key)
  if i < 0: return
  objcSend(void, wkViews[i].view, "removeFromSuperview")
  objcSend(void, wkViews[i].view, "release")
  wkViews[i].view = nil

proc webNativeNav*(key: string; what: WebNav) =
  ## Back, Forward, Reload or Stop in the page.
  let i = indexOf(key)
  if i < 0: return
  let v = wkViews[i].view
  case what
  of wnBack: discard objcSend(ObjcId, v, "goBack")
  of wnForward: discard objcSend(ObjcId, v, "goForward")
  of wnReload: discard objcSend(ObjcId, v, "reload")
  of wnStop: objcSend(void, v, "stopLoading")

proc webNativeRun*(key: string; js: string) =
  ## Runs `js` in the page (what it posts comes as notes).
  let i = indexOf(key)
  if i < 0: return
  autoreleasePool:
    objcSend(void, wkViews[i].view, "evaluateJavaScript:completionHandler:", nsString(js),
             pointer(nil))

proc webNativeAllow*(key: string; hosts: seq[string]) =
  ## The hosts the page may open (none: any).
  let i = indexOf(key)
  if i >= 0: wkViews[i].hosts = hosts

proc webNativeTake*(key: string): WebNativeState =
  ## The page now, and what it posted since the last look.
  let i = indexOf(key)
  if i < 0: return
  autoreleasePool:
    let v = wkViews[i].view
    wkViews[i].st.url = urlOf(objcSend(ObjcId, v, "URL"))
    wkViews[i].st.title = toNim(objcSend(ObjcId, v, "title"))
    wkViews[i].st.progress = clamp(int(objcSend(float64, v, "estimatedProgress") * 100), 0, 100)
    if not objcSend(bool, v, "isLoading"): wkViews[i].st.progress = 100
    wkViews[i].st.canBack = objcSend(bool, v, "canGoBack")
    wkViews[i].st.canForward = objcSend(bool, v, "canGoForward")
  result = wkViews[i].st
  wkViews[i].st.notes.setLen(0)
  wkViews[i].st.blocked.setLen(0)
