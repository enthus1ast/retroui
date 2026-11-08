#> shot("f-web")
import retroui

var said = "nothing yet"

app "Web page", 340, 200:
  row:
    if button("&Greet"): webPost("order", "Hello")   # a retro event in the page
    label "The page said: " & said
  let page = webView("html:<h3>Order 1042</h3><p>Ready to <b>ship</b>.</p>" &
                     "<script>retro.post('loaded')</script>",
                     key = "order", engine = weSystem)   # the room left
  mark "page"
  for m in page.messages: said = m              # retro.post(text) in the page
