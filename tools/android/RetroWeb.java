package org.retro;

import android.app.Activity;
import android.app.Application;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.PixelFormat;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import java.util.ArrayList;
import java.util.HashMap;

/** Web pages: the system's WebView over a part of the window (webView in
 *  src/retroui/htmlview.nim), reached as "web.show", "web.hide",
 *  "web.close", "web.back", "web.forward", "web.reload", "web.stop",
 *  "web.run", "web.allow", "web.zoom" and "web.info" through
 *  RetroActivity.uirelaysCall. The page's scripts post to the app with
 *  retro.post(text); what they post comes with "web.info".
 *
 *  NativeActivity reads the window's input itself: a WebView inside the
 *  window would never get a touch. So each page lives in a small panel
 *  window of its own over the activity, placed where the app draws it
 *  (window pixels). The panel takes the keyboard only once it is touched
 *  (the app's own text boxes keep theirs until then) and gives it back on a
 *  touch outside it. Back goes back in the page; with no page before, the
 *  app is told (web.info) and the keyboard goes back to it. */
public final class RetroWeb {
  private RetroWeb() { }

  static final class Web {
    Activity act;
    WebView view;
    Root root;
    WindowManager.LayoutParams lp;
    boolean added;
    String loaded = "";
    volatile String url = "", title = "";
    volatile int progress = 100;
    volatile boolean canBack, canForward, backOut;
    volatile String[] hosts = new String[0];
    final ArrayList<String> notes = new ArrayList<String>();   // "m" text, "b" address
  }

  /** retro.post(text) in the page's scripts. */
  static final class Bridge {
    final Web web;
    Bridge(Web w) { web = w; }
    @JavascriptInterface
    public void post(String m) {
      synchronized (web.notes) { web.notes.add("m" + (m == null ? "" : m)); }
    }
  }

  /** May the page open `url` (its host one of the allowed, or under one)? */
  static boolean allowed(Web w, String url) {
    String[] hs = w.hosts;
    if (hs.length == 0) return true;
    String host;
    try { host = Uri.parse(url).getHost(); } catch (Throwable t) { host = null; }
    if (host == null) return true;
    host = host.toLowerCase();
    for (String h : hs) {
      String x = h.trim().toLowerCase();
      if (x.length() > 0 && (host.equals(x) || host.endsWith("." + x))) return true;
    }
    return false;
  }

  static final HashMap<String, Web> webs = new HashMap<String, Web>();
  static boolean watching;

  static final class Root extends FrameLayout {
    final Web web;
    Root(Activity a, Web w) { super(a); web = w; }

    @Override
    public boolean dispatchTouchEvent(MotionEvent e) {
      if (e.getActionMasked() == MotionEvent.ACTION_OUTSIDE) {
        focusable(web, false);
        return false;
      }
      if (e.getActionMasked() == MotionEvent.ACTION_DOWN) focusable(web, true);
      return super.dispatchTouchEvent(e);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent e) {
      if (e.getKeyCode() == KeyEvent.KEYCODE_BACK) {
        if (e.getAction() == KeyEvent.ACTION_UP) {
          if (web.view.canGoBack()) web.view.goBack();
          else {
            web.backOut = true;
            focusable(web, false);
          }
        }
        return true;
      }
      return super.dispatchKeyEvent(e);
    }
  }

  static void focusable(Web w, boolean on) {
    if (w.lp == null) return;
    int f = w.lp.flags;
    int nf = on ? (f & ~WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
                : (f | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
    if (nf == f) return;
    w.lp.flags = nf;
    if (w.added) {
      try { w.act.getWindowManager().updateViewLayout(w.root, w.lp); } catch (Throwable t) { }
    }
  }

  /** Pages pause with the activity and go with it. */
  static void watch(final Activity a) {
    if (watching) return;
    watching = true;
    a.getApplication().registerActivityLifecycleCallbacks(
        new Application.ActivityLifecycleCallbacks() {
          public void onActivityPaused(Activity x) {
            for (Web w : all(x)) {
              try { w.view.onPause(); } catch (Throwable t) { }
            }
          }
          public void onActivityResumed(Activity x) {
            for (Web w : all(x)) {
              try { if (w.added) w.view.onResume(); } catch (Throwable t) { }
            }
          }
          public void onActivityDestroyed(Activity x) {
            for (Web w : all(x)) {
              try {
                remove(w);
                w.view.destroy();
              } catch (Throwable t) { }
            }
            synchronized (webs) { webs.values().removeAll(all(x)); }
          }
          public void onActivityCreated(Activity x, Bundle b) { }
          public void onActivityStarted(Activity x) { }
          public void onActivityStopped(Activity x) { }
          public void onActivitySaveInstanceState(Activity x, Bundle b) { }
        });
  }

  static java.util.ArrayList<Web> all(Activity a) {
    java.util.ArrayList<Web> r = new java.util.ArrayList<Web>();
    synchronized (webs) {
      for (Web w : webs.values()) if (w.act == a) r.add(w);
    }
    return r;
  }

  /** The page with `key`, made the first time (on the UI thread). */
  static Web webOf(final Activity a, String key) {
    Web w;
    synchronized (webs) { w = webs.get(key); }
    if (w != null) return w;
    watch(a);
    final Web nw = new Web();
    nw.act = a;
    WebView v = new WebView(a);
    WebSettings s = v.getSettings();
    s.setJavaScriptEnabled(true);
    s.setDomStorageEnabled(true);
    s.setBuiltInZoomControls(true);
    s.setDisplayZoomControls(false);
    s.setUseWideViewPort(true);
    s.setLoadWithOverviewMode(true);
    s.setAllowFileAccess(false);
    s.setAllowFileAccessFromFileURLs(false);
    s.setAllowUniversalAccessFromFileURLs(false);
    v.setWebViewClient(new WebViewClient() {
      @Override
      public boolean shouldOverrideUrlLoading(WebView view, String url) {
        String l = url.toLowerCase();
        if (l.startsWith("http:") || l.startsWith("https:")) {
          if (allowed(nw, url)) return false;
          synchronized (nw.notes) { nw.notes.add("b" + url); }   // the app is told
          return true;
        }
        if (l.startsWith("file:") || l.startsWith("about:") || l.startsWith("data:")) return false;
        try {                       // mail, phone, maps, stores: their apps
          Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
          i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
          a.startActivity(i);
        } catch (Throwable t) { }
        return true;
      }
      @Override
      public void onPageStarted(WebView view, String url, Bitmap icon) {
        nw.url = url == null ? "" : url;
        nw.progress = 0;
      }
      @Override
      public void onPageFinished(WebView view, String url) {
        nw.url = url == null ? "" : url;
        nw.progress = 100;
        nw.canBack = view.canGoBack();
        nw.canForward = view.canGoForward();
      }
      @Override
      public void doUpdateVisitedHistory(WebView view, String url, boolean reload) {
        nw.url = url == null ? "" : url;
        nw.canBack = view.canGoBack();
        nw.canForward = view.canGoForward();
      }
    });
    v.setWebChromeClient(new WebChromeClient() {
      @Override
      public void onProgressChanged(WebView view, int p) { nw.progress = p; }
      @Override
      public void onReceivedTitle(WebView view, String t) { nw.title = t == null ? "" : t; }
    });
    v.addJavascriptInterface(new Bridge(nw), "retro");
    nw.view = v;
    nw.root = new Root(a, nw);
    nw.root.addView(v, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                                                    ViewGroup.LayoutParams.MATCH_PARENT));
    WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
        WindowManager.LayoutParams.TYPE_APPLICATION_PANEL,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
            | WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
        PixelFormat.OPAQUE);
    lp.gravity = Gravity.TOP | Gravity.LEFT;
    nw.lp = lp;
    synchronized (webs) { webs.put(key, nw); }
    return nw;
  }

  static void load(Web w, String url) {
    w.loaded = url;
    w.view.getSettings().setAllowFileAccess(url.startsWith("file:") || url.startsWith("/"));
    if (url.startsWith("html:"))
      w.view.loadDataWithBaseURL(null, url.substring(5), "text/html", "utf-8", null);
    else if (url.startsWith("/")) w.view.loadUrl("file://" + url);
    else w.view.loadUrl(url);
  }

  static void remove(Web w) {
    if (!w.added) return;
    try { w.act.getWindowManager().removeViewImmediate(w.root); } catch (Throwable t) { }
    w.added = false;
  }

  /** show (key, x, y, w, h, url), hide, close, back, forward, reload, stop
   *  (key), run (key, script), allow (key, hosts...), zoom (key, percent) and
   *  info (key: url, title, progress, can go back, Back pressed with no page
   *  before, can go forward, then the notes: "m" text or "b" address, each
   *  ending with \2) -- from the native thread. */
  public static String call(final Activity act, String what, String[] a) {
    final String key = a.length > 0 ? a[0] : "";
    if (what.equals("show")) {
      if (a.length < 6) return null;
      final int x = Integer.parseInt(a[1]), y = Integer.parseInt(a[2]);
      final int w = Math.max(1, Integer.parseInt(a[3])), h = Math.max(1, Integer.parseInt(a[4]));
      StringBuilder u = new StringBuilder(a[5]);
      for (int i = 6; i < a.length; i++) u.append('\t').append(a[i]);
      final String url = u.toString();
      act.runOnUiThread(new Runnable() {
        public void run() {
          try {
            Web wb = webOf(act, key);
            wb.lp.x = x;
            wb.lp.y = y;
            wb.lp.width = w;
            wb.lp.height = h;
            if (wb.lp.token == null) wb.lp.token = act.getWindow().getDecorView().getWindowToken();
            if (wb.lp.token == null) return;       // not on screen yet: the next show
            if (!wb.added) {
              act.getWindowManager().addView(wb.root, wb.lp);
              wb.added = true;
              wb.view.onResume();
            } else act.getWindowManager().updateViewLayout(wb.root, wb.lp);
            if (!url.equals(wb.loaded)) load(wb, url);
          } catch (Throwable t) { }
        }
      });
      return "";
    }
    final Web wb;
    synchronized (webs) { wb = webs.get(key); }
    if (what.equals("info")) {
      if (wb == null) return null;
      boolean out = wb.backOut;
      wb.backOut = false;
      StringBuilder notes = new StringBuilder();
      synchronized (wb.notes) {
        for (String n : wb.notes) notes.append(n).append('\u0002');
        wb.notes.clear();
      }
      return wb.url + "\t" + wb.title.replace('\t', ' ') + "\t" + wb.progress + "\t"
          + (wb.canBack ? "1" : "0") + "\t" + (out ? "1" : "0") + "\t"
          + (wb.canForward ? "1" : "0") + "\t" + notes;
    }
    if (wb == null) return what.equals("back") ? "0" : "";
    if (what.equals("back")) {
      if (!wb.canBack) return "0";
      act.runOnUiThread(new Runnable() {
        public void run() { if (wb.view.canGoBack()) wb.view.goBack(); }
      });
      return "1";
    }
    if (what.equals("forward")) {
      if (!wb.canForward) return "0";
      act.runOnUiThread(new Runnable() {
        public void run() { if (wb.view.canGoForward()) wb.view.goForward(); }
      });
      return "1";
    }
    if (what.equals("allow")) {
      String[] hs = new String[Math.max(0, a.length - 1)];
      for (int i = 1; i < a.length; i++) hs[i - 1] = a[i];
      wb.hosts = hs;
      return "";
    }
    if (what.equals("run") || what.equals("zoom") || what.equals("stop")) {
      StringBuilder j = new StringBuilder(a.length > 1 ? a[1] : "");
      for (int i = 2; i < a.length; i++) j.append('\t').append(a[i]);
      final String arg = j.toString();
      final String op = what;
      act.runOnUiThread(new Runnable() {
        public void run() {
          try {
            if (op.equals("run")) wb.view.evaluateJavascript(arg, null);
            else if (op.equals("stop")) wb.view.stopLoading();
            else wb.view.getSettings().setTextZoom(Math.max(50, Math.min(300, Integer.parseInt(arg.trim()))));
          } catch (Throwable t) { }
        }
      });
      return "";
    }
    if (what.equals("hide") || what.equals("close") || what.equals("reload")) {
      final boolean close = what.equals("close");
      final boolean reload = what.equals("reload");
      act.runOnUiThread(new Runnable() {
        public void run() {
          try {
            if (reload) { wb.view.reload(); return; }
            remove(wb);
            if (close) {
              synchronized (webs) { webs.remove(key); }
              wb.view.destroy();
            } else wb.view.onPause();
          } catch (Throwable t) { }
        }
      });
      return "";
    }
    return null;
  }
}
