package org.retro;

import android.app.Activity;
import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import android.util.Log;
import java.lang.reflect.Method;

/** The app's background check (retro/bgcheck): a periodic job of the
 *  system's JobScheduler, run when there is a network and kept across
 *  reboots. The job loads the app's native library when this process has
 *  none yet and runs the check the app registered, on a thread of its own,
 *  with no window; android_glue.c starts the app's Nim side for it when no
 *  activity has. Nim schedules it with `schedule` (through RetroNative);
 *  while there is no activity the native side reaches the Java parts
 *  through `uirelaysCall`, with the application's Context in the
 *  activity's place. In the manifest with `retroapk --background`. */
public class RetroBackground extends JobService {
  static final int JOB = 0x52657472;           // "Retr": the app's one check
  static volatile Context app;                 // the application's Context

  static native int nativeCheck(String dataDir);

  @Override
  public boolean onStartJob(final JobParameters params) {
    app = getApplicationContext();
    final String dir = getFilesDir().getAbsolutePath();   // (as NativeActivity's internalDataPath)
    // (onStartJob must answer at once: the check runs on a thread with a
    // real stack, as the app's own thread has)
    Thread t = new Thread(null, new Runnable() {
      public void run() {
        try {
          System.loadLibrary("main");
          nativeCheck(dir);
        } catch (Throwable e) {
          Log.e("uirelays", "the background check failed", e);
        }
        jobFinished(params, false);
      }
    }, "retro-check", 8L << 20);
    t.start();
    return true;
  }

  @Override
  public boolean onStopJob(JobParameters params) {
    // (the system takes the job back: the network went, or it ran too
    // long; the next period runs it again)
    return false;
  }

  /** Runs the check every `minutes` (15 at the least), when there is a
   *  network, also after a reboot; 0 stops it. The same period asked again
   *  leaves the job as it is (the time already counted is kept). */
  public static boolean schedule(Context c, int minutes) {
    JobScheduler js = (JobScheduler) c.getSystemService(Context.JOB_SCHEDULER_SERVICE);
    if (js == null) return false;
    if (minutes <= 0) {
      js.cancel(JOB);
      return true;
    }
    long every = Math.max(15, minutes) * 60000L;
    for (JobInfo j : js.getAllPendingJobs()) {
      if (j.getId() == JOB && j.isPeriodic() && j.getIntervalMillis() == every && j.isPersisted())
        return true;
    }
    JobInfo job = new JobInfo.Builder(JOB, new ComponentName(c, RetroBackground.class))
        .setPeriodic(every)
        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
        .setPersisted(true)
        .build();
    return js.schedule(job) == JobScheduler.RESULT_SUCCESS;
  }

  /** The native side's calls while there is no activity: "native.what"
   *  (retro/native) with the application's Context as the activity, and
   *  "part.what" to the parts that need no activity (RetroNet: retro/http);
   *  UTF-8 text out, null when it failed. Any thread. */
  public static byte[] uirelaysCall(String name, String arg) {
    try {
      Context c = app;
      int dot = name.indexOf('.');
      if (c == null || dot <= 0) return null;
      String part = name.substring(0, dot);
      String what = name.substring(dot + 1);
      String[] a = arg.split("\t", -1);
      String r;
      if (part.equals("native")) {
        try {
          r = RetroNative.dispatch(c, what, a);
        } catch (Throwable t) {
          String m = t.getMessage();
          r = "e" + t.getClass().getSimpleName() + (m != null ? ": " + m : "");
        }
      } else {
        Class<?> k = Class.forName("org.retro.Retro" +
            Character.toUpperCase(part.charAt(0)) + part.substring(1));
        Method m = k.getMethod("call", Activity.class, String.class, String[].class);
        r = (String) m.invoke(null, new Object[] {null, what, a});
      }
      return r == null ? null : r.getBytes("UTF-8");
    } catch (Throwable t) {
      return null;
    }
  }
}
