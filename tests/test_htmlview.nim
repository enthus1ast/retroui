## HTML read into Markdown and shown, and web pages: the kit's own reader
## on the desktop, the system's WebView on Android (here through a fake
## `systemRelays.call` that records what the app asks of it).

import std/[os, strutils, times, monotimes]
import retroui
import retroui/htmlview
import retroui/uirelays/[input, services]
import harness

fakeDriver()
startApp("html", W, H)

proc md(h: string): string = htmlToMarkdown(h)

# ---- the reader ------------------------------------------------------------------------------

block constructs:
  doAssert md("<h1>Title</h1><h3>Sub</h3>") == "# Title\n\n### Sub"
  doAssert md("<p>One</p><p>Two</p>") == "One\n\nTwo"
  doAssert md("<p>a <b>bold</b> <strong>s</strong> <i>it</i> <em>e</em></p>") ==
    "a <b>bold</b> <b>s</b> <i>it</i> <i>e</i>"
  doAssert md("<p><u>u</u><s>s</s><del>d</del><code>c</code><kbd>k</kbd><mark>m</mark></p>") ==
    "<u>u</u><s>s</s><s>d</s><code>c</code><code>k</code><mark>m</mark>"
  doAssert md("<p>x<br>y</p>") == "x<br>y"
  doAssert md("<p>a</p><hr><p>b</p>") == "a\n\n---\n\nb"
  # what Markdown would read as markup stays text
  doAssert md("<p># not a heading * not em _ [x](y) | 1. </p>") ==
    "\\# not a heading \\* not em \\_ \\[x\\]\\(y\\) \\| 1\\."
  # entities, numeric too; white space collapsed
  doAssert md("<p>&lt;b&gt; &amp; &copy; &#169; &#xA9; &nbsp;x   \n  y</p>") ==
    "\\<b\\> \\& © © ©  x y"
  doAssert decodeEntities("&#0;&#x110000;&#xD800;&bogus;&amp") == "���&bogus;&"
  # links: javascript is not a link; brackets and pipes in addresses are made harmless
  doAssert md("<a href=\"page.html\">Next</a>") == "[Next](<page.html>)"
  doAssert md("<a href=\"javascript:alert(1)\">Bad</a>") == "Bad"
  doAssert md("<a href=\" JaVa\tScRiPt:x\">Bad</a>") == "Bad"
  doAssert md("<a href=\"a(1)|b.html\">L</a>") == "[L](<a%281%29%7Cb.html>)"
  doAssert md("<a href=\"x\"></a>") == "[x](<x>)", "a link without words: its address"
  doAssert md("<img src=\"pic.png\" alt=\"A pic\">") == "![A pic](<pic.png>)"
  doAssert md("<img alt=\"no src\">") == "no src"
  # lists
  doAssert md("<ul><li>one<li>two</ul>") == "- one\n- two"
  doAssert md("<ol start=\"3\"><li>a</li><li>b</li></ol>") == "3. a\n4. b"
  doAssert md("<ul><li>a<ul><li>b</li></ul></li></ul>") == "- a\n\n  - b"
  doAssert md("<blockquote><p>q</p><p>r</p></blockquote>") == "> q\n>\n> r"
  doAssert md("<pre>a\n  b &lt;c&gt;</pre>") == "```\na\n  b <c>\n```"
  doAssert md("<pre><code class=\"language-nim\">echo 1</code></pre>") ==
    "```nim\necho 1\n```"
  doAssert md("<pre>x ``` y</pre>") == "````\nx ``` y\n````", "a longer fence"
  doAssert md("<dl><dt>Term</dt><dd>Says</dd></dl>") ==
    "<b>Term</b>\n\n\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0Says"
  # tables: a header row of th, alignment, colspan, rows without th
  doAssert md("<table><tr><th>A</th><th align=right>B</th></tr>" &
              "<tr><td>1</td><td>2</td></tr><tr><td colspan=2>w</td></tr></table>") ==
    "| A | B |\n| --- | ---: |\n| 1 | 2 |\n| w |  |"
  doAssert md("<table><tr><td>1</td><td>2</td></tr></table>") ==
    "|  |  |\n| --- | --- |\n| 1 | 2 |", "no header row: an empty one"
  doAssert md("<table><caption>Cap</caption><tr><td>a<p>b</p></td></tr></table>") ==
    "<b>Cap</b>\n\n|  |\n| --- |\n| a<br>b |"
  # colors
  doAssert md("<p><span style=\"color: red\">r</span><font color=\"#00f\">b</font></p>") ==
    "<font color=\"#DC0000\">r</font><font color=\"#0000FF\">b</font>"
  # left out entirely: scripts, styles, forms, frames, the head
  doAssert md("<head><title>T</title><style>p{}</style></head><script>x<y</script>" &
              "<form>Name <input name=n><button>Go</button></form><iframe src=x>i</iframe>" &
              "<p>shown</p>") == "shown"
  doAssert htmlTitle("<html><head><title> My  &amp; page </title></head></html>") ==
    "My & page"
  # forgiving: unclosed and misnested tags, stray end tags, comments, CDATA
  doAssert md("<p>a<p>b") == "a\n\nb"
  doAssert md("<b><i>x</b></i> y</p></div>") == "<b><i>x</i></b> y"
  doAssert md("<!-- hidden --><p>v<!-- also --></p><![CDATA[<raw>]]>") == "v\n\n\\<raw\\>"
  doAssert md("a < b and c > d") == "a \\< b and c \\> d"
  doAssert md("<p>task <input type=checkbox checked> done</p>") == "task ☑ done"

block hostile:
  # deep nesting, a huge page, endless attributes: bounded, no crash
  let t0 = getMonoTime()
  var deep = ""
  for i in 0 ..< 20_000: deep.add "<div><b><ul><li>"
  deep.add "bottom"
  discard md(deep)
  var many = ""
  for i in 0 ..< 200_000: many.add "<b>"
  discard md(many)
  var big = newStringOfCap(5_000_000)
  while big.len < 5_000_000: big.add "<p>words &amp; <i>more</i> words</p>"
  let m = md(big)
  doAssert m.len < 7_000_000
  var attrs = "<p"
  for i in 0 ..< 10_000: attrs.add " a" & $i & "=\"" & repeat('x', 20) & "\""
  attrs.add ">ok</p>"
  doAssert md(attrs) == "ok"
  doAssert md("<p title='>unclosed") == ""
  doAssert md("<") == "\\<" and md("</") == "\\<\\/" and md("<!") == "" and
    md("&#") == "\\&\\#"
  let ms = (getMonoTime() - t0).inMilliseconds
  doAssert ms < 20_000, "hostile pages take " & $ms & " ms"
  # the Markdown side: thousands of unclosed tags and "<" do not make it slow
  var lt = repeat('<', 300_000)
  var tags = ""
  for i in 0 ..< 50_000: tags.add "<b>x"
  let t1 = getMonoTime()
  view = proc () =
    discard markdownView(lt, height = 200, key = "lt")
    discard markdownView(tags, height = 200, key = "tags")
  run(2)
  doAssert (getMonoTime() - t1).inMilliseconds < 20_000

# ---- shown -------------------------------------------------------------------------------------

proc px(x, y: int): uint32 = pixels[y * W + x] and 0xFFFFFF'u32

block htmlViewLinks:
  var ev: HtmlEvent
  var r: Rect
  view = proc () =
    let e = htmlView("<p><a href=\"next.html\">Next page</a> and <mark>marked</mark></p>" &
                     "<p><img src=\"missing.png\" alt=\"gone\"></p>", height = 200, key = "t")
    if e.link.len > 0: ev = e
    r = ui.lastRect
  run(3)
  # the link is the first words, at the padding
  let lx = r.x + 1 + dp(10) + 8
  let ly = r.y + 1 + dp(10) + FontH div 2
  down(lx, ly)
  run()
  up(lx, ly)
  run(2)
  doAssert ev.link == "next.html", "a link clicked: " & ev.link
  # <mark> highlights
  var yellow = false
  for y in r.y .. r.y + 60:
    for x in r.x .. r.x + r.w - 1:
      if px(x, y) == 0xFFF078: yellow = true
  doAssert yellow, "marked text has its highlight"
  # in the flow
  view = proc () =
    discard htmlBlock("<h2>Flow</h2><p>text</p>")
  run(2)

# ---- web pages on the desktop ---------------------------------------------------------------------

var opened: seq[string]
systemRelays.openUrl = proc (url: string): bool =
  opened.add url
  true

block webOnTheDesktop:
  let dir = getTempDir() / "retro-web-test"
  removeDir(dir)
  createDir(dir)
  writeFile(dir / "a.html", "<html><head><title>Page A</title></head><body>" &
            "<p><a href=\"b.html#top\">To B</a></p></body></html>")
  writeFile(dir / "b.html", "<title>Page B</title><p>B here <a href=\"https://nim-lang.org\">web</a></p>")
  var url = dir / "a.html"
  var ev: WebEvent
  var r: Rect
  view = proc () =
    ev = webView(url, height = 300, key = "desk")
    r = ui.lastRect
  run(3)
  doAssert ev.title == "Page A" and ev.url == dir / "a.html" and not ev.canGoBack
  let lx = r.x + 1 + dp(10) + 6
  let ly = r.y + 1 + dp(10) + FontH div 2
  down(lx, ly)
  run()
  up(lx, ly)
  run(3)
  doAssert ev.url == dir / "b.html", "a local link is followed: " & ev.url
  doAssert ev.title == "Page B" and ev.canGoBack
  # a link to the web goes to the browser
  let wx = r.x + 1 + dp(10) + textWidth("B here ") + 6
  down(wx, ly)
  run()
  up(wx, ly)
  run(2)
  doAssert opened == @["https://nim-lang.org"], $opened
  doAssert webGoBack("desk")
  run(2)
  doAssert ev.url == dir / "a.html" and not ev.canGoBack
  doAssert not webGoBack("desk")
  # file:// addresses, and html: text
  url = "file://" & dir / "b.html"
  run(2)
  doAssert ev.title == "Page B"
  url = "html:<title>Inline</title><p>hi</p>"
  run(2)
  doAssert ev.title == "Inline"
  # a page on the web: its address and a button for the browser
  opened.setLen(0)
  url = "https://example.com/some/page"
  run(3)
  var bx, by = -1
  # the button: the first long black line inside the frame (its top border)
  for y in r.y + 2 ..< r.y + r.h - 2:
    var run = 0
    for x in r.x + 2 ..< r.x + r.w - 2:
      if px(x, y) == 0x000000:
        inc run
        if run >= 100 and bx < 0:
          bx = x - run + 1
          by = y + 1
      else: run = 0
    if bx >= 0: break
  doAssert bx >= 0, "the button is there"
  down(bx + 20, by + 6)
  run()
  up(bx + 20, by + 6)
  run(2)
  doAssert opened == @["https://example.com/some/page"], $opened
  # a page not there
  url = dir / "nothing.html"
  run(2)
  removeDir(dir)

# ---- web pages on Android (the system's WebView, faked) ---------------------------------------------

var calls: seq[string]
var info = "https://a.example/\tA page\t40\t1\t0"
var backOk = "1"
systemRelays.call = proc (name, arg: string): string {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if name != "web.info": calls.add name & " " & arg
    case name
    of "web.info": info
    of "web.back": backOk
    else: ""

block webOnAndroid:
  useSystemWebView = true
  var shown = true
  var h = 200
  var dlg = false
  var ev: WebEvent
  var gotBack = false
  view = proc () =
    if shown:
      ev = webView("https://a.example/", height = h, key = "and")
      if ev.back: gotBack = true
    dialog(dlg, "Over it", 200):
      label "A dialog"
  calls.setLen(0)
  run(3)
  doAssert calls.len == 1 and calls[0].startsWith("web.show and\t"), $calls
  let p = calls[0].split('\t')
  doAssert p[^1] == "https://a.example/" and parseInt(p[3]) > 0 and parseInt(p[4]) == 200 * pxScale,
    $p
  doAssert ev.title == "A page" and ev.progress == 40 and ev.loading and ev.canGoBack
  # the same frame again: nothing to tell; a new place: moved
  calls.setLen(0)
  run(2)
  doAssert calls.len == 0, $calls
  h = 150
  run(2)
  doAssert calls.len == 1 and calls[0].startsWith("web.show and\t") and
           calls[0].split('\t')[4] == $(150 * pxScale), $calls
  # a dialog over it: hidden, then back
  calls.setLen(0)
  dlg = true
  run(3)
  doAssert "web.hide and" in calls, $calls
  calls.setLen(0)
  dlg = false
  run(3)
  doAssert calls.len >= 1 and calls[^1].startsWith("web.show and"), $calls
  # Back in the page with nowhere to go: reported once
  info = "https://a.example/b\tB\t100\t0\t1"
  ui.redraw = true
  harness.ticks += 1000
  run(2)
  doAssert ev.url == "https://a.example/b" and not ev.loading and gotBack
  # not drawn any more: hidden by the frame after
  calls.setLen(0)
  shown = false
  run(3)
  doAssert calls == @["web.hide and"], $calls
  # back and close
  shown = true
  run(2)
  calls.setLen(0)
  doAssert webGoBack("and")
  doAssert calls == @["web.back and"], $calls
  backOk = "0"
  doAssert not webGoBack("and")
  webClose("and")
  doAssert calls[^1] == "web.close and"
  useSystemWebView = false

echo "html view tests passed"
