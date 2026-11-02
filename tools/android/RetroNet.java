package org.retro;

import android.app.Activity;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/** Downloads for retro's asset store (src/retro/assetfetch.nim). The
 *  native side calls "net.what" with tab-separated arguments, from any
 *  thread (its download workers):
 *  "net.download" url, dest, user agent, timeout in ms[, headers] downloads
 *  url into the file dest (through dest + ".part", renamed when whole) and
 *  answers "1", or "e" and what went wrong. Headers ("Name: value", split
 *  by "\r": an API's key) go only to the address's own host. Redirects are followed by hand, also
 *  from http to https and back, which HttpURLConnection does not do.
 *  "net.available" answers "1". */
public class RetroNet {
  public static String call(Activity a, String what, String[] args) {
    if (what.equals("available")) return "1";
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
}
