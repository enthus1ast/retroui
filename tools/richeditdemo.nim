## The rich text editor of Retro Mail on its own: the formatting buttons,
## a message with lists, a quote, a link and Arabic, and the HTML and plain
## text it sends.  nim c -r tools/richeditdemo.nim
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/os
import retro, retro/richedit

const sample = """
<h2>Quarterly training plan</h2>
<p>Dear team,</p>
<p>Please find the plan below. It is <b>important</b>, <i>a little urgent</i>,
<u>underlined</u>, <s>no longer needed</s> and written in <code>monospace</code>
where it names a file. Colors: <span style="color:#c00000">red</span>,
<span style="color:#008000">green</span>, <span style="color:#000080">navy</span>;
sizes: <span style="font-size:9.35pt">small</span>, <span style="font-size:16.5pt">large</span>,
<span style="font-size:22pt">huge</span>.</p>
<ul><li>Front office: guest experience</li>
<li>Housekeeping<ul><li>room standards</li><li>safety</li></ul></li>
<li>Kitchen: hygiene</li></ul>
<ol><li>Book the training room</li><li>Send the invitations</li><li>Collect the feedback</li></ol>
<p>The details are on <a href="https://www.foxoman.net">our site</a>.</p>
<p dir="rtl">مرحبا بالجميع، يرجى <b>مراجعة</b> الخطة قبل الاجتماع.</p>
<ul dir="rtl"><li>التدريب يوم الخميس</li><li>القاعة الكبرى، الطابق 2</li></ul>
<blockquote><p dir="rtl">نص مقتبس من الرسالة السابقة</p></blockquote>
<p style="text-align:center">Thank you</p>
<p><br></p>
<p>On Monday, Ahmed wrote:</p>
<blockquote><p>Can we move the session to Thursday?</p>
<blockquote><p>The room is free all week.</p></blockquote></blockquote>
"""

var
  doc = richFromHtml(sample)
  showHtml = getEnv("RICH_SHOW") == "html"
  showPlain = getEnv("RICH_SHOW") == "plain"
  compact = getEnv("RICH_COMPACT") == "1"
  status = "Ready"
  shown = ""

if getEnv("RICH_EMPTY") == "1": doc = richDoc("")

app "Rich Text Editor", 800, 600:
  richToolbar(doc, compact = compact)
  row:
    if button("Show &HTML"):
      showHtml = not showHtml
      showPlain = false
    if button("Plain &text"):
      showPlain = not showPlain
      showHtml = false
    if button("&Signature"):
      richInsertDoc(doc, richFromHtml("<p>--</p><p><b>Sultan Al Isaiee</b></p>" &
                                      "<p><span style=\"color:#808080\">Human Resources</span></p>"))
    if button("&Clear all"):
      richSelectAll(doc)
      richInsert(doc, "")
  let h = if showHtml or showPlain: max(120, (remainingH() - Gap) div 2) else: -1
  if richEdit(doc, height = h, placeholder = "Write your message"): status = "Changed"
  let lk = richClickedLink(doc)
  if lk.len > 0: status = "Link: " & lk
  if showHtml or showPlain:
    shown = if showHtml: toHtml(doc) else: toPlainText(doc)
    editArea shown, lines = -1
  statusbar status, $doc.paras.len & " paragraphs"
