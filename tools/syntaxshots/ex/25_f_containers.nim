#> shot("f-containers")
import retroui

var page = 0
var street = "Al Hamra Street"
var city = "Sohar"

app "Containers", 400, 256:
  row([-1, -1]):
    card "Sales":
      label "12,400 OMR"
    card "Orders":
      label "86 this month"
  tabs(page, ["&General", "&Advanced"]):   # bound to `page`
    if page == 0:
      group "Address":
        row([50, -1]):
          label "&Street:"
          edit street
          label "&City:"
          edit city
    else:
      label "The Advanced page."
  panel(60):
    label "A panel: a framed page that scrolls when it is taller."
