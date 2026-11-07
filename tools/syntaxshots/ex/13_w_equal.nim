#> shot("w-equal")
import retroui

app "Widths", 356, 80:
  row([-1, -1, -1]):    # three equal shares
    button "< &Back"
    mark "-1"
    button "&Next >"
    mark "-1"
    button "&Finish"
    mark "-1"
