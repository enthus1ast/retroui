#> shot("w-plain")
import retroui

app "Widths", 320, 130:
  row:                  # no widths: each its own width, wrapping when full
    button "&New"
    button "&Open..."
    button "&Save"
    button "&Print..."
    button "Cu&t"
    button "&Copy"
    button "&Paste"
