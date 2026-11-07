#> shot("w-wrap")
import retroui

var name = "Maryam"
var phone = "+968 9123 4567"

app "Widths", 320, 110:
  row([50, -1]):        # four controls, two widths: two lines
    label "&Name:"
    mark "50"
    edit name
    mark "-1"
    label "&Phone:"
    edit phone
