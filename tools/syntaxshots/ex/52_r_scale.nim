#> shot("r-scale")
import retroui

var a = "Sohar"
var b = "Sohar"

app "Scale", 380, 100:
  row([80, -1]):                  # right: 80 design pixels
    label "&City:"
    edit a
  row([dp(80), -1]):              # wrong: scaled twice
    label "C&ity:"
    edit b
