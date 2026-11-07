#> shot("w-shares")
import retroui

var first = "Maryam"
var last = "Al Balushi"

app "Widths", 358, 80:
  row([50, -1, -2]):    # -1 and -2: one share and two shares of the rest
    label "&Name:"
    mark "50"
    edit first
    mark "-1"
    edit last
    mark "-2"
