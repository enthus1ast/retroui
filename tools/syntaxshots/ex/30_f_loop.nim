#> clickMark(1)
#> shot("f-loop")
import retroui

var people = @["Maryam", "Ahmed", "Salim"]
var chosen = ""

app "People", 300, 170:
  for i, p in people:
    withId(i):                    # row i's controls get ids of their own
      row([-1, 0]):
        label p
        if button("&Delete"): chosen = p
        mark "del"
  label "Clicked: " & chosen
