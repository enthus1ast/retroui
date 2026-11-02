## The app the fake Android (mock_android.c) drives. Build with run.sh.

{.compile: "mock_android.c".}

import retro
import retro/uirelays/drivers/android_driver

# The fake Android's relays, in place of the desktop driver's.
initAndroidDriver()

var
  clicks = 0
  name = "abc"
  wasPaused = false

app "mock", 300, 200:
  if button("Press me"):
    inc clicks
    echo "clicked ", clicks
  edit name
  if name.len == 0 and clicks > 0: echo "typed hi"
  if name == "سلام":
    echo "arabic ok"
    name = "done"
  label "Arabic: مرحبا"
  if ui.paused and not wasPaused: echo "paused"
  wasPaused = ui.paused
