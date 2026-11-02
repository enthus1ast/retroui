package org.retro;

import android.app.Activity;
import android.content.Context;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;
import android.print.PrintManager;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

/** Printing for retro's report module (src/retro/report.nim). The native
 *  side calls "print.what" with tab-separated arguments:
 *  "print.pdf" path, job name [, page count] opens Android's print dialog
 *  (the printers it knows, Save as PDF) for that PDF file, which is handed
 *  to the print system as it is; "print.available" says whether this
 *  device can print at all. */
public class RetroPrint {
  public static String call(final Activity a, String what, final String[] args) throws Exception {
    if (what.equals("available")) return Build.VERSION.SDK_INT >= 19 ? "1" : "0";
    if (what.equals("pdf")) {
      if (Build.VERSION.SDK_INT < 19 || args.length < 1 || args[0].length() == 0) return null;
      final String path = args[0];
      if (!new File(path).canRead()) return null;
      final String job = args.length > 1 && args[1].length() > 0 ? args[1] : new File(path).getName();
      int pages = PrintDocumentInfo.PAGE_COUNT_UNKNOWN;
      if (args.length > 2) {
        try { pages = Math.max(1, Integer.parseInt(args[2].trim())); } catch (Throwable t) { }
      }
      final int pageCount = pages;
      a.runOnUiThread(new Runnable() {
        public void run() {
          try {
            PrintManager pm = (PrintManager) a.getSystemService(Context.PRINT_SERVICE);
            pm.print(job, new PdfAdapter(path, job, pageCount), new PrintAttributes.Builder().build());
          } catch (Throwable t) { }
        }
      });
      return "1";
    }
    return null;
  }

  /** Hands a PDF file to the print system, as it is. */
  static class PdfAdapter extends PrintDocumentAdapter {
    final String path, job;
    final int pages;

    PdfAdapter(String path, String job, int pages) {
      this.path = path;
      this.job = job;
      this.pages = pages;
    }

    @Override
    public void onLayout(PrintAttributes oldAttrs, PrintAttributes newAttrs, CancellationSignal cancel,
                         LayoutResultCallback cb, Bundle extras) {
      if (cancel.isCanceled()) {
        cb.onLayoutCancelled();
        return;
      }
      String name = job.toLowerCase().endsWith(".pdf") ? job : job + ".pdf";
      PrintDocumentInfo info = new PrintDocumentInfo.Builder(name)
          .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
          .setPageCount(pages)
          .build();
      cb.onLayoutFinished(info, oldAttrs == null || !newAttrs.equals(oldAttrs));
    }

    @Override
    public void onWrite(PageRange[] ranges, ParcelFileDescriptor dest, CancellationSignal cancel,
                        WriteResultCallback cb) {
      InputStream in = null;
      OutputStream out = null;
      try {
        in = new FileInputStream(path);
        out = new FileOutputStream(dest.getFileDescriptor());
        byte[] buf = new byte[64 * 1024];
        int n;
        while ((n = in.read(buf)) > 0) {
          if (cancel.isCanceled()) {
            cb.onWriteCancelled();
            return;
          }
          out.write(buf, 0, n);
        }
        out.flush();
        cb.onWriteFinished(new PageRange[] { PageRange.ALL_PAGES });
      } catch (Throwable t) {
        cb.onWriteFailed(t.toString());
      } finally {
        try { if (in != null) in.close(); } catch (Throwable t) { }
        try { if (out != null) out.close(); } catch (Throwable t) { }
      }
    }
  }
}
