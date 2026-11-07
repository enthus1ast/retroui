#> key(KeyF, {AltPressed})
#> shot("f-menus")
import retroui

var chosen = ""

app "Menus", 320, 150:
  menubar:
    menu "&File":
      if menuItem("&Open...", "Ctrl+O"): chosen = "Open"
      if menuItem("&Save", "Ctrl+S"): chosen = "Save"
      menuSeparator()
      if menuItem("E&xit"): quitApp()
    menu "&Help":
      if menuItem("&About Menus..."): chosen = "About"
  label chosen
