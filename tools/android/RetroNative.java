package org.retro;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.HashMap;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Any Java API from Nim, by reflection (retro/native): static methods and
 *  fields, methods of the activity or of objects kept here for the native
 *  side (handles), constructors. The activity dispatches "native.what"
 *  calls here.
 *
 *  Arguments come escaped (backslash, \t, \n, \r, \0) and typed by their
 *  first letter: s string, i int, l long, d double, f float, b boolean
 *  (b1 / b0), n null, a the activity, o an object handle. Results: s text,
 *  n nothing, h a handle, e an error message. */
public class RetroNative {
  private static final HashMap<Integer, Object> objects = new HashMap<Integer, Object>();
  private static int nextId = 1;

  static synchronized int keep(Object o) {
    int id = nextId++;
    if (nextId > 1000000000) nextId = 1;
    objects.put(id, o);
    return id;
  }

  static synchronized Object get(int id) { return objects.get(id); }

  static synchronized void drop(int id) { objects.remove(id); }

  static synchronized int count() { return objects.size(); }

  static String unescape(String s) {
    if (s.indexOf('\\') < 0) return s;
    StringBuilder b = new StringBuilder(s.length());
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      if (c == '\\' && i + 1 < s.length()) {
        char n = s.charAt(++i);
        switch (n) {
          case 't': b.append('\t'); break;
          case 'n': b.append('\n'); break;
          case 'r': b.append('\r'); break;
          case '0': b.append('\0'); break;
          default: b.append(n);
        }
      } else b.append(c);
    }
    return b.toString();
  }

  /** A typed argument. */
  static final class Arg {
    char kind;
    String text;
    long whole;
    double real;
    Object obj;
  }

  static Arg parse(String t, Object activity) {
    Arg a = new Arg();
    a.kind = t.length() > 0 ? t.charAt(0) : 'n';
    String v = t.length() > 0 ? t.substring(1) : "";
    switch (a.kind) {
      case 's': a.text = v; break;
      case 'i': case 'l': a.whole = Long.parseLong(v); break;
      case 'd': case 'f': a.real = Double.parseDouble(v); break;
      case 'b': a.whole = v.equals("1") ? 1 : 0; break;
      case 'a': a.obj = activity; break;
      case 'o': a.obj = get(Integer.parseInt(v)); break;
      default: a.kind = 'n';
    }
    return a;
  }

  /** How well `a` fits a parameter of type `t`: -1 not at all, 0 exactly,
   *  more for widening; `out[0]` gets the value to pass. */
  static int fit(Class<?> t, Arg a, Object[] out) {
    switch (a.kind) {
      case 'n':
        if (t.isPrimitive()) return -1;
        out[0] = null;
        return 1;
      case 's':
        if (t == String.class || t == CharSequence.class) { out[0] = a.text; return 0; }
        if (t == Object.class) { out[0] = a.text; return 2; }
        if ((t == char.class || t == Character.class) && a.text.length() == 1) {
          out[0] = a.text.charAt(0);
          return 1;
        }
        return -1;
      case 'i': case 'l': {
        long v = a.whole;
        boolean small = a.kind == 'i';
        if (small && (t == int.class || t == Integer.class) &&
            v >= Integer.MIN_VALUE && v <= Integer.MAX_VALUE) { out[0] = (int) v; return 0; }
        if (t == long.class || t == Long.class) { out[0] = v; return small ? 1 : 0; }
        if (small && (t == short.class || t == Short.class) &&
            v >= Short.MIN_VALUE && v <= Short.MAX_VALUE) { out[0] = (short) v; return 3; }
        if (small && (t == byte.class || t == Byte.class) &&
            v >= Byte.MIN_VALUE && v <= Byte.MAX_VALUE) { out[0] = (byte) v; return 4; }
        if (t == float.class || t == Float.class) { out[0] = (float) v; return 5; }
        if (t == double.class || t == Double.class) { out[0] = (double) v; return 5; }
        if (t == Object.class || t == Number.class) {
          out[0] = small && v >= Integer.MIN_VALUE && v <= Integer.MAX_VALUE ? (Object) (int) v : (Object) v;
          return 6;
        }
        return -1;
      }
      case 'd': case 'f':
        if (a.kind == 'f' && (t == float.class || t == Float.class)) { out[0] = (float) a.real; return 0; }
        if (t == double.class || t == Double.class) { out[0] = a.real; return a.kind == 'd' ? 0 : 1; }
        if (t == float.class || t == Float.class) { out[0] = (float) a.real; return 2; }
        if (t == Object.class || t == Number.class) { out[0] = a.real; return 6; }
        return -1;
      case 'b':
        if (t == boolean.class || t == Boolean.class) { out[0] = a.whole == 1; return 0; }
        if (t == Object.class) { out[0] = a.whole == 1; return 6; }
        return -1;
      default: {                       // 'a', 'o'
        Object o = a.obj;
        if (o == null) {
          if (t.isPrimitive()) return -1;
          out[0] = null;
          return 1;
        }
        if (t.isInstance(o)) { out[0] = o; return t == o.getClass() ? 0 : 1; }
        if (t.isPrimitive()) {
          Class<?> boxed = t == int.class ? Integer.class : t == long.class ? Long.class :
              t == boolean.class ? Boolean.class : t == double.class ? Double.class :
              t == float.class ? Float.class : t == char.class ? Character.class :
              t == short.class ? Short.class : Byte.class;
          if (boxed.isInstance(o)) { out[0] = o; return 1; }
        }
        return -1;
      }
    }
  }

  /** The values for `types`, or null when `args` do not fit; `score[0]` gets
   *  how far from exact they are. */
  static Object[] convert(Class<?>[] types, Arg[] args, int[] score) {
    if (types.length != args.length) return null;
    Object[] vals = new Object[args.length];
    Object[] one = new Object[1];
    int total = 0;
    for (int i = 0; i < args.length; i++) {
      int s = fit(types[i], args[i], one);
      if (s < 0) return null;
      total += s;
      vals[i] = one[0];
    }
    score[0] = total;
    return vals;
  }

  static Class<?> classOf(String name) throws ClassNotFoundException {
    switch (name) {
      case "int": return int.class;
      case "long": return long.class;
      case "boolean": return boolean.class;
      case "double": return double.class;
      case "float": return float.class;
      default: return Class.forName(name);
    }
  }

  /** Calls `member` of `target` (or of the class `cls`, static) with `args`;
   *  without a method of that name, reads (no argument) or writes (one) the
   *  field of that name. */
  static Object invoke(Class<?> cls, Object target, String member, Arg[] args,
                       boolean[] isVoid) throws Exception {
    Method best = null;
    Object[] bestVals = null;
    int bestScore = Integer.MAX_VALUE;
    int[] score = new int[1];
    for (Method m : cls.getMethods()) {
      if (!m.getName().equals(member)) continue;
      if (target == null && !Modifier.isStatic(m.getModifiers())) continue;
      Object[] vals = convert(m.getParameterTypes(), args, score);
      if (vals != null && score[0] < bestScore) {
        best = m;
        bestVals = vals;
        bestScore = score[0];
      }
    }
    if (best != null) {
      isVoid[0] = best.getReturnType() == void.class;
      if (target != null) best = publicMethod(best);
      try {
        return best.invoke(target, bestVals);
      } catch (InvocationTargetException e) {
        Throwable c = e.getCause();
        throw c instanceof Exception ? (Exception) c : new Exception(String.valueOf(c));
      }
    }
    Field f;
    try {
      f = cls.getField(member);
    } catch (NoSuchFieldException e) {
      throw new NoSuchMethodException(cls.getName() + "." + member + " with " +
                                      args.length + " argument(s) that fit");
    }
    if (args.length == 0) return f.get(target);
    if (args.length == 1) {
      Object[] one = new Object[1];
      if (fit(f.getType(), args[0], one) < 0)
        throw new IllegalArgumentException("the value does not fit " + member);
      f.set(target, one[0]);
      isVoid[0] = true;
      return null;
    }
    throw new NoSuchMethodException(cls.getName() + "." + member);
  }

  /** `m` as a public class or interface declares it: objects the system
   *  hands out are often of private classes (a vibrator, a window) whose
   *  own methods may not be called by reflection, while the same method of
   *  their public type may. */
  static Method publicMethod(Method m) {
    if (Modifier.isPublic(m.getDeclaringClass().getModifiers())) return m;
    Class<?>[] p = m.getParameterTypes();
    for (Class<?> c = m.getDeclaringClass(); c != null; c = c.getSuperclass()) {
      if (Modifier.isPublic(c.getModifiers())) {
        try { return c.getMethod(m.getName(), p); } catch (NoSuchMethodException e) { }
      }
      for (Class<?> i : c.getInterfaces()) {
        if (Modifier.isPublic(i.getModifiers())) {
          try { return i.getMethod(m.getName(), p); } catch (NoSuchMethodException e) { }
        }
      }
    }
    return m;
  }

  static Object construct(Class<?> cls, Arg[] args) throws Exception {
    Constructor<?> best = null;
    Object[] bestVals = null;
    int bestScore = Integer.MAX_VALUE;
    int[] score = new int[1];
    for (Constructor<?> c : cls.getConstructors()) {
      Object[] vals = convert(c.getParameterTypes(), args, score);
      if (vals != null && score[0] < bestScore) {
        best = c;
        bestVals = vals;
        bestScore = score[0];
      }
    }
    if (best == null)
      throw new NoSuchMethodException("new " + cls.getName() + " with " + args.length +
                                      " argument(s) that fit");
    try {
      return best.newInstance(bestVals);
    } catch (InvocationTargetException e) {
      Throwable c = e.getCause();
      throw c instanceof Exception ? (Exception) c : new Exception(String.valueOf(c));
    }
  }

  static boolean isText(Object r) {
    return r instanceof String || r instanceof Number || r instanceof Boolean ||
           r instanceof Character;
  }

  static String encode(Object r, boolean handle, boolean isVoid) {
    if (r == null) return "n";
    if (handle && !isVoid) return "h" + keep(r);
    return "s" + String.valueOf(r);
  }

  /** On the UI thread (views, toasts, windows), waiting for the answer. */
  static Object onUi(android.app.Activity a, final Callable<Object> job) throws Exception {
    if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) return job.call();
    final Object[] box = new Object[1];
    final Throwable[] err = new Throwable[1];
    final CountDownLatch done = new CountDownLatch(1);
    a.runOnUiThread(new Runnable() {
      public void run() {
        try { box[0] = job.call(); } catch (Throwable t) { err[0] = t; }
        done.countDown();
      }
    });
    if (!done.await(10, TimeUnit.SECONDS)) throw new Exception("the UI thread did not answer");
    if (err[0] != null)
      throw err[0] instanceof Exception ? (Exception) err[0] : new Exception(String.valueOf(err[0]));
    return box[0];
  }

  /** The entry point: what = static | method | new | release | count | ping. */
  public static String call(android.app.Activity a, String what, String[] raw) {
    try {
      return dispatch(a, what, raw);
    } catch (Throwable t) {
      String m = t.getMessage();
      return "e" + t.getClass().getSimpleName() + (m != null ? ": " + m : "");
    }
  }

  /** `call` without the Android types in its way (also run by tests on a
   *  desktop Java). */
  public static String dispatch(final Object activity, String what, String[] raw) throws Exception {
    final String[] u = new String[raw.length];
    for (int i = 0; i < raw.length; i++) u[i] = unescape(raw[i]);
    if (what.equals("ping")) return "s1";
    if (what.equals("count")) return "s" + count();
    if (what.equals("release")) {
      for (String s : u) if (s.length() > 0) drop(Integer.parseInt(s));
      return "n";
    }
    // static: class, member, flags, args...   method: target, member, flags, args...
    // new: class, flags, args...
    final int first = what.equals("new") ? 2 : 3;
    if (u.length < first) throw new IllegalArgumentException("too few fields");
    final String flags = u[first - 1];
    final Arg[] args = new Arg[u.length - first];
    for (int i = first; i < u.length; i++) args[i - first] = parse(u[i], activity);
    final boolean handle = flags.indexOf('h') >= 0;
    final boolean[] isVoid = new boolean[1];
    Callable<Object> job;
    if (what.equals("static")) {
      final Class<?> cls = classOf(u[0]);
      final String member = u[1];
      job = new Callable<Object>() {
        public Object call() throws Exception { return invoke(cls, null, member, args, isVoid); }
      };
    } else if (what.equals("method")) {
      final Object target = u[0].equals("a") ? activity :
          u[0].startsWith("o") ? get(Integer.parseInt(u[0].substring(1))) : null;
      if (target == null) throw new IllegalArgumentException("no object " + u[0]);
      final String member = u[1];
      job = new Callable<Object>() {
        public Object call() throws Exception {
          return invoke(target.getClass(), target, member, args, isVoid);
        }
      };
    } else if (what.equals("new")) {
      final Class<?> cls = classOf(u[0]);
      job = new Callable<Object>() {
        public Object call() throws Exception { return construct(cls, args); }
      };
    } else throw new IllegalArgumentException("no such call: " + what);
    Object r = flags.indexOf('u') >= 0 && activity instanceof android.app.Activity
        ? onUi((android.app.Activity) activity, job) : job.call();
    return encode(r, handle || what.equals("new"), isVoid[0]);
  }
}
