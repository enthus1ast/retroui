#> shot("f-time")
import std/times
import retroui

app "Clock", 220, 70:
  label now().format("HH:mm:ss"), bold = true
  wakeIn(1000)                    # one more frame in a second
