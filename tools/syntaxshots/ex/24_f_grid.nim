#> clickMark(0, 0.2, 0.02)
#> shot("f-grid")
import retroui

var cols = @[Column(title: "Name", width: 110), Column(title: "City", width: 100)]
var people = @[@["Salim", "Nizwa"], @["Maryam", "Sohar"], @["Aisha", "Sur"], @["Ahmed", "Muscat"]]
var sel = 0

proc cellOf(row, col: int): string = people[row][col]   # asked only for rows on screen

app "Event object", 300, 160:
  let ev = grid(cols, people.len, cellOf, sel, height = 5)
  mark "grid"
  if ev.sorted:                   # the header was clicked
    sortRows(people, ev.sortColumn, ev.sortDescending)
