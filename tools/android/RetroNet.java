package org.retro;

import android.app.Activity;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.Field;
import java.net.HttpURLConnection;
import java.net.ProtocolException;
import java.net.URL;

/** Downloads for retro's asset store (src/retro/assetfetch.nim) and web
 *  requests for retro/http. The native side calls "net.what" with
 *  tab-separated arguments, from any thread (its download workers):
 *  "net.download" url, dest, user agent, timeout in ms[, headers] downloads
 *  url into the file dest (through dest + ".part", renamed when whole) and
 *  answers "1", or "e" and what went wrong. Headers ("Name: value", split
 *  by "\r": an API's key) go only to the address's own host. Redirects are followed by hand, also
 *  from http to https and back, which HttpURLConnection does not do.
 *  "net.request" method, url, headers, timeout in ms, body file, answer
 *  file, follow ("1"/"0") sends one request of any method (PATCH too) with
 *  the bytes of the body file ("": none), writes the answer's body into the
 *  answer file and answers the status and the headers ("200\nname: value\n
 *  ..."), or "e" and why no answer came. Redirects are followed by hand
 *  when asked; Authorization and Cookie go only to the first host.
 *  "net.available" answers "1". */
public class RetroNet {
  public static String call(Activity a, String what, String[] args) {
    if (what.equals("available")) return "1";
    if (what.equals("request")) {
      if (args.length < 7) return "emissing arguments";
      int ms = 60000;
      try { ms = Math.max(1000, Integer.parseInt(args[3].trim())); } catch (Throwable t) { }
      return request(args[0], args[1], args[2], ms, args[4], args[5], args[6].equals("1"));
    }
    if (what.equals("download")) {
      if (args.length < 2) return "eno address";
      String ua = args.length > 2 && args[2].length() > 0 ? args[2] : "RetroApp";
      int ms = 60000;
      if (args.length > 3) {
        try { ms = Math.max(1000, Integer.parseInt(args[3].trim())); } catch (Throwable t) { }
      }
      String hs = args.length > 4 ? args[4] : "";
      return download(args[0], args[1], ua, ms, hs);
    }
    return null;
  }

  static String download(String url, String dest, String ua, int ms, String headers) {
    File out = new File(dest);
    File part = new File(dest + ".part");
    HttpURLConnection c = null;
    try {
      File dir = out.getParentFile();
      if (dir != null && !dir.isDirectory()) dir.mkdirs();
      URL u = new URL(url);
      String home = u.getHost();
      for (int hops = 0; ; hops++) {
        if (hops > 10) return "etoo many redirects";
        String p = u.getProtocol();
        if (!p.equals("http") && !p.equals("https")) return "eunsupported address: " + u;
        c = (HttpURLConnection) u.openConnection();
        c.setInstanceFollowRedirects(false);
        c.setConnectTimeout(ms);
        c.setReadTimeout(ms);
        c.setUseCaches(false);
        c.setRequestProperty("User-Agent", ua);
        if (headers != null && headers.length() > 0 && u.getHost().equalsIgnoreCase(home)) {
          for (String h : headers.split("\r")) {
            int k = h.indexOf(':');
            if (k > 0) c.setRequestProperty(h.substring(0, k).trim(), h.substring(k + 1).trim());
          }
        }
        int code = c.getResponseCode();
        if (code >= 300 && code < 400 && code != 304) {
          String loc = c.getHeaderField("Location");
          c.disconnect();
          c = null;
          if (loc == null || loc.length() == 0)
            return "ethe server answered " + code + " without a new address";
          u = new URL(u, loc);
          continue;
        }
        if (code != 200) return "ethe server answered " + code;
        break;
      }
      long want = -1;
      try {
        String len = c.getHeaderField("Content-Length");
        // (a gzip answer HttpURLConnection unpacks has another length)
        String enc = c.getContentEncoding();
        if (len != null && (enc == null || enc.equals("identity"))) want = Long.parseLong(len.trim());
      } catch (Throwable t) { }
      long got = 0;
      InputStream in = c.getInputStream();
      OutputStream os = new FileOutputStream(part);
      try {
        byte[] buf = new byte[65536];
        int n;
        while ((n = in.read(buf)) > 0) {
          os.write(buf, 0, n);
          got += n;
        }
      } finally {
        try { os.close(); } catch (Throwable t) { }
        try { in.close(); } catch (Throwable t) { }
      }
      if (want >= 0 && got != want) {
        part.delete();
        return "ethe download was cut off (" + got + " of " + want + " bytes)";
      }
      if (out.exists()) out.delete();
      if (!part.renameTo(out)) {
        part.delete();
        return "ecannot write " + dest;
      }
      return "1";
    } catch (Throwable t) {
      part.delete();
      String m = t.getMessage();
      return "e" + (m != null && m.length() > 0 ? m : t.toString());
    } finally {
      if (c != null) c.disconnect();
    }
  }

  /** HttpURLConnection refuses the methods it does not know -- PATCH,
   *  which Microsoft Graph needs. Then the method goes into its field by
   *  reflection, and into the field of the connection an https one hands
   *  its work to (its "delegate"); false when it could not be set. */
  static boolean setMethod(HttpURLConnection c, String m) {
    try {
      c.setRequestMethod(m);
      return true;
    } catch (ProtocolException e) {
      // (refused: by hand below)
    }
    try {
      Field f = HttpURLConnection.class.getDeclaredField("method");
      f.setAccessible(true);
      f.set(c, m);
      for (Class<?> k = c.getClass(); k != null && k != HttpURLConnection.class; k = k.getSuperclass()) {
        Field d;
        try {
          d = k.getDeclaredField("delegate");
        } catch (NoSuchFieldException e) {
          continue;
        }
        d.setAccessible(true);
        Object o = d.get(c);
        if (o instanceof HttpURLConnection) f.set(o, m);
        break;
      }
    } catch (Throwable t) {
      return false;
    }
    return m.equals(c.getRequestMethod());
  }

  static String request(String method, String url, String headers, int ms,
                        String bodyPath, String outPath, boolean follow) {
    HttpURLConnection c = null;
    File body = bodyPath.length() > 0 ? new File(bodyPath) : null;
    boolean dropType = false;
    try {
      URL u = new URL(url);
      String home = u.getHost();
      for (int hops = 0; ; hops++) {
        if (hops > 10) return "etoo many redirects";
        String p = u.getProtocol();
        if (!p.equals("http") && !p.equals("https")) return "eunsupported address: " + u;
        c = (HttpURLConnection) u.openConnection();
        c.setInstanceFollowRedirects(false);
        c.setConnectTimeout(ms);
        c.setReadTimeout(ms);
        c.setUseCaches(false);
        boolean sameHost = u.getHost().equalsIgnoreCase(home);
        boolean agent = false;
        if (headers.length() > 0) {
          for (String h : headers.split("\r")) {
            int k = h.indexOf(':');
            if (k <= 0) continue;
            String name = h.substring(0, k).trim();
            if (!sameHost && (name.equalsIgnoreCase("Authorization") || name.equalsIgnoreCase("Cookie")))
              continue;
            if (dropType && name.equalsIgnoreCase("Content-Type")) continue;
            if (name.equalsIgnoreCase("User-Agent")) agent = true;
            c.addRequestProperty(name, h.substring(k + 1).trim());
          }
        }
        if (!agent) c.setRequestProperty("User-Agent", "RetroNimUI/0.16");
        if (body != null) {
          c.setDoOutput(true);
          c.setFixedLengthStreamingMode(body.length());
        }
        if (!setMethod(c, method)) return "ethis system's HTTP cannot send " + method;
        if (body != null) {
          OutputStream os = c.getOutputStream();
          InputStream in = new FileInputStream(body);
          try {
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) os.write(buf, 0, n);
          } finally {
            try { in.close(); } catch (Throwable t) { }
            os.close();
          }
        }
        int code = c.getResponseCode();
        if (code < 0) return "enot an HTTP answer";
        if (follow && (code == 301 || code == 302 || code == 303 || code == 307 || code == 308)) {
          String loc = c.getHeaderField("Location");
          if (loc != null && loc.length() > 0) {
            drain(c);
            c.disconnect();
            c = null;
            u = new URL(u, loc);
            if ((code == 303 && !method.equals("HEAD")) ||
                ((code == 301 || code == 302) && method.equals("POST"))) {
              method = "GET";
              body = null;
              dropType = true;
            }
            continue;
          }
        }
        StringBuilder b = new StringBuilder();
        b.append(code).append('\n');
        for (int i = 0; i < 1000; i++) {
          String k = c.getHeaderFieldKey(i);
          String v = c.getHeaderField(i);
          if (k == null && v == null) break;
          if (k == null || v == null) continue;       // (the status line)
          b.append(k).append(": ").append(v.replace('\r', ' ').replace('\n', ' ')).append('\n');
        }
        long want = -1;
        try {
          String len = c.getHeaderField("Content-Length");
          // (a gzip answer HttpURLConnection unpacks has another length)
          String enc = c.getContentEncoding();
          if (len != null && (enc == null || enc.equals("identity"))) want = Long.parseLong(len.trim());
        } catch (Throwable t) { }
        long got = 0;
        InputStream in = null;
        if (!method.equals("HEAD")) {
          try {
            in = code >= 400 ? c.getErrorStream() : c.getInputStream();
          } catch (IOException e) {
            in = c.getErrorStream();
          }
        }
        OutputStream os = new FileOutputStream(outPath);
        try {
          if (in != null) {
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) {
              os.write(buf, 0, n);
              got += n;
            }
          }
        } finally {
          try { os.close(); } catch (Throwable t) { }
          if (in != null) try { in.close(); } catch (Throwable t) { }
        }
        if (in != null && want >= 0 && got != want)
          return "ethe answer was cut off (" + got + " of " + want + " bytes)";
        return b.toString();
      }
    } catch (java.net.SocketTimeoutException t) {
      return "eno answer from the server in " + (ms / 1000) + " s";
    } catch (Throwable t) {
      String m = t.getMessage();
      return "e" + (m != null && m.length() > 0 ? m : t.toString());
    } finally {
      if (c != null) c.disconnect();
    }
  }

  /** Reads what is left of an answer, so its connection can be used again. */
  static void drain(HttpURLConnection c) {
    InputStream in = null;
    try {
      in = c.getInputStream();
    } catch (Throwable t) {
      in = c.getErrorStream();
    }
    if (in == null) return;
    try {
      byte[] buf = new byte[8192];
      while (in.read(buf) > 0) { }
    } catch (Throwable t) {
    } finally {
      try { in.close(); } catch (Throwable t) { }
    }
  }
}
