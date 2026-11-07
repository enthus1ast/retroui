#> key(KeyO, {AltPressed})
#> shot("f-dialog")
import retroui

var showOptions = false
var autosave = true
var keepCopies = false

app "Dialog", 380, 200:
  if button("&Options..."): showOptions = true
  dialog(showOptions, "Options", 240):    # shown while showOptions is true
    checkbox("&Save by itself", autosave)
    checkbox("&Keep old copies", keepCopies)
    row:
      spring()
      if button("OK", isDefault = true): showOptions = false
      if button("Cancel"): showOptions = false
