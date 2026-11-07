#> key(KeyS, {AltPressed})
#> key(KeyS, {AltPressed})
#> shot("f-action")
import retroui

var saved = 0

app "Action", 320, 110:
  row:
    if button("&Save"): inc saved     # Alt+S or a click
    if button("E&xit"): quitApp()     # Alt+X
  label "Saved " & $saved & " times"
