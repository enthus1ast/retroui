#> shot("f-form")
#> phone(250, 270)
#> shot("f-form-phone")
import retroui

var name = "Maryam Al Balushi"
var phone = "+968 9123 4567"
var active = true

app "Form", 360, 130:
  form(70):                       # captions in a 70-pixel column
    field("&Name:"): edit name
    field("&Phone:"): edit phone
    field(""): checkbox("&Active", active)
