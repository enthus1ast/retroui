#> shot("c-save-before")
#> key(KeyTab)
#> typeText("Dear Maryam,")
#> shot("c-save-after")
import retroui

var text = ""
var dirty = false

app "Editor", 300, 110:
  if edit(text): dirty = true
  row:
    if button("&Save", enabled = dirty): dirty = false
