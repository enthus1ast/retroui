## (included by webnative) Linux and BSD: WebKitGTK, loaded when the first
## page is shown. GTK runs in a thread of its own with its own connection to
## the X server; each page is a GTK window of WebKit's put inside the app's
## window (reparented) where the widget is. The app's thread sends it orders
## (`g_idle_add`, which GTK's thread runs) and reads what it reports under a
## lock: nothing of GTK is touched from the app's thread.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[locks, dynlib, os, tables]
import uirelays/drivers/x11_driver

type
  GtkCmdKind = enum gcShow, gcHide, gcClose, gcNav, gcRun, gcAllow
  GtkCmd = object
    kind: GtkCmdKind
    key: string
    x, y, w, h: int
    parent: uint
    text: string
    nav: WebNav
    hosts: seq[string]
    zoom: float
  GtkView = object
    win, wv, ucm: pointer
    xid: culong
    loaded: string
    hosts: seq[string]
    zoom: float

  GCallback = proc () {.cdecl.}

var
  gtkLock: Lock
  gtkCmds: seq[GtkCmd]                       # (under the lock)
  gtkShared: Table[string, WebNativeState]   # (under the lock)
  gtkState = 0                               # 0 not started, 1 starting, 2 ready, -1 none
  gtkThread: Thread[void]
  gtkViews: Table[string, GtkView]           # (GTK's thread only)
  gtkKeyOf: Table[pointer, string]           # (GTK's thread only) a view's or manager's key
  gtkXDpy: pointer                           # (GTK's thread only) GTK's X connection

  # GTK, GDK, GLib, GObject
  gtk_init_check: proc (argc, argv: pointer): cint {.cdecl, gcsafe.}
  gtk_main: proc () {.cdecl, gcsafe.}
  gtk_window_new: proc (kind: cint): pointer {.cdecl, gcsafe.}
  gtk_window_set_default_size: proc (w: pointer; width, height: cint) {.cdecl, gcsafe.}
  gtk_window_move: proc (w: pointer; x, y: cint) {.cdecl, gcsafe.}
  gtk_window_resize: proc (w: pointer; width, height: cint) {.cdecl, gcsafe.}
  gtk_container_add: proc (c, w: pointer) {.cdecl, gcsafe.}
  gtk_widget_show_all: proc (w: pointer) {.cdecl, gcsafe.}
  gtk_widget_show: proc (w: pointer) {.cdecl, gcsafe.}
  gtk_widget_hide: proc (w: pointer) {.cdecl, gcsafe.}
  gtk_widget_destroy: proc (w: pointer) {.cdecl, gcsafe.}
  gtk_widget_grab_focus: proc (w: pointer) {.cdecl, gcsafe.}
  gtk_widget_get_window: proc (w: pointer): pointer {.cdecl, gcsafe.}
  gdk_x11_window_get_xid: proc (w: pointer): culong {.cdecl, gcsafe.}
  gdk_display_get_default: proc (): pointer {.cdecl, gcsafe.}
  gdk_x11_display_get_xdisplay: proc (d: pointer): pointer {.cdecl, gcsafe.}
  g_idle_add: proc (f: proc (data: pointer): cint {.cdecl, gcsafe.}; data: pointer): cuint {.cdecl, gcsafe.}
  g_free: proc (p: pointer) {.cdecl, gcsafe.}
  g_signal_connect_data: proc (inst: pointer; signal: cstring; handler: GCallback;
                               data, destroy: pointer; flags: cint): culong {.cdecl, gcsafe.}
  XReparentWindow: proc (dpy: pointer; w, parent: culong; x, y: cint): cint {.cdecl, gcsafe.}
  XSetInputFocus: proc (dpy: pointer; w: culong; revert: cint; time: culong): cint {.cdecl, gcsafe.}
  XFlush: proc (dpy: pointer): cint {.cdecl, gcsafe.}
  # WebKit
  webkit_user_content_manager_new: proc (): pointer {.cdecl, gcsafe.}
  webkit_user_content_manager_register_script_message_handler: proc (m: pointer; name: cstring): cint {.cdecl, gcsafe.}
  webkit_user_script_new: proc (src: cstring; frames, time: cint; allow, deny: pointer): pointer {.cdecl, gcsafe.}
  webkit_user_content_manager_add_script: proc (m, s: pointer) {.cdecl, gcsafe.}
  webkit_web_view_new_with_user_content_manager: proc (m: pointer): pointer {.cdecl, gcsafe.}
  webkit_web_view_get_settings: proc (v: pointer): pointer {.cdecl, gcsafe.}
  webkit_settings_set_enable_developer_extras: proc (s: pointer; on: cint) {.cdecl, gcsafe.}
  webkit_web_view_load_uri: proc (v: pointer; uri: cstring) {.cdecl, gcsafe.}
  webkit_web_view_load_html: proc (v: pointer; html, base: cstring) {.cdecl, gcsafe.}
  webkit_web_view_get_uri: proc (v: pointer): cstring {.cdecl, gcsafe.}
  webkit_web_view_get_title: proc (v: pointer): cstring {.cdecl, gcsafe.}
  webkit_web_view_get_estimated_load_progress: proc (v: pointer): cdouble {.cdecl, gcsafe.}
  webkit_web_view_can_go_back: proc (v: pointer): cint {.cdecl, gcsafe.}
  webkit_web_view_can_go_forward: proc (v: pointer): cint {.cdecl, gcsafe.}
  webkit_web_view_go_back: proc (v: pointer) {.cdecl, gcsafe.}
  webkit_web_view_go_forward: proc (v: pointer) {.cdecl, gcsafe.}
  webkit_web_view_reload: proc (v: pointer) {.cdecl, gcsafe.}
  webkit_web_view_stop_loading: proc (v: pointer) {.cdecl, gcsafe.}
  webkit_web_view_set_zoom_level: proc (v: pointer; z: cdouble) {.cdecl, gcsafe.}
  webkit_web_view_evaluate_javascript: proc (v: pointer; js: cstring; length: int;
      world, source, cancel, cb, data: pointer) {.cdecl, gcsafe.}
  webkit_web_view_run_javascript: proc (v: pointer; js: cstring; cancel, cb, data: pointer) {.cdecl, gcsafe.}
  webkit_navigation_policy_decision_get_navigation_action: proc (d: pointer): pointer {.cdecl, gcsafe.}
  webkit_navigation_action_get_request: proc (a: pointer): pointer {.cdecl, gcsafe.}
  webkit_uri_request_get_uri: proc (r: pointer): cstring {.cdecl, gcsafe.}
  webkit_policy_decision_ignore: proc (d: pointer) {.cdecl, gcsafe.}
  webkit_javascript_result_get_js_value: proc (r: pointer): pointer {.cdecl, gcsafe.}
  jsc_value_to_string: proc (v: pointer): cstring {.cdecl, gcsafe.}

const
  GtkWindowPopup = 1.cint
  InjectTopFrame = 1.cint
  InjectAtStart = 0.cint
  PolicyNavigation = 0.cint
  PolicyNewWindow = 1.cint
  RevertToParent = 2.cint

proc loadGtk(): bool =
  ## GTK 3, WebKitGTK and the libraries they come with; false when one is
  ## not on this system.
  template lib(names: openArray[string]): LibHandle =
    var h: LibHandle = nil
    for n in names:
      h = loadLib(n)
      if h != nil: break
    if h == nil: return false
    h
  template get(h: LibHandle; v: untyped; name: string; needed = true) =
    v = cast[typeof(v)](h.symAddr(name))
    if v == nil and needed: return false
  let gtk = lib(["libgtk-3.so.0", "libgtk-3.so"])
  let gdk = lib(["libgdk-3.so.0", "libgdk-3.so"])
  let glib = lib(["libglib-2.0.so.0", "libglib-2.0.so"])
  let gobj = lib(["libgobject-2.0.so.0", "libgobject-2.0.so"])
  let x11 = lib(["libX11.so.6", "libX11.so"])
  let wk = lib(["libwebkit2gtk-4.1.so.0", "libwebkit2gtk-4.1.so", "libwebkit2gtk-4.0.so.37",
                 "libwebkit2gtk-4.0.so"])
  gtk.get(gtk_init_check, "gtk_init_check")
  gtk.get(gtk_main, "gtk_main")
  gtk.get(gtk_window_new, "gtk_window_new")
  gtk.get(gtk_window_set_default_size, "gtk_window_set_default_size")
  gtk.get(gtk_window_move, "gtk_window_move")
  gtk.get(gtk_window_resize, "gtk_window_resize")
  gtk.get(gtk_container_add, "gtk_container_add")
  gtk.get(gtk_widget_show_all, "gtk_widget_show_all")
  gtk.get(gtk_widget_show, "gtk_widget_show")
  gtk.get(gtk_widget_hide, "gtk_widget_hide")
  gtk.get(gtk_widget_destroy, "gtk_widget_destroy")
  gtk.get(gtk_widget_grab_focus, "gtk_widget_grab_focus")
  gtk.get(gtk_widget_get_window, "gtk_widget_get_window")
  gdk.get(gdk_x11_window_get_xid, "gdk_x11_window_get_xid")
  gdk.get(gdk_display_get_default, "gdk_display_get_default")
  gdk.get(gdk_x11_display_get_xdisplay, "gdk_x11_display_get_xdisplay")
  glib.get(g_idle_add, "g_idle_add")
  glib.get(g_free, "g_free")
  gobj.get(g_signal_connect_data, "g_signal_connect_data")
  x11.get(XReparentWindow, "XReparentWindow")
  x11.get(XSetInputFocus, "XSetInputFocus")
  x11.get(XFlush, "XFlush")
  wk.get(webkit_user_content_manager_new, "webkit_user_content_manager_new")
  wk.get(webkit_user_content_manager_register_script_message_handler,
         "webkit_user_content_manager_register_script_message_handler")
  wk.get(webkit_user_script_new, "webkit_user_script_new")
  wk.get(webkit_user_content_manager_add_script, "webkit_user_content_manager_add_script")
  wk.get(webkit_web_view_new_with_user_content_manager, "webkit_web_view_new_with_user_content_manager")
  wk.get(webkit_web_view_get_settings, "webkit_web_view_get_settings")
  wk.get(webkit_settings_set_enable_developer_extras, "webkit_settings_set_enable_developer_extras")
  wk.get(webkit_web_view_load_uri, "webkit_web_view_load_uri")
  wk.get(webkit_web_view_load_html, "webkit_web_view_load_html")
  wk.get(webkit_web_view_get_uri, "webkit_web_view_get_uri")
  wk.get(webkit_web_view_get_title, "webkit_web_view_get_title")
  wk.get(webkit_web_view_get_estimated_load_progress, "webkit_web_view_get_estimated_load_progress")
  wk.get(webkit_web_view_can_go_back, "webkit_web_view_can_go_back")
  wk.get(webkit_web_view_can_go_forward, "webkit_web_view_can_go_forward")
  wk.get(webkit_web_view_go_back, "webkit_web_view_go_back")
  wk.get(webkit_web_view_go_forward, "webkit_web_view_go_forward")
  wk.get(webkit_web_view_reload, "webkit_web_view_reload")
  wk.get(webkit_web_view_stop_loading, "webkit_web_view_stop_loading")
  wk.get(webkit_web_view_set_zoom_level, "webkit_web_view_set_zoom_level")
  # (2.40 and later; older ones have run_javascript)
  wk.get(webkit_web_view_evaluate_javascript, "webkit_web_view_evaluate_javascript", false)
  wk.get(webkit_web_view_run_javascript, "webkit_web_view_run_javascript", false)
  if webkit_web_view_evaluate_javascript == nil and webkit_web_view_run_javascript == nil:
    return false
  wk.get(webkit_navigation_policy_decision_get_navigation_action,
         "webkit_navigation_policy_decision_get_navigation_action")
  wk.get(webkit_navigation_action_get_request, "webkit_navigation_action_get_request")
  wk.get(webkit_uri_request_get_uri, "webkit_uri_request_get_uri")
  wk.get(webkit_policy_decision_ignore, "webkit_policy_decision_ignore")
  wk.get(webkit_javascript_result_get_js_value, "webkit_javascript_result_get_js_value")
  # (JavaScriptCore comes with WebKit)
  wk.get(jsc_value_to_string, "jsc_value_to_string", false)
  if jsc_value_to_string == nil:
    let jsc = lib(["libjavascriptcoregtk-4.1.so.0", "libjavascriptcoregtk-4.1.so",
                   "libjavascriptcoregtk-4.0.so.18", "libjavascriptcoregtk-4.0.so"])
    jsc.get(jsc_value_to_string, "jsc_value_to_string")
  true

# ---- in GTK's thread ------------------------------------------------------------------------------

proc keyOf(p: pointer): string =
  {.cast(gcsafe).}: gtkKeyOf.getOrDefault(p, "")

template shared(key: string; body: untyped) =
  ## `it`: the page's state, under the lock.
  {.cast(gcsafe).}:
    withLock gtkLock:
      if gtkShared.hasKey(key):
        var it {.inject.} = addr gtkShared[key]
        body

proc onChange(wv, a, b: pointer) {.cdecl, gcsafe.} =
  ## The page's address, title, loading or history changed.
  let key = keyOf(wv)
  if key.len == 0: return
  let u = webkit_web_view_get_uri(wv)
  let t = webkit_web_view_get_title(wv)
  let p = int(webkit_web_view_get_estimated_load_progress(wv) * 100)
  let back = webkit_web_view_can_go_back(wv) != 0
  let fwd = webkit_web_view_can_go_forward(wv) != 0
  shared(key):
    it.url = if u == nil: "" else: $u
    it.title = if t == nil: "" else: $t
    it.progress = clamp(p, 0, 100)
    it.canBack = back
    it.canForward = fwd

proc onMessage(ucm, res, data: pointer) {.cdecl, gcsafe.} =
  ## `retro.post(text)` in the page.
  let key = keyOf(ucm)
  if key.len == 0 or res == nil: return
  let v = webkit_javascript_result_get_js_value(res)
  if v == nil: return
  let s = jsc_value_to_string(v)
  if s == nil: return
  let text = $s
  g_free(s)
  shared(key): it.notes.add text

proc onPolicy(wv, decision: pointer; kind: cint; data: pointer): cint {.cdecl, gcsafe.} =
  ## Where the page goes: an address it is not allowed is kept from it (the
  ## app is told); a new window opens in the same view.
  if kind != PolicyNavigation and kind != PolicyNewWindow: return 0
  let key = keyOf(wv)
  let action = webkit_navigation_policy_decision_get_navigation_action(decision)
  if action == nil: return 0
  let req = webkit_navigation_action_get_request(action)
  let u = if req == nil: nil else: webkit_uri_request_get_uri(req)
  if u == nil: return 0
  let url = $u
  var hosts: seq[string]
  {.cast(gcsafe).}:
    if gtkViews.hasKey(key): hosts = gtkViews[key].hosts
  if not allowedBy(hosts, url):
    webkit_policy_decision_ignore(decision)
    shared(key): it.blocked.add url
    return 1
  if kind == PolicyNewWindow:
    webkit_policy_decision_ignore(decision)
    webkit_web_view_load_uri(wv, url.cstring)
    return 1
  0

proc onPress(widget, event, data: pointer): cint {.cdecl, gcsafe.} =
  ## A press in the page: the keyboard goes to it.
  let key = keyOf(widget)
  {.cast(gcsafe).}:
    if gtkViews.hasKey(key):
      let v = gtkViews[key]
      discard XSetInputFocus(gtkXDpy, v.xid, RevertToParent, 0)
      discard XFlush(gtkXDpy)
      gtk_widget_grab_focus(v.wv)
  0

proc onFocus(win, event, data: pointer): cint {.cdecl, gcsafe.} =
  let key = keyOf(win)
  shared(key): it.focused = true
  0

proc onBlur(win, event, data: pointer): cint {.cdecl, gcsafe.} =
  let key = keyOf(win)
  shared(key): it.focused = false
  0

proc connect(inst: pointer; signal: string; handler: pointer) =
  discard g_signal_connect_data(inst, signal.cstring, cast[GCallback](handler), nil, nil, 0)

proc load(v: var GtkView; url: string) =
  v.loaded = url
  if url.startsWith("html:"): webkit_web_view_load_html(v.wv, url[5 .. ^1].cstring, nil)
  elif url.len > 0 and url[0] == '/': webkit_web_view_load_uri(v.wv, fileUrl(url).cstring)
  else: webkit_web_view_load_uri(v.wv, url.cstring)

proc runJs(wv: pointer; js: string) =
  if webkit_web_view_evaluate_javascript != nil:
    webkit_web_view_evaluate_javascript(wv, js.cstring, -1, nil, nil, nil, nil, nil)
  else:
    webkit_web_view_run_javascript(wv, js.cstring, nil, nil, nil)

proc exec(c: GtkCmd) =
  {.cast(gcsafe).}:
    case c.kind
    of gcShow:
      var v = gtkViews.getOrDefault(c.key)
      if v.wv == nil:
        v.ucm = webkit_user_content_manager_new()
        gtkKeyOf[v.ucm] = c.key
        connect(v.ucm, "script-message-received::retro", onMessage)
        discard webkit_user_content_manager_register_script_message_handler(v.ucm, "retro")
        webkit_user_content_manager_add_script(v.ucm, webkit_user_script_new(
          shimFor("window.webkit.messageHandlers.retro.postMessage").cstring,
          InjectTopFrame, InjectAtStart, nil, nil))
        v.wv = webkit_web_view_new_with_user_content_manager(v.ucm)
        gtkKeyOf[v.wv] = c.key
        # (Inspect Element in the page's menu only when asked for)
        webkit_settings_set_enable_developer_extras(webkit_web_view_get_settings(v.wv),
                                                    cint(webToolsWanted()))
        for s in ["notify::uri", "notify::title", "notify::estimated-load-progress",
                  "load-changed"]:
          connect(v.wv, s, onChange)
        connect(v.wv, "decide-policy", onPolicy)
        connect(v.wv, "button-press-event", onPress)
        v.win = gtk_window_new(GtkWindowPopup)
        gtkKeyOf[v.win] = c.key
        connect(v.win, "focus-in-event", onFocus)
        connect(v.win, "focus-out-event", onBlur)
        gtk_window_set_default_size(v.win, cint(max(1, c.w)), cint(max(1, c.h)))
        gtk_container_add(v.win, v.wv)
        gtk_widget_show_all(v.win)
        v.xid = gdk_x11_window_get_xid(gtk_widget_get_window(v.win))
        discard XReparentWindow(gtkXDpy, v.xid, culong(c.parent), cint(c.x), cint(c.y))
        discard XFlush(gtkXDpy)
      else:
        gtk_widget_show(v.win)
      gtk_window_move(v.win, cint(c.x), cint(c.y))
      gtk_window_resize(v.win, cint(max(1, c.w)), cint(max(1, c.h)))
      if c.zoom > 0 and c.zoom != v.zoom:
        v.zoom = c.zoom
        webkit_web_view_set_zoom_level(v.wv, c.zoom)
      if c.text != v.loaded: v.load(c.text)
      gtkViews[c.key] = v
    of gcHide:
      if gtkViews.hasKey(c.key): gtk_widget_hide(gtkViews[c.key].win)
    of gcClose:
      if gtkViews.hasKey(c.key):
        let v = gtkViews[c.key]
        gtkKeyOf.del v.wv
        gtkKeyOf.del v.ucm
        gtkKeyOf.del v.win
        gtk_widget_destroy(v.win)
        gtkViews.del c.key
    of gcNav:
      if gtkViews.hasKey(c.key):
        let wv = gtkViews[c.key].wv
        case c.nav
        of wnBack: webkit_web_view_go_back(wv)
        of wnForward: webkit_web_view_go_forward(wv)
        of wnReload: webkit_web_view_reload(wv)
        of wnStop: webkit_web_view_stop_loading(wv)
    of gcRun:
      if gtkViews.hasKey(c.key): runJs(gtkViews[c.key].wv, c.text)
    of gcAllow:
      if gtkViews.hasKey(c.key): gtkViews[c.key].hosts = c.hosts

proc drain(data: pointer): cint {.cdecl, gcsafe.} =
  ## The app's orders, run in GTK's thread.
  var cmds: seq[GtkCmd]
  {.cast(gcsafe).}:
    withLock gtkLock: swap(cmds, gtkCmds)
  for c in cmds: exec(c)
  0

proc webkitLoop() {.thread.} =
  {.cast(gcsafe).}:
    if gtk_init_check(nil, nil) == 0:
      withLock gtkLock: gtkState = -1
      return
    gtkXDpy = gdk_x11_display_get_xdisplay(gdk_display_get_default())
    withLock gtkLock: gtkState = 2
    gtk_main()

# ---- in the app's thread --------------------------------------------------------------------------

proc webNativeAvailable*(): bool =
  ## Whether the system has a browser engine the kit can show pages in
  ## (WebKitGTK here, with the X11 driver's window). The first call starts
  ## it (a second or so).
  if gtkState == 0:
    gtkState = 1
    initLock gtkLock
    if not loadGtk():
      gtkState = -1
      return false
    putEnv("GDK_BACKEND", "x11")      # (its windows go inside an X11 window)
    createThread(gtkThread, webkitLoop)
  var waited = 0
  while true:
    var s: int
    withLock gtkLock: s = gtkState
    if s != 1 or waited >= 5000: break
    sleep(10)
    waited += 10
  var s: int
  withLock gtkLock: s = gtkState
  s == 2 and x11Window() != 0

proc send(c: sink GtkCmd) =
  if not webNativeAvailable(): return
  withLock gtkLock:
    if c.kind == gcShow and not gtkShared.hasKey(c.key):
      gtkShared[c.key] = WebNativeState(progress: 0)
    gtkCmds.add c
  discard g_idle_add(drain, nil)

proc webNativeShow*(key: string; r: Rect; url: string; zoom: float) =
  ## The page `key` placed at `r` (window pixels), showing `url`; `zoom`
  ## (> 0) the size of its text and pictures.
  send GtkCmd(kind: gcShow, key: key, x: r.x, y: r.y, w: r.w, h: r.h, parent: x11Window(),
              text: url, zoom: zoom)

proc webNativeHide*(key: string) = send GtkCmd(kind: gcHide, key: key)
  ## Hides the page (kept with its place in history).

proc webNativeClose*(key: string) =
  ## Lets the page go.
  send GtkCmd(kind: gcClose, key: key)
  if gtkState == 2:
    withLock gtkLock: gtkShared.del key

proc webNativeNav*(key: string; what: WebNav) = send GtkCmd(kind: gcNav, key: key, nav: what)
  ## Back, Forward, Reload or Stop in the page.

proc webNativeRun*(key: string; js: string) = send GtkCmd(kind: gcRun, key: key, text: js)
  ## Runs `js` in the page (what it posts comes as notes).

proc webNativeAllow*(key: string; hosts: seq[string]) =
  ## The hosts the page may open (none: any).
  send GtkCmd(kind: gcAllow, key: key, hosts: hosts)

proc webNativeTake*(key: string): WebNativeState =
  ## The page now, and what it posted since the last look.
  if gtkState != 2: return
  withLock gtkLock:
    if gtkShared.hasKey(key):
      result = gtkShared[key]
      gtkShared[key].notes.setLen(0)
      gtkShared[key].blocked.setLen(0)
