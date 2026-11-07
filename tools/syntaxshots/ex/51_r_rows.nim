#> shot("r-rows")
import retroui

app "Rows", 360, 160:
  row:                            # no widths: the col takes all the room
    label "1."
    col:
      label "Maryam Al Balushi"
      label "+968 9123 4567"
    button "&Call"
  row([24, -1, 0]):               # widths: the button keeps its place
    label "2."
    col:
      label "Ahmed Al Harthy"
      label "+968 9988 7766"
    button "C&all"
