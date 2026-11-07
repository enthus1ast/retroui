#> shot("w-spring")
import retroui

app "Widths", 360, 80:
  row:
    button "&Help"
    spring()            # what follows goes to the right end
    button("OK", isDefault = true)
    button "Cancel"
