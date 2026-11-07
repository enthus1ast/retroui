#> key(KeyS, {CtrlPressed})
#> shot("f-shortcut")
import retroui

var said = ""

app "Shortcut", 320, 100:
  menubar:
    menu "&File":
      if menuItem("&Save", "Ctrl+S"): said = "Saved from the menu"   # "Ctrl+S" is only shown
  if hotkeyPressed("Ctrl+S"): said = "Saved with Ctrl+S"             # this reads the key
  label said
