#> key(KeyEnter)
#> shot("hello")
import retroui

var name = "World"          # state: your own variables
var greeted = ""

app "Hello", 320, 130:      # a window; the block runs every frame
  row([50, -1]):            # side by side: 50 pixels, then the rest
    label "&Name:"
    edit name               # bound to `name`: typing changes it
  row:
    if button("&Greet", isDefault = true):   # true on the frame it is clicked
      greeted = "Hello, " & name & "!"
    if button("E&xit"): quitApp()
  label greeted
