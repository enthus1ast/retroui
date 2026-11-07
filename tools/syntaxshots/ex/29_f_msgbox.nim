#> key(KeyX, {AltPressed})
#> shot("f-msgbox")
import retroui

var askExit = false
var answer = ""

app "Notepad", 400, 170:
  if button("E&xit"): askExit = true
  label answer
  case msgBox(askExit, "Notepad", "Save the changes?", ["&Yes", "&No", "Cancel"], miQuestion)
  of 1: answer = "Yes"            # the number of the button chosen
  of 2: answer = "No"
  of 3: answer = "Cancel"
  else: discard                   # 0: still open, or never opened
