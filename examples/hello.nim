## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import retro

var name = "World"
var greeted = ""

app "Hello", 320, 120:
  row([50, -1]):
    label "&Name:"
    edit name
  row:
    if button("&Greet", isDefault = true):
      greeted = "Hello, " & name & "!"
    if button("E&xit"): quitApp()
  label greeted
