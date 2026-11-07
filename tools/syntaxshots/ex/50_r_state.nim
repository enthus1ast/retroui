#> key(KeyK, {AltPressed})
#> key(KeyL, {AltPressed})
#> shot("r-state")
import retroui

var kept = false                  # outside the block: kept

app "State", 300, 90:
  var lost = false                # inside: made again every frame
  checkbox("&Kept (declared outside)", kept)
  checkbox("&Lost (declared inside)", lost)
