# uirelays in retro

`src/retro/uirelays` is [uirelays](https://github.com/nim-lang/uirelays)
with my changes for phones, tablets, pens and the GPU, so retro needs no
other package. Import it as `retro/uirelays`.

It is the same code as `src/uirelays` on the **`uirelays` branch** of this
repository: upstream's history up to the commit in `VERSION`, then my
commits on top, ready to go upstream as a pull request. Nothing in it
knows about retro -- it stays a library for any Nim program.

## Keeping the two the same

    tools/uirelays.sh push "X11: what changed"   # src/retro/uirelays -> a commit on the branch
    tools/uirelays.sh pull                       # the branch -> src/retro/uirelays
    tools/uirelays.sh diff                       # what differs between them

## Sending it upstream

    git push https://github.com/foxoman/uirelays.git uirelays:android-ios-pens-gpu

then open the pull request on nim-lang/uirelays from that branch; its text
is in `docs/uirelays-pr.md`.

## What it adds to upstream

- `drivers/android_driver.nim`, `drivers/android_glue.c` -- Android: a
  NativeActivity, the app on its own thread, input through the activity's
  input queue (touch, mouse, pens, two-finger gestures, keys with the
  keyboard's own characters), the frame put in the window with
  `ANativeWindow_lock`, clipboard, links, system-font text (Arabic shaped),
  OpenGL ES through EGL. `drivers/android/UiRelaysActivity.java` is an
  optional activity for text without key codes, the keyboard, insets and the
  system bars; retro's own is `tools/android/RetroActivity.java`, which also
  answers `uirelaysCall` (documents of other apps, media, printing...).
- `drivers/uikit_driver.nim`, `drivers/uikit_backend.m` -- iOS with UIKit.
- `drivers/surface_driver.nim` -- the relays both phone drivers share.
- `services.nim` -- `systemRelays`: data folder, links, files, places,
  storage access, photo decoding, `systemCall`.
- `eglload.nim` -- EGL loaded at run time; `gpuRelays` in `screen.nim`.
- `drivers/penaxes.nim` -- a pen's pressure, lean and turn from what each
  system reports.
- `input.nim`, `screen.nim`: more keys, the mouse's side buttons,
  `hasMods`, pens, `AppPauseEvent` / `AppResumeEvent`, `GestureEvent`, the
  safe area and `touch`, diagonal and move cursors, `pointerHeight`.
- Driver fixes: WinAPI (Alt shortcuts, mouse capture, signed coordinates,
  surrogate pairs, the client size), X11 (the scale without `Xft.dpi`, only
  the pictures' part copied), SDL3 (safe area, text input on demand,
  TTF_SetFontStyle linked).
