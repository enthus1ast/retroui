#> shot("w-own")
import retroui

var path = "Documents/Budget.csv"

app "Widths", 360, 80:
  row([50, -1, 0]):     # 0: the control's own width
    label "&File:"
    mark "50"
    edit path
    mark "-1"
    button "&Browse"
    mark "0"
