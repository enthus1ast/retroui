## Letters and certificates: a template's text with #[tags]#, filled in for
## an employee and laid out on the hotel's paper -- its letterhead image,
## or a header made of its logo, name and numbers -- as a report that is
## shown, saved as PDF, shared or printed.
##
## The text of a template is plain, with a few marks:
##
## - `# Title`, `## Smaller title`
## - an empty line between paragraphs
## - `**bold**`
## - `^^ text`: centered, `>> text`: at the right, `<< text`: at the left
## - `| a | b |` lines: a table
## - `---`: a line across
## - `[signature]`: the hotel's signature and stamp, the signer's name and title
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[strutils, tables, os, base64, times]
import retroui/[report, templates, imaging]
import model

proc esc(s: string): string =
  s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"))

proc inline(s: string): string =
  ## `**bold**` in already-escaped text.
  var parts = s.split("**")
  for i, p in parts:
    if i mod 2 == 1 and i < parts.high: result.add "<b>" & p & "</b>"
    else:
      if i > 0 and i mod 2 == 1: result.add "**"
      result.add p

proc isRtl(s: string): bool =
  for ch in s:
    if ord(ch) >= 0xD8 and ord(ch) <= 0xDB: return true     # (UTF-8 lead bytes of Arabic)

proc pngSize(data: string): tuple[w, h: int] =
  ## A PNG's width and height, from its header ((0, 0): not a PNG).
  if data.len < 24 or not data.startsWith("\x89PNG"): return
  template be(i: int): int =
    (ord(data[i]) shl 24) or (ord(data[i + 1]) shl 16) or (ord(data[i + 2]) shl 8) or ord(data[i + 3])
  (be(16), be(20))

proc picTag(dir, name, png: string; height: int): string =
  ## The picture as an <img>, `height` high and as wide as its shape says
  ## (both given: the report then never stretches it), written once to a
  ## file the report can read; "" when there is none.
  if png.len == 0: return ""
  createDir(dir)
  let p = dir / name & ".png"
  try:
    let data = decode(png)
    if not fileExists(p) or readFile(p) != data: writeFile(p, data)
    let (w, h) = pngSize(data)
    let width = if w > 0 and h > 0: " width=\"" & $max(1, height * w div h) & "\"" else: ""
    "<img src=\"" & p.extractFilename & "\"" & width & " height=\"" & $height & "\">"
  except ValueError, IOError, OSError: ""

proc bodyHtml*(body: string; lang: LetterLang; sig: string): string =
  ## The marked text as HTML (the tags are already filled in and escaped).
  let dirAttr = if lang == llArabic: " dir=\"rtl\"" else: ""
  var para: seq[string]
  var align = ""
  var tableRows: seq[seq[string]]
  proc flushPara(res: var string) =
    if para.len > 0:
      let t = para.join("<br>")
      let d = if lang == llArabic or (lang == llBoth and isRtl(t)): " dir=\"rtl\"" else: ""
      let st = if align.len > 0: " style=\"text-align: " & align & "\"" else: ""
      res.add "<p" & d & st & ">" & inline(t) & "</p>\n"
      para.setLen(0)
      align = ""
  proc flushTable(res: var string) =
    if tableRows.len > 0:
      res.add "<table border=\"1\"" & dirAttr & ">"
      for r in tableRows:
        res.add "<tr>"
        for c in r: res.add "<td>" & inline(c.strip) & "</td>"
        res.add "</tr>"
      res.add "</table>\n"
      tableRows.setLen(0)
  for raw in body.splitLines:
    let line = raw.strip(leading = false)
    let t = line.strip
    if t.startsWith("|") and t.endsWith("|") and t.len > 1:
      flushPara(result)
      var cells = t[1 .. ^2].split('|')
      var dashes = true
      for c in cells:
        if c.strip.replace("-", "").replace(":", "").len > 0: dashes = false
      if not dashes: tableRows.add cells
      continue
    flushTable(result)
    if t.len == 0:
      flushPara(result)
    elif t.startsWith("## "):
      flushPara(result)
      let d = if isRtl(t): " dir=\"rtl\"" else: ""
      result.add "<h3" & d & ">" & inline(t[3 .. ^1]) & "</h3>\n"
    elif t.startsWith("# "):
      flushPara(result)
      let d = if isRtl(t): " dir=\"rtl\"" else: ""
      result.add "<h2" & d & " style=\"text-align: center\">" & inline(t[2 .. ^1]) & "</h2>\n"
    elif t == "---":
      flushPara(result)
      result.add "<hr>\n"
    elif t.toLowerAscii == "[signature]":
      flushPara(result)
      result.add sig
    elif t.startsWith("^^ "):
      flushPara(result)
      align = "center"
      para.add t[3 .. ^1]
      flushPara(result)
    elif t.startsWith(">> "):
      flushPara(result)
      align = "right"
      para.add t[3 .. ^1]
      flushPara(result)
    elif t.startsWith("<< "):
      flushPara(result)
      align = "left"
      para.add t[3 .. ^1]
      flushPara(result)
    else:
      para.add t
  flushTable(result)
  flushPara(result)

proc letterHotel*(b: Book; t: Template; e: Employee): Hotel =
  let id = if t.hotel.len > 0: t.hotel else: e.get("hotel")
  let i = b.hotelIndex(id)
  if i >= 0: b.hotels[i] elif b.hotels.len > 0: b.hotels[0] else: Hotel(name: "")

proc nextRefNo*(h: Hotel): string =
  let y = $now().year
  let n = h.nextRef.getOrDefault(y, 1)
  (if h.refPrefix.len > 0: h.refPrefix else: h.code & "/HR") & "/" & y & "/" & align($n, 3, '0')

proc takeRefNo*(b: var Book; hotelId: string): string =
  ## The next reference number of the hotel, counted.
  let i = b.hotelIndex(hotelId)
  if i < 0: return ""
  result = nextRefNo(b.hotels[i])
  let y = $now().year
  b.hotels[i].nextRef[y] = b.hotels[i].nextRef.getOrDefault(y, 1) + 1
  b.hotels[i].modified = nowT()

proc letterReport*(b: Book; t: Template; e: Employee; answers: Table[string, string];
                   refNo, cacheDir: string): Report =
  ## The letter for `e`, on its hotel's paper.
  let h = letterHotel(b, t, e)
  let vals = tagValues(b, e, h, refNo)
  let filled = fillTags(t.body, vals, answers, escape = true)
  let picDir = cacheDir / "letters"
  let logo = picTag(picDir, h.id & "-logo", h.logo, 60)
  let sigPic = picTag(picDir, h.id & "-signature", h.signature, 50)
  let stampPic = picTag(picDir, h.id & "-stamp", h.stamp, 80)
  let ar = t.lang == llArabic
  # the signature block
  var sig = "<table class=\"plain\"" & (if ar: " dir=\"rtl\"" else: "") & "><tr><td width=\"55%\">"
  if sigPic.len > 0: sig.add sigPic & "<br>"
  let signer = if ar and h.signerAr.len > 0: h.signerAr else: h.signer
  let title = if ar and h.signerTitleAr.len > 0: h.signerTitleAr else: h.signerTitle
  if signer.len > 0: sig.add "<b>" & esc(signer) & "</b><br>"
  if title.len > 0: sig.add esc(title) & "<br>"
  sig.add esc(if ar and h.nameAr.len > 0: h.nameAr else: h.name)
  sig.add "</td><td align=\"center\">"
  if stampPic.len > 0: sig.add stampPic
  sig.add "</td></tr></table>\n"
  var html = "<title>" & esc(t.name & " - " & e.name) & "</title>\n"
  if h.letterhead.len == 0:
    # a header of its own: the logo, the hotel's name and numbers
    html.add "<table class=\"plain\"><tr><td width=\"30%\">"
    if logo.len > 0: html.add logo
    html.add "</td><td align=\"right\"><b><span style=\"font-size: 15px; color: " & h.color & "\">" &
             esc(h.name) & "</span></b><br>"
    if h.nameAr.len > 0: html.add "<span style=\"color: " & h.color & "\">" & esc(h.nameAr) & "</span><br>"
    if h.address.len > 0: html.add "<small>" & esc(h.address) & "</small><br>"
    var nums: seq[string]
    if h.cr.len > 0: nums.add "C.R. " & esc(h.cr)
    if h.vat.len > 0: nums.add "VATIN " & esc(h.vat)
    if nums.len > 0: html.add "<small>" & nums.join(" · ") & "</small>"
    html.add "</td></tr></table><hr>\n"
    var foot: seq[string]
    if h.phone.len > 0: foot.add "Tel. " & h.phone
    if h.email.len > 0: foot.add h.email
    if h.website.len > 0: foot.add h.website
    if foot.len > 0: html.add "<footer><span>" & esc(foot.join(" · ")) & "</span></footer>\n"
  # the reference and the date
  if refNo.len > 0:
    if ar:
      html.add "<table class=\"plain\" dir=\"rtl\"><tr><td>الرقم: " & esc(refNo) &
               "</td><td align=\"left\">التاريخ: " & esc(showDate(todayIso())) & "</td></tr></table>\n"
    else:
      html.add "<table class=\"plain\"><tr><td>Ref: " & esc(refNo) & "</td><td align=\"right\">Date: " &
               esc(showDate(todayIso())) & "</td></tr></table>\n"
  html.add bodyHtml(filled, t.lang, sig)
  result = reportFromHtml(html, baseDir = picDir, title = t.name)
  result.author = h.name
  result.size = 11
  if h.letterhead.len > 0:
    let bm = try: decodePng(decode(h.letterhead)) except CatchableError: nil
    if bm != nil:
      result.setBackground(bm)
      result.margins = (top: mm(48), right: mm(20), bottom: mm(32), left: mm(20))

# ---- the templates a new book starts with -------------------------------------------------------

proc starterTemplates*(): seq[Template] =
  let at = nowT()
  @[
    Template(id: newId("t-"), name: "Salary Certificate", lang: llEnglish, modified: at, body: """
# SALARY CERTIFICATE

To: #[?Addressed to]#

This is to certify that **#[Mr/Ms]# #[Name]#**, holder of #[Nationality]# nationality, Civil ID No. #[Civil ID]#, has been working with **#[Hotel Name]#** since #[Joining Date|long]# as **#[Position]#** in the #[Department]# department.

#[His/Her]# monthly salary is as follows:

#[Salary Table]#

(#[Total Salary|words]# only)

This certificate is issued at #[His/Her|lower]# request for the purpose of #[?Purpose]#, without any liability on the part of the hotel.

[signature]
"""),
    Template(id: newId("t-"), name: "شهادة راتب", lang: llArabic, modified: at, body: """
# شهادة راتب

إلى: #[?الجهة الموجهة إليها]#

تشهد إدارة **#[اسم الفندق]#** بأن #[السيد/ة]# **#[الاسم]#**، #[الجنسية]#، رقم البطاقة المدنية #[الرقم المدني]#، #[يعمل/تعمل]# لدينا منذ تاريخ #[Joining Date|long-ar]# بوظيفة **#[المسمى الوظيفي]#** في قسم #[القسم]#.

#[ويتقاضى/وتتقاضى]# راتباً شهرياً إجمالياً قدره **#[Total Salary]# ريال عماني** (فقط #[Total Salary|words-ar]# لا غير)، موزعاً كالتالي:

#[جدول الراتب]#

وقد أعطيت #[له/لها]# هذه الشهادة بناءً على #[طلبه/طلبها]# دون أدنى مسؤولية على الفندق.

[signature]
"""),
    Template(id: newId("t-"), name: "Experience Certificate", lang: llEnglish, modified: at, body: """
# EXPERIENCE CERTIFICATE

To whom it may concern,

This is to certify that **#[Mr/Ms]# #[Name]#**, #[Nationality]#, Passport No. #[Passport No.]#, worked with **#[Hotel Name]#** as **#[Position]#** in the #[Department]# department from #[Joining Date|long]# to #[Leaving Date|long]#.

During this period #[His/Her]# conduct and performance were found satisfactory. We wish #[His/Her|lower]# all the best in the future.

[signature]
"""),
    Template(id: newId("t-"), name: "No Objection Certificate", lang: llEnglish, modified: at, body: """
# NO OBJECTION CERTIFICATE

To: #[?Addressed to]#

This is to certify that **#[Mr/Ms]# #[Name]#**, Civil ID No. #[Civil ID]#, is employed with **#[Hotel Name]#** as **#[Position]#** since #[Joining Date|long]#.

We have no objection to #[His/Her|lower]# #[?For what (e.g. travelling to Dubai from 1 to 5 December)]#.

[signature]
"""),
    Template(id: newId("t-"), name: "لمن يهمه الأمر", lang: llArabic, modified: at, body: """
# لمن يهمه الأمر

تشهد إدارة **#[اسم الفندق]#** بأن #[السيد/ة]# **#[الاسم]#** #[يعمل/تعمل]# لدينا بوظيفة #[المسمى الوظيفي]# منذ #[Joining Date|long-ar]# #[وما زال/وما زالت]# على رأس #[عمله/عملها]# حتى تاريخه.

وقد أعطيت #[له/لها]# هذه الشهادة بناءً على #[طلبه/طلبها]# لتقديمها إلى #[?الجهة]#.

[signature]
""")]
