#> shot("w-fixed")
import retroui

var name = "Maryam"

app "Widths", 320, 80:
  row([50, -1]):        # 50: a fixed column; -1: all the width left
    label "&Name:"
    mark "50"
    edit name
    mark "-1"
