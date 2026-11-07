#> key(KeyTab)
#> key(KeyEnd)
#> typeText(" Al Balushi")
#> shot("f-binding")
import retroui

var name = "Maryam"
var bold = true

app "Binding", 320, 110:
  edit name                       # shows `name`; typing changes it
  checkbox("&Bold", bold)         # shows `bold`; a click flips it
  label "name = " & name & ", bold = " & $bold
