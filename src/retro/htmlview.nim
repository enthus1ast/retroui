## Web pages and HTML in the window.
##
## - `htmlView`, `htmlBlock`: a safe subset of HTML -- headings,
##   paragraphs, bold, italic, underline, strike, code, marked and colored
##   text, links, line breaks, rules, lists (nested), quotes, preformatted
##   text, tables, pictures (files next to the page), definition lists --
##   read by a forgiving parser and drawn with the kit's Markdown renderer.
##   Scripts, styles, frames and forms are left out entirely: no page can
##   run code or reach the network.
## - `webView`: a web page. On Android it is the system's WebView (the
##   browser engine of the phone) placed over the widget; elsewhere local
##   pages (`file://`, paths, `html:` text) are shown with `htmlView`, and
##   pages on the web get a button that opens them in the browser.
##
## .. code-block:: nim
##   let ev = htmlView(readFile("help/index.html"), baseDir = "help")
##   if ev.link.len > 0: discard openUrl(ev.link)
##
##   let w = webView("https://nim-lang.org", key = "docs")
##   if w.back: requestClose()      # Back with no page before (Android)

import std/[strutils, unicode, tables, os, hashes, times]
import core, widgets, markdown, pixelicons, nerdicons
import uirelays/services

template th: untyped = ui.theme

# ---- limits: what a hostile page can cost ---------------------------------------------------

const
  MaxHtml = 4_000_000        ## bytes of HTML read (the rest is left out)
  MaxDepth = 96              ## elements in elements deeper than this are taken flat
  MaxNodes = 250_000         ## elements and texts
  MaxAttrs = 32              ## attributes read per element
  MaxOut = 6_000_000         ## bytes of Markdown made
  MaxNest = 10               ## lists and quotes in each other
  MaxCols = 50               ## table columns
  MaxRows = 5000             ## table rows

# ---- entities -----------------------------------------------------------------------------------

const namedEntities = {
  "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u00A0",
  "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
  "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›", "lsquo": "‘",
  "rsquo": "’", "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„",
  "bull": "•", "middot": "·", "times": "×", "divide": "÷", "deg": "°",
  "plusmn": "±", "micro": "µ", "para": "¶", "sect": "§", "euro": "€", "pound": "£",
  "yen": "¥", "cent": "¢", "curren": "¤", "larr": "←", "rarr": "→", "uarr": "↑",
  "darr": "↓", "harr": "↔", "lArr": "⇐", "rArr": "⇒", "hArr": "⇔", "crarr": "↵",
  "check": "✓", "cross": "✗", "frac12": "½", "frac14": "¼", "frac34": "¾",
  "sup1": "¹", "sup2": "²", "sup3": "³", "ordf": "ª", "ordm": "º", "iexcl": "¡",
  "iquest": "¿", "shy": "\u00AD", "ensp": "\u2002", "emsp": "\u2003",
  "thinsp": "\u2009", "zwj": "\u200D", "zwnj": "\u200C", "lrm": "\u200E",
  "rlm": "\u200F", "dagger": "†", "Dagger": "‡", "permil": "‰", "prime": "′",
  "Prime": "″", "oline": "‾", "frasl": "⁄", "minus": "−", "lowast": "∗",
  "infin": "∞", "ne": "≠", "le": "≤", "ge": "≥", "asymp": "≈", "equiv": "≡",
  "sum": "∑", "prod": "∏", "radic": "√", "part": "∂", "int": "∫", "forall": "∀",
  "exist": "∃", "empty": "∅", "nabla": "∇", "isin": "∈", "notin": "∉", "ni": "∋",
  "prop": "∝", "and": "∧", "or": "∨", "cap": "∩", "cup": "∪", "there4": "∴",
  "sim": "∼", "cong": "≅", "sub": "⊂", "sup": "⊃", "sube": "⊆", "supe": "⊇",
  "oplus": "⊕", "otimes": "⊗", "perp": "⊥", "sdot": "⋅", "lceil": "⌈",
  "rceil": "⌉", "lfloor": "⌊", "rfloor": "⌋", "lang": "⟨", "rang": "⟩", "loz": "◊",
  "spades": "♠", "clubs": "♣", "hearts": "♥", "diams": "♦", "not": "¬",
  "macr": "¯", "acute": "´", "cedil": "¸", "uml": "¨", "brvbar": "¦",
  "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã", "Auml": "Ä",
  "Aring": "Å", "AElig": "Æ", "Ccedil": "Ç", "Egrave": "È", "Eacute": "É",
  "Ecirc": "Ê", "Euml": "Ë", "Igrave": "Ì", "Iacute": "Í", "Icirc": "Î",
  "Iuml": "Ï", "ETH": "Ð", "Ntilde": "Ñ", "Ograve": "Ò", "Oacute": "Ó",
  "Ocirc": "Ô", "Otilde": "Õ", "Ouml": "Ö", "Oslash": "Ø", "Ugrave": "Ù",
  "Uacute": "Ú", "Ucirc": "Û", "Uuml": "Ü", "Yacute": "Ý", "THORN": "Þ",
  "szlig": "ß", "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã",
  "auml": "ä", "aring": "å", "aelig": "æ", "ccedil": "ç", "egrave": "è",
  "eacute": "é", "ecirc": "ê", "euml": "ë", "igrave": "ì", "iacute": "í",
  "icirc": "î", "iuml": "ï", "eth": "ð", "ntilde": "ñ", "ograve": "ò",
  "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö", "oslash": "ø",
  "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü", "yacute": "ý",
  "thorn": "þ", "yuml": "ÿ", "OElig": "Œ", "oelig": "œ", "Scaron": "Š",
  "scaron": "š", "Yuml": "Ÿ", "fnof": "ƒ", "circ": "ˆ", "tilde": "˜",
  "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Epsilon": "Ε",
  "Zeta": "Ζ", "Eta": "Η", "Theta": "Θ", "Iota": "Ι", "Kappa": "Κ",
  "Lambda": "Λ", "Mu": "Μ", "Nu": "Ν", "Xi": "Ξ", "Omicron": "Ο", "Pi": "Π",
  "Rho": "Ρ", "Sigma": "Σ", "Tau": "Τ", "Upsilon": "Υ", "Phi": "Φ", "Chi": "Χ",
  "Psi": "Ψ", "Omega": "Ω", "alpha": "α", "beta": "β", "gamma": "γ",
  "delta": "δ", "epsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ",
  "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ",
  "omicron": "ο", "pi": "π", "rho": "ρ", "sigmaf": "ς", "sigma": "σ", "tau": "τ",
  "upsilon": "υ", "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω"}.toTable

const legacyEntities = ["amp", "lt", "gt", "quot", "nbsp", "copy", "reg"]
  ## named without the ';' in old pages

proc decodeEntities*(t: string): string =
  ## `t` with its character references ("&amp;", "&#169;", "&#xA9;")
  ## replaced by the characters.
  if '&' notin t: return t
  result = newStringOfCap(t.len)
  var i = 0
  while i < t.len:
    let ch = t[i]
    if ch != '&':
      result.add ch
      inc i
      continue
    var j = i + 1
    if j < t.len and t[j] == '#':
      inc j
      var hex = false
      if j < t.len and t[j] in {'x', 'X'}:
        hex = true
        inc j
      var v = 0
      var n = 0
      while j < t.len and n < 8 and (if hex: t[j] in HexDigits else: t[j] in Digits):
        v = v * (if hex: 16 else: 10) +
            (if t[j] in Digits: ord(t[j]) - ord('0')
             else: ord(t[j].toLowerAscii) - ord('a') + 10)
        inc j
        inc n
      if n == 0:
        result.add ch
        inc i
        continue
      if j < t.len and t[j] == ';': inc j
      if v == 0 or v > 0x10FFFF or v in 0xD800 .. 0xDFFF: v = 0xFFFD
      result.add $Rune(v)
      i = j
      continue
    var name = ""
    while j < t.len and name.len < 32 and t[j].isAlphaNumeric:
      name.add t[j]
      inc j
    if j < t.len and t[j] == ';' and namedEntities.hasKey(name):
      result.add namedEntities[name]
      i = j + 1
    elif name in legacyEntities:
      result.add namedEntities[name]
      i = j
    else:
      result.add ch
      inc i

proc htmlEscape*(s: string): string =
  ## `s` safe to put in HTML text: & < > " escaped.
  result = newStringOfCap(s.len + 8)
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    else: result.add c

# ---- the document tree ------------------------------------------------------------------------

type
  HNode = ref object
    tag: string                          ## "" for a text
    text: string
    attrs: seq[(string, string)]
    kids: seq[HNode]

proc attr(n: HNode; name: string): string =
  for (k, v) in n.attrs:
    if k == name: return v

const
  voidTags = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link",
              "meta", "param", "source", "track", "wbr", "keygen", "frame",
              "basefont", "isindex"]
  rawTags = ["script", "style", "textarea", "title", "xmp", "iframe", "noembed",
             "noframes", "plaintext"]
  skipTags = ["head", "script", "style", "template", "iframe", "object", "embed",
              "svg", "math", "canvas", "video", "audio", "form", "select", "button",
              "textarea", "datalist", "dialog", "map", "frameset", "frame", "applet",
              "meta", "link", "base", "noembed", "noframes", "title", "xmp", "option",
              "optgroup", "label", "output", "progress", "meter", "picture", "source",
              "track", "param", "plaintext"]
  closesP = ["address", "article", "aside", "blockquote", "center", "details",
             "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure",
             "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup",
             "hr", "main", "menu", "nav", "ol", "p", "pre", "section", "summary",
             "table", "ul", "li", "dd", "dt", "search"]
  pScope = ["table", "td", "th", "caption", "html", "button", "object", "template",
            "marquee", "applet"]
  headings = ["h1", "h2", "h3", "h4", "h5", "h6"]
  blockTags = ["html", "body", "div", "p", "section", "article", "header", "footer",
               "main", "nav", "aside", "figure", "figcaption", "address", "center",
               "details", "summary", "hgroup", "h1", "h2", "h3", "h4", "h5", "h6",
               "ul", "ol", "li", "dl", "dt", "dd", "blockquote", "pre", "table",
               "caption", "thead", "tbody", "tfoot", "tr", "td", "th", "hr", "menu",
               "dir", "fieldset", "legend", "noscript", "search", "listing"]

proc findCI(s, what: string; start: int): int =
  ## `what` (lower case) in `s` from `start`, letters in any case.
  let n = what.len
  var i = start
  while i + n <= s.len:
    var k = 0
    while k < n and s[i + k].toLowerAscii == what[k]: inc k
    if k == n: return i
    inc i
  -1

proc parseHtml(src: string): tuple[root: HNode; title: string] =
  ## A forgiving reader: what browsers make of messy pages, near enough --
  ## unclosed paragraphs, list items and cells closed by what follows,
  ## misnested tags, missing end tags.
  let s = if src.len > MaxHtml: src[0 ..< MaxHtml] else: src
  let root = HNode(tag: "#root")
  result.root = root
  var stack = @[root]
  var nodes = 0
  var gotTitle = false
  template top: HNode = stack[^1]
  proc addText(stack: var seq[HNode]; t: string; nodes: var int) =
    if t.len == 0: return
    let p = stack[^1]
    if p.kids.len > 0 and p.kids[^1].tag.len == 0:
      p.kids[^1].text.add t
    else:
      inc nodes
      p.kids.add HNode(text: t)
  proc closeTo(stack: var seq[HNode]; names: openArray[string];
               bounds: openArray[string]): bool =
    ## Closes up to the nearest open element named one of `names`, unless
    ## an element in `bounds` comes first.
    for k in countdown(stack.high, 1):
      let t = stack[k].tag
      if t in names:
        stack.setLen(k)
        return true
      if t in bounds: return false
  var i = 0
  while i < s.len and nodes < MaxNodes:
    let lt = s.find('<', i)
    let textEnd = if lt < 0: s.len else: lt
    if textEnd > i:
      addText(stack, decodeEntities(s[i ..< textEnd]), nodes)
    if lt < 0: break
    i = lt
    if i + 1 >= s.len:
      addText(stack, "<", nodes)
      break
    let c1 = s[i + 1]
    if s.continuesWith("<!--", i):
      let e = s.find("-->", i + 4)
      i = if e < 0: s.len else: e + 3
      continue
    if s.continuesWith("<![CDATA[", i):
      let e = s.find("]]>", i + 9)
      let body = if e < 0: s[i + 9 .. ^1] else: s[i + 9 ..< e]
      addText(stack, body, nodes)
      i = if e < 0: s.len else: e + 3
      continue
    if c1 in {'!', '?'}:
      let e = s.find('>', i + 2)
      i = if e < 0: s.len else: e + 1
      continue
    if c1 == '/' and i + 2 < s.len and s[i + 2].isAlphaAscii:
      # an end tag
      var j = i + 2
      var name = ""
      while j < s.len and (s[j].isAlphaNumeric or s[j] in {'-', ':'}) and name.len < 32:
        name.add s[j].toLowerAscii
        inc j
      let e = s.find('>', j)
      i = if e < 0: s.len else: e + 1
      if name == "br":
        inc nodes
        top.kids.add HNode(tag: "br")
      elif name == "p":
        discard closeTo(stack, ["p"], pScope)
      elif name in headings:
        discard closeTo(stack, headings, [])
      else:
        discard closeTo(stack, [name], [])
      continue
    if not c1.isAlphaAscii:
      addText(stack, "<", nodes)
      inc i
      continue
    # a start tag, its attributes
    var j = i + 1
    var name = ""
    while j < s.len and (s[j].isAlphaNumeric or s[j] in {'-', ':'}) and name.len < 32:
      name.add s[j].toLowerAscii
      inc j
    var attrs: seq[(string, string)]
    var selfClose = false
    while j < s.len:
      while j < s.len and s[j] in {' ', '\t', '\n', '\r', '\f'}: inc j
      if j >= s.len: break
      if s[j] == '>':
        inc j
        break
      if s[j] == '/':
        selfClose = j + 1 < s.len and s[j + 1] == '>'
        inc j
        continue
      var an = ""
      while j < s.len and s[j] notin {' ', '\t', '\n', '\r', '\f', '=', '>', '/'}:
        if an.len < 64: an.add s[j].toLowerAscii
        inc j
      if an.len == 0:
        inc j
        continue
      while j < s.len and s[j] in {' ', '\t', '\n', '\r', '\f'}: inc j
      var av = ""
      if j < s.len and s[j] == '=':
        inc j
        while j < s.len and s[j] in {' ', '\t', '\n', '\r', '\f'}: inc j
        if j < s.len and s[j] in {'"', '\''}:
          let q = s[j]
          let e = s.find(q, j + 1)
          let stop = if e < 0: s.len else: e
          av = s[j + 1 ..< stop]
          j = stop + 1
        else:
          let st = j
          while j < s.len and s[j] notin {' ', '\t', '\n', '\r', '\f', '>'}: inc j
          av = s[st ..< j]
      if attrs.len < MaxAttrs and av.len <= 100_000:
        attrs.add (an, decodeEntities(av))
    i = min(j, s.len)
    # raw text: up to its end tag, not read as HTML
    if name in rawTags and not selfClose:
      let e = findCI(s, "</" & name, i)
      let body = if e < 0: s[i .. ^1] else: s[i ..< e]
      if name == "title" and not gotTitle:
        gotTitle = true
        result.title = strutils.splitWhitespace(decodeEntities(body)).join(" ")
      elif name in ["xmp", "plaintext"]:
        inc nodes
        let n = HNode(tag: "pre", kids: @[HNode(text: body)])
        top.kids.add n
      if e < 0: i = s.len
      else:
        let gt = s.find('>', e)
        i = if gt < 0: s.len else: gt + 1
      continue
    # what this one closes first
    if name in closesP: discard closeTo(stack, ["p"], pScope)
    case name
    of "li": discard closeTo(stack, ["li"], ["ul", "ol", "menu", "dir", "table"])
    of "dt", "dd": discard closeTo(stack, ["dt", "dd"], ["dl", "table"])
    of "tr": discard closeTo(stack, ["tr", "td", "th"], ["table"])
    of "td", "th": discard closeTo(stack, ["td", "th"], ["tr", "table"])
    of "thead", "tbody", "tfoot":
      discard closeTo(stack, ["thead", "tbody", "tfoot"], ["table"])
    of "h1", "h2", "h3", "h4", "h5", "h6":
      if top.tag in headings: discard stack.pop()
    of "a": discard closeTo(stack, ["a"], ["table", "td", "th"])
    of "option", "optgroup": discard closeTo(stack, ["option"], ["select"])
    else: discard
    inc nodes
    let n = HNode(tag: name, attrs: attrs)
    top.kids.add n
    if name notin voidTags and not selfClose and stack.len < MaxDepth:
      stack.add n

# ---- to Markdown ------------------------------------------------------------------------------

type
  Inl = object
    ## A paragraph being made.
    buf: string
    lastSpace: bool            ## the text so far ends in white space
    visible: bool              ## something shows
    pendingBreak: bool         ## a line break before what comes next
    inLink: bool
  Conv = object
    size: int                  ## Markdown made so far

proc esc(buf: var string; r: string) =
  ## Text, with what Markdown would read as markup escaped.
  for c in r:
    if c in {'!'..'/', ':'..'@', '['..'`', '{'..'~'}: buf.add '\\'
    buf.add c

proc safeUrl(u: string): string =
  ## `u` as a link may take it: "" for scripts; spaces, brackets and pipes
  ## made harmless.
  var t = ""
  for c in u:
    if c notin {'\0'..' ', '\x7F'} or c == ' ': t.add c
  t = t.strip
  var scheme = ""
  for c in t:
    if c in {' ', '\t'}: continue
    if c == ':': break
    scheme.add c.toLowerAscii
    if scheme.len > 12: break
  if scheme in ["javascript", "vbscript", "data"] and ':' in t: return ""
  for c in t:
    case c
    of '<': result.add "%3C"
    of '>': result.add "%3E"
    of '(': result.add "%28"
    of ')': result.add "%29"
    of '|': result.add "%7C"
    of '\\': result.add '/'
    else: result.add c

proc unsafeUrl(u: string): string =
  ## What `safeUrl` changed, back (for the link reported).
  u.multiReplace(("%3C", "<"), ("%3E", ">"), ("%28", "("), ("%29", ")"), ("%7C", "|"))

proc emitText(st: var Inl; t: string; c: var Conv) =
  ## Text into the paragraph, white space collapsed.
  for r in t.runes:
    let isSpace = int(r) in {9, 10, 12, 13, 32}
    if isSpace:
      if not st.lastSpace and st.visible and not st.pendingBreak:
        st.buf.add ' '
        st.lastSpace = true
      continue
    if st.pendingBreak and st.visible:
      while st.buf.endsWith(" "): st.buf.setLen(st.buf.len - 1)
      st.buf.add "<br>"
    st.pendingBreak = false
    st.buf.esc($r)
    st.lastSpace = false
    st.visible = true
  c.size += t.len

proc lineBreak(st: var Inl) =
  ## A break before the next text (none at the start, none twice).
  if st.visible: st.pendingBreak = true
  st.lastSpace = true

proc styleAttrColor(n: HNode): string =
  ## "#rrggbb" of the text color an element asks for, or "".
  var col = Color()
  if n.tag == "font": col = cssColor(n.attr("color"))
  let style = n.attr("style")
  if style.len > 0:
    for decl in style.split(';'):
      let k = decl.find(':')
      if k > 0 and decl[0 ..< k].strip.toLowerAscii == "color":
        col = cssColor(decl[k + 1 .. ^1].strip.split(' ')[0])
  if col.a == 0: return ""
  "#" & toHex(int(col.r), 2) & toHex(int(col.g), 2) & toHex(int(col.b), 2)

proc rawText(n: HNode; buf: var string) =
  ## The text of `n` as it is (preformatted): line breaks kept.
  if n.tag.len == 0:
    buf.add n.text
    return
  if n.tag in skipTags and n.tag notin ["xmp", "plaintext"]: return
  if n.tag == "br":
    buf.add '\n'
    return
  let blocky = n.tag in ["p", "div", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6"]
  if blocky and buf.len > 0 and not buf.endsWith("\n"): buf.add '\n'
  for k in n.kids: rawText(k, buf)
  if blocky and not buf.endsWith("\n"): buf.add '\n'

proc inline(c: var Conv; n: HNode; st: var Inl; depth: int)

proc wrapped(c: var Conv; n: HNode; st: var Inl; depth: int; open, close: string) =
  ## The children of `n` between `open` and `close` (left out when empty).
  let saved = (st.buf.len, st.visible, st.pendingBreak, st.lastSpace)
  st.buf.add open
  let inner = st.buf.len
  for k in n.kids: c.inline(k, st, depth + 1)
  if st.buf.len == inner:
    st.buf.setLen(saved[0])
    (st.visible, st.pendingBreak, st.lastSpace) = (saved[1], saved[2], saved[3])
  else:
    st.buf.add close

proc inline(c: var Conv; n: HNode; st: var Inl; depth: int) =
  if c.size > MaxOut: return
  if n.tag.len == 0:
    st.emitText(n.text, c)
    return
  if n.tag in skipTags: return
  if depth > MaxDepth:
    var t = ""
    rawText(n, t)
    st.emitText(t, c)
    return
  case n.tag
  of "br":
    while st.buf.endsWith(" "): st.buf.setLen(st.buf.len - 1)
    if st.visible:
      st.buf.add "<br>"
      st.pendingBreak = false
    st.lastSpace = true
  of "b", "strong": c.wrapped(n, st, depth, "<b>", "</b>")
  of "i", "em", "cite", "var", "dfn": c.wrapped(n, st, depth, "<i>", "</i>")
  of "u", "ins": c.wrapped(n, st, depth, "<u>", "</u>")
  of "s", "strike", "del": c.wrapped(n, st, depth, "<s>", "</s>")
  of "code", "kbd", "samp", "tt": c.wrapped(n, st, depth, "<code>", "</code>")
  of "mark": c.wrapped(n, st, depth, "<mark>", "</mark>")
  of "q": c.wrapped(n, st, depth, "<q>", "</q>")
  of "font", "span":
    let col = styleAttrColor(n)
    if col.len > 0: c.wrapped(n, st, depth, "<font color=\"" & col & "\">", "</font>")
    else:
      for k in n.kids: c.inline(k, st, depth + 1)
  of "a":
    let href = safeUrl(n.attr("href"))
    if href.len == 0 or st.inLink or href.startsWith("#") and href.len == 1:
      for k in n.kids: c.inline(k, st, depth + 1)
      return
    if st.pendingBreak and st.visible:
      st.buf.add "<br>"
      st.pendingBreak = false
    let start = st.buf.len
    let wasVisible = st.visible
    st.buf.add '['
    let inner = st.buf.len
    st.inLink = true
    for k in n.kids: c.inline(k, st, depth + 1)
    st.inLink = false
    if st.buf.len == inner:
      st.buf.esc(n.attr("href").strip)       # a link without words: its address
      st.visible = true
    while st.buf.endsWith(" "): st.buf.setLen(st.buf.len - 1)
    if st.buf.len == inner:
      st.buf.setLen(start)
      st.visible = wasVisible
      return
    st.buf.add "](<" & href & ">)"
    st.lastSpace = false
  of "img":
    let src = safeUrl(n.attr("src"))
    let alt = strutils.splitWhitespace(n.attr("alt")).join(" ")
    if src.len == 0:
      if alt.len > 0: st.emitText(alt, c)
      return
    if st.pendingBreak and st.visible:
      st.buf.add "<br>"
      st.pendingBreak = false
    if not st.lastSpace and st.visible: st.buf.add ' '
    st.buf.add "!["
    st.buf.esc(alt)
    st.buf.add "](<" & src & ">)"
    st.visible = true
    st.lastSpace = false
  of "input":
    # a task list's check box (forms are left out)
    if n.attr("type").toLowerAscii == "checkbox":
      var checked = false
      for (k, _) in n.attrs:
        if k == "checked": checked = true
      st.emitText(if checked: "\u2611 " else: "\u2610 ", c)
  of "li":
    st.lineBreak()
    st.emitText("\u2022 ", c)
    for k in n.kids: c.inline(k, st, depth + 1)
    st.lineBreak()
  of "td", "th":
    if st.visible and not st.pendingBreak: st.emitText(" \u00B7 ", c)
    for k in n.kids: c.inline(k, st, depth + 1)
  of "hr":
    st.lineBreak()
  of "pre", "listing":
    st.lineBreak()
    var t = ""
    rawText(n, t)
    let lines = t.strip(leading = false).split('\n')
    if st.pendingBreak and st.visible: st.buf.add "<br>"
    st.pendingBreak = false
    st.buf.add "<code>"
    for k, line in lines:
      if k > 0: st.buf.add "<br>"
      st.buf.esc(line.replace("\t", "    "))
    st.buf.add "</code>"
    st.visible = true
    st.lineBreak()
  else:
    if n.tag in blockTags:
      st.lineBreak()
      for k in n.kids: c.inline(k, st, depth + 1)
      st.lineBreak()
    else:
      for k in n.kids: c.inline(k, st, depth + 1)

proc blocks(c: var Conv; kids: seq[HNode]; depth, nest: int): seq[string]

proc addBlock(result: var seq[string]; lines: seq[string]) =
  if lines.len == 0: return
  if result.len > 0: result.add ""
  result.add lines

proc tableLines(c: var Conv; n: HNode; depth: int): seq[string] =
  var rows: seq[tuple[node: HNode; head: bool]]
  var caption = ""
  for k in n.kids:
    case k.tag
    of "tr": rows.add (k, false)
    of "thead", "tbody", "tfoot":
      for kk in k.kids:
        if kk.tag == "tr": rows.add (kk, k.tag == "thead")
    of "caption":
      var st = Inl(lastSpace: true)
      for kk in k.kids: c.inline(kk, st, depth + 1)
      caption = st.buf.strip
    else: discard
    if rows.len >= MaxRows: break
  if rows.len == 0:
    # a table without rows: its text
    var st = Inl(lastSpace: true)
    for k in n.kids: c.inline(k, st, depth + 1)
    if st.visible: result.add st.buf.strip
    return
  var cells: seq[seq[string]]
  var aligns: seq[char]
  var allTh: seq[bool]
  for (r, head) in rows:
    var row: seq[string]
    var thOnly = true
    var any = false
    for cell in r.kids:
      if cell.tag notin ["td", "th"]: continue
      any = true
      if cell.tag == "td": thOnly = false
      var st = Inl(lastSpace: true)
      for kk in cell.kids: c.inline(kk, st, depth + 1)
      let col = row.len
      if col >= MaxCols: break
      row.add st.buf.strip
      var a = cell.attr("align").toLowerAscii
      let style = cell.attr("style").toLowerAscii
      let ta = style.find("text-align")
      if ta >= 0:
        let rest = style[ta .. ^1]
        if "center" in rest.split(';')[0]: a = "center"
        elif "right" in rest.split(';')[0]: a = "right"
      while aligns.len <= col: aligns.add '\0'
      if aligns[col] == '\0' and a in ["center", "right", "left"]: aligns[col] = a[0]
      var span = 1
      try: span = clamp(parseInt(cell.attr("colspan").strip), 1, MaxCols)
      except ValueError: discard
      for _ in 1 ..< span:
        if row.len < MaxCols: row.add ""
    cells.add row
    allTh.add (head or (any and thOnly))
  var ncols = 1
  for r in cells: ncols = max(ncols, r.len)
  ncols = min(ncols, MaxCols)
  proc line(r: seq[string]): string =
    result = "|"
    for k in 0 ..< ncols:
      result.add ' '
      result.add(if k < r.len: r[k] else: "")
      result.add " |"
  if caption.len > 0:
    result.add "<b>" & caption & "</b>"
    result.add ""
  var first = 0
  if allTh[0]:
    result.add line(cells[0])
    first = 1
  else:
    result.add line(newSeq[string](ncols))        # no header row
  var d = "|"
  for k in 0 ..< ncols:
    let a = if k < aligns.len: aligns[k] else: '\0'
    d.add(case a
          of 'c': " :---: |"
          of 'r': " ---: |"
          else: " --- |")
  result.add d
  for k in first ..< cells.len: result.add line(cells[k])
  if cells.len == first:
    result.add line(newSeq[string](ncols))

proc blockOf(c: var Conv; n: HNode; depth, nest: int): seq[string] =
  if c.size > MaxOut or n.tag in skipTags: return
  if depth > MaxDepth:
    var st = Inl(lastSpace: true)
    c.inline(n, st, depth)
    if st.visible: result.add st.buf.strip
    return
  case n.tag
  of "h1", "h2", "h3", "h4", "h5", "h6":
    var st = Inl(lastSpace: true)
    for k in n.kids: c.inline(k, st, depth + 1)
    if st.visible:
      result.add repeat('#', ord(n.tag[1]) - ord('0')) & " " & st.buf.strip
  of "hr":
    result.add "---"
  of "pre", "listing":
    var t = ""
    rawText(n, t)
    if t.startsWith("\n"): t = t[1 .. ^1]
    if t.startsWith("\r\n"): t = t[2 .. ^1]
    while t.endsWith("\n") or t.endsWith("\r"): t.setLen(t.len - 1)
    var lang = ""
    for k in n.kids:
      if k.tag == "code":
        for cls in strutils.splitWhitespace(k.attr("class")):
          if cls.startsWith("language-"): lang = cls[9 .. ^1]
          elif cls.startsWith("lang-"): lang = cls[5 .. ^1]
    var run, longest = 0
    for ch in t:
      if ch == '`':
        inc run
        longest = max(longest, run)
      else: run = 0
    let fence = repeat('`', max(3, longest + 1))
    var l = ""
    for ch in lang:
      if ch.isAlphaNumeric or ch in {'-', '+', '#', '.'}: l.add ch
    result.add fence & l
    for line in t.replace("\r\n", "\n").split('\n'): result.add line.replace("\t", "    ")
    result.add fence
    c.size += t.len
  of "blockquote":
    if nest >= MaxNest:
      return c.blocks(n.kids, depth + 1, nest)
    for line in c.blocks(n.kids, depth + 1, nest + 1):
      result.add(if line.len == 0: ">" else: "> " & line)
  of "ul", "ol", "menu", "dir":
    let ordered = n.tag == "ol"
    var num = 1
    if ordered:
      try: num = clamp(parseInt(n.attr("start").strip), 0, 999_999_999)
      except ValueError: discard
    if nest >= MaxNest:
      # too deep: items as lines with bullets
      var st = Inl(lastSpace: true)
      c.inline(n, st, depth)
      if st.visible: result.add st.buf.strip
      return
    var items: seq[seq[string]]
    for k in n.kids:
      if k.tag == "li":
        items.add c.blocks(k.kids, depth + 1, nest + 1)
      elif k.tag.len == 0 and k.text.strip.len == 0:
        continue
      elif k.tag in skipTags:
        continue
      else:
        # something else in the list: with the item before, or one of its own
        let lines = if k.tag in blockTags: c.blockOf(k, depth + 1, nest + 1)
                    else:
                      var st = Inl(lastSpace: true)
                      c.inline(k, st, depth + 1)
                      (if st.visible: @[st.buf.strip] else: @[])
        if lines.len == 0: continue
        if items.len > 0: items[^1].addBlock(lines)
        else: items.add lines
    for k, item in items:
      let marker = if ordered: $(num + k) & ". " else: "- "
      let pad = spaces(marker.len)
      if item.len == 0:
        result.add marker.strip
        continue
      result.add marker & item[0]
      for line in item[1 .. ^1]:
        result.add(if line.len == 0: "" else: pad & line)
  of "dl":
    for k in n.kids:
      case k.tag
      of "dt":
        var st = Inl(lastSpace: true)
        for kk in k.kids: c.inline(kk, st, depth + 1)
        if st.visible: result.addBlock(@["<b>" & st.buf.strip & "</b>"])
      of "dd":
        var lines: seq[string]
        for line in c.blocks(k.kids, depth + 1, nest):
          lines.add(if line.len == 0: "" else: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0" & line)
        result.addBlock(lines)
      else:
        if k.tag.len > 0: result.addBlock(c.blockOf(k, depth + 1, nest))
  of "table":
    result = c.tableLines(n, depth)
  of "li":
    let item = c.blocks(n.kids, depth + 1, nest + 1)
    if item.len > 0:
      result.add "- " & item[0]
      for line in item[1 .. ^1]: result.add(if line.len == 0: "" else: "  " & line)
  of "caption", "summary", "legend", "figcaption", "dt":
    var st = Inl(lastSpace: true)
    for k in n.kids: c.inline(k, st, depth + 1)
    if st.visible: result.add "<b>" & st.buf.strip & "</b>"
  else:
    result = c.blocks(n.kids, depth + 1, nest)

proc blocks(c: var Conv; kids: seq[HNode]; depth, nest: int): seq[string] =
  var st = Inl(lastSpace: true)
  template flush() =
    if st.visible:
      let t = st.buf.strip
      if t.len > 0: result.addBlock(@[t])
    st = Inl(lastSpace: true)
  for k in kids:
    if c.size > MaxOut: break
    if k.tag.len > 0 and k.tag in blockTags and k.tag notin ["td", "th", "tr"]:
      flush()
      result.addBlock(c.blockOf(k, depth, nest))
    else:
      c.inline(k, st, depth)
  flush()

var convCache: seq[tuple[h: Hash; n: int; md, title: string]]

proc convert(html: string): tuple[md, title: string] =
  let h = hash(html)
  for i, e in convCache:
    if e.h == h and e.n == html.len:
      if i > 0:
        let x = convCache[i]
        convCache.delete(i)
        convCache.insert(x, 0)
      return (convCache[0].md, convCache[0].title)
  let (root, title) = parseHtml(html)
  var c = Conv()
  let lines = c.blocks(root.kids, 0, 0)
  result = (lines.join("\n"), title)
  convCache.insert((h, html.len, result.md, result.title), 0)
  if convCache.len > 4: convCache.setLen(4)

proc htmlToMarkdown*(html: string): string =
  ## `html` as Markdown the kit draws (inline styles kept as the few HTML
  ## tags `markdown` understands). Scripts, styles, frames and forms are
  ## left out.
  convert(html).md

proc htmlTitle*(html: string): string =
  ## The page's `<title>` ("" when it has none).
  convert(html).title

# ---- showing HTML -------------------------------------------------------------------------------

type HtmlEvent* = object
  link*: string        ## a link clicked (its address as the page has it), or ""

proc htmlView*(html: string; baseDir = ""; height = -1; key = ""): HtmlEvent {.discardable.} =
  ## HTML in a framed view that scrolls (wheel, finger, scroll bar, arrows,
  ## Page keys); pictures load from `baseDir`. Returns the link clicked;
  ## links to "#a-heading" scroll there themselves. `key` tells several
  ## views apart.
  let ev = markdownView(convert(html).md, height = height, baseDir = baseDir,
                        key = "html:" & key)
  result.link = unsafeUrl(ev.link)

proc htmlBlock*(html: string; baseDir = ""; w = 0): HtmlEvent {.discardable.} =
  ## HTML flowing in the layout at its natural height (in a page that
  ## scrolls, a card, a dialog).
  let ev = markdown(convert(html).md, baseDir = baseDir, w = w)
  result.link = unsafeUrl(ev.link)

# ---- web pages ----------------------------------------------------------------------------------

type
  WebEvent* = object
    ## What a `webView` shows and what happened in it this frame.
    url*: string         ## the page shown now (after links followed in it)
    title*: string       ## its title ("" while there is none)
    progress*: int       ## how much of it is loaded, 0..100
    loading*: bool
    canGoBack*: bool     ## there is a page before (`webGoBack`)
    link*: string        ## a link clicked in a page the kit shows itself
    opened*: bool        ## the page was handed to the browser
    back*: bool          ## (Android) Back pressed in the page with no page before
  WebState = ref object
    asked: string        ## the address the app gave last
    cur: string          ## shown now
    history: seq[string]
    drawn: int           ## the frame it was last drawn in
    shown: bool          ## (Android) the system's view is on screen
    sent: string         ## ... with this address
    rect: Rect           ## ... at this place, in screen pixels
    polledAt: int
    title: string
    progress: int
    canBack, backOut: bool
    file: tuple[path, text: string; stamp: Time]

var
  useSystemWebView* = defined(android)
    ## Pages are the system's WebView (Android; tests can turn it on with a
    ## fake `systemRelays.call`).
  webs: Table[string, WebState]
  hooked = false

proc webFrameHook() {.nimcall.} =
  ## Views not drawn in the frame before go away (the system's view is
  ## not part of the kit's drawing: it would stay over the window).
  for k, w in webs:
    if w.shown and w.drawn < ui.frameNo - 1:
      discard systemCall("web.hide", k)
      w.shown = false

proc webOf(key: string): WebState =
  result = webs.getOrDefault(key, nil)
  if result == nil:
    result = WebState(progress: 100)
    webs[key] = result
  if not hooked:
    hooked = true
    beginFrameHooks.add webFrameHook

proc isWeb(u: string): bool =
  let l = u.toLowerAscii
  l.startsWith("http://") or l.startsWith("https://")

proc localPath(u: string): string =
  ## The file a "file://" address or a path names ("" when it is neither).
  if u.toLowerAscii.startsWith("file://"):
    var p = u[7 .. ^1]
    if p.len >= 3 and p[0] == '/' and p[2] == ':': p = p[1 .. ^1]   # file:///C:/...
    var r = ""
    var i = 0
    while i < p.len:
      if p[i] == '%' and i + 2 < p.len and p[i + 1] in HexDigits and p[i + 2] in HexDigits:
        r.add char(parseHexInt(p[i + 1 .. i + 2]))
        i += 3
      else:
        r.add p[i]
        inc i
    return r
  if u.len > 0 and (u[0] == '/' or u.startsWith("./") or u.startsWith("~") or
     (u.len >= 3 and u[1] == ':' and u[2] in {'/', '\\'})):
    return u.expandTilde
  ""

proc pageText(w: WebState; path: string): string =
  ## A local page's text, read again when the file changed (4 MB at most).
  let stamp = try: getLastModificationTime(path) except OSError: Time()
  if w.file.path == path and w.file.stamp == stamp: return w.file.text
  var t = ""
  try:
    var f = open(path)
    defer: f.close()
    t = newString(min(MaxHtml, int(max(0'i64, getFileSize(f)))))
    if t.len > 0: t.setLen(f.readBuffer(addr t[0], t.len))
  except IOError, OSError:
    t = ""
  w.file = (path, t, stamp)
  t

proc webGoBack*(key = ""): bool {.discardable.} =
  ## The page before in the `webView` with `key`; false when there is none.
  let w = webs.getOrDefault(key, nil)
  if w == nil: return false
  if useSystemWebView:
    if w.shown and systemCall("web.back", key) == "1":
      return true
    return false
  if w.history.len == 0: return false
  w.cur = w.history.pop()
  ui.redraw = true
  true

proc webReload*(key = "") =
  ## Loads the page of the `webView` with `key` again.
  let w = webs.getOrDefault(key, nil)
  if w == nil: return
  if useSystemWebView: discard systemCall("web.reload", key)
  else:
    w.file.path = ""
    ui.redraw = true

proc webClose*(key = "") =
  ## Lets the `webView` with `key` go (on Android its WebView is freed;
  ## drawing it again starts afresh).
  let w = webs.getOrDefault(key, nil)
  if w == nil: return
  if useSystemWebView: discard systemCall("web.close", key)
  webs.del key

proc follow(w: WebState; link: string; ev: var WebEvent) =
  ## A link clicked in a page the kit shows: another local page is shown
  ## here (Back returns), anything else goes to the system (the browser,
  ## mail...).
  var target = link
  let hashAt = target.find('#')
  if hashAt >= 0: target = target[0 ..< hashAt]
  let qAt = target.find('?')
  if qAt >= 0: target = target[0 ..< qAt]
  if target.len == 0: return
  let lower = target.toLowerAscii
  if ':' in lower and not lower.startsWith("file:") and
     not (target.len >= 3 and target[1] == ':' and target[2] in {'/', '\\'}):
    if openUrl(link): ev.opened = true
    return
  var path = localPath(target)
  if path.len == 0:
    let here = localPath(w.cur)
    let dir = if here.len > 0: here.parentDir else: getCurrentDir()
    path = dir / target
  path = path.normalizedPath
  if fileExists(path):
    w.history.add w.cur
    if w.history.len > 50: w.history.delete(0)
    w.cur = path
    ui.redraw = true

proc webPlaceholder(r: Rect; w: WebState) =
  ## What shows where the system's view goes, under it (and while it is
  ## hidden by a menu or a dialog).
  fill(r, th.field)
  box(r, th.edge)
  let t = if w.progress < 100: "Loading... " & $w.progress & "%"
          elif w.title.len > 0: w.title
          else: w.cur
  let line = ellipsize(t, r.w - dp(16))
  text(r.x + (r.w - textWidth(line)) div 2, r.y + (r.h - FontH) div 2, line, th.gray)

proc webFallback(r: Rect; url: string; ev: var WebEvent) =
  ## A page on the web where the kit has no browser engine: the address and
  ## a button that opens it in the browser.
  fill(r, th.field)
  box(r, th.edge)
  let gh = dp(32)
  let lines = wrapLines(url, r.w - dp(24))
  let need = gh + dp(8) + FontH * (2 + min(3, lines.len) + 2) + dp(12) + CtrlH
  var y = r.y + max(dp(6), (r.h - need) div 2)
  if r.h > need:
    image(r.x + (r.w - gh) div 2, y, glyphIcon(retroOr(pxWeb, nfGlobe), th.text, gh))
    y += gh + dp(8)
  let head = "This page is on the web"
  drawLabel(r.x + (r.w - textWidth(head, true)) div 2, y, head, th.text, bold = true)
  y += FontH + dp(4)
  for k, line in lines:
    if k >= 3: break
    text(r.x + (r.w - textWidth(line)) div 2, y, line, th.link)
    y += FontH
  y += dp(4)
  for line in wrapLines("It opens in your browser. (Inside the app on Android.)",
                        r.w - dp(24)):
    text(r.x + (r.w - textWidth(line)) div 2, y, line, th.gray)
    y += FontH
  y += dp(8)
  let label = "&Open in your browser"
  let bw = max(dp(150), labelWidth(label) + dp(24))
  if y + CtrlH <= r.y + r.h:
    pushFrame(rect(r.x + (r.w - bw) div 2, y, bw, CtrlH))
    if button(label, w = bw):
      if openUrl(url): ev.opened = true
    discard popFrame()

proc webView*(url: string; height = -1; key = ""): WebEvent {.discardable.} =
  ## A web page in the window, `height` pixels high (-1: the room left).
  ## `url` is "https://...", a "file://" address or a path, or "html:" and
  ## the HTML itself; giving another address shows that page.
  ##
  ## On Android the page is the system's WebView (the phone's browser
  ## engine: scripts, forms, video), placed over the widget: links are
  ## followed in it, Back (`webGoBack`) returns, other kinds of links (mail,
  ## phone, maps) open their apps. It is hidden while a menu or a dialog of
  ## the app is over it, and when the widget is not drawn. The app needs
  ## the INTERNET permission (`retroapk --permission:INTERNET`).
  ##
  ## Elsewhere local pages are shown by the kit itself (`htmlView`: no
  ## scripts, no network; links to other local pages are followed, others
  ## open in the browser), and pages on the web get a button that opens them
  ## in the browser.
  let r = place(0, if height < 0: remainingH() else: height, fill = true)
  let w = webOf(key)
  if url != w.asked:
    w.asked = url
    w.cur = url
    w.history.setLen(0)
    w.title = ""
    w.progress = if useSystemWebView: 0 else: 100
  w.drawn = ui.frameNo
  if useSystemWebView:
    webPlaceholder(r, w)
    # only the part of it on screen; hidden under the app's menus and dialogs
    let vis = intersect(r, clipRect())
    let covered = vis.w <= 0 or vis.h <= 0 or
                  (ui.dialogTop != 0 and ui.curDialog != ui.dialogTop) or
                  (ui.popup != 0 and intersect(ui.popupRect, vis).w > 0)
    if covered:
      if w.shown:
        discard systemCall("web.hide", key)
        w.shown = false
    else:
      let dr = rect(vis.x * pxScale, vis.y * pxScale, vis.w * pxScale, vis.h * pxScale)
      if not w.shown or dr != w.rect or w.sent != w.cur:
        discard systemCall("web.show", key & "\t" & $dr.x & "\t" & $dr.y & "\t" & $dr.w &
                           "\t" & $dr.h & "\t" & w.cur)
        w.shown = true
        w.rect = dr
        w.sent = w.cur
      # what the page does by itself (links followed, its title, loading)
      if ui.now - w.polledAt >= 250 or ui.now < w.polledAt:
        w.polledAt = ui.now
        let info = systemCall("web.info", key)
        if info != "\0":
          let p = info.split('\t')
          if p.len >= 5:
            if p[0].len > 0: w.cur = p[0]
            w.sent = w.cur
            w.title = p[1]
            w.progress = (try: clamp(parseInt(p[2]), 0, 100) except ValueError: 100)
            w.canBack = p[3] == "1"
            if p[4] == "1": w.backOut = true
      wakeIn(if w.progress < 100: 250 else: 500)
    result.url = w.cur
    result.title = w.title
    result.progress = w.progress
    result.loading = w.progress < 100
    result.canGoBack = w.canBack
    result.back = w.backOut
    w.backOut = false
    ui.lastRect = r
    return
  # the kit shows it itself
  result.progress = 100
  let cur = w.cur
  if cur.startsWith("html:"):
    pushFrame(rect(r.x, r.y, r.w, r.h))
    let ev = htmlView(cur[5 .. ^1], height = r.h, key = "web:" & key)
    discard popFrame()
    result.title = htmlTitle(cur[5 .. ^1])
    if ev.link.len > 0:
      result.link = ev.link
      w.follow(ev.link, result)
  elif isWeb(cur):
    webFallback(r, cur, result)
    result.title = cur
  else:
    let path = localPath(cur)
    if path.len == 0 or not fileExists(path):
      pushFrame(rect(r.x, r.y, r.w, r.h))
      discard htmlView("<h3>This page is not there</h3><p>" & htmlEscape(cur) & "</p>",
                       height = r.h, key = "web:" & key)
      discard popFrame()
    else:
      let text = w.pageText(path)
      let ext = path.splitFile.ext.toLowerAscii
      pushFrame(rect(r.x, r.y, r.w, r.h))
      var ev: HtmlEvent
      if ext in [".md", ".markdown"]:
        let m = markdownView(text, height = r.h, baseDir = path.parentDir,
                             key = "web:" & key & ":" & path)
        ev.link = m.link
        result.title = path.extractFilename
      elif ext in [".html", ".htm", ".xhtml", ".xht", ""]:
        ev = htmlView(text, baseDir = path.parentDir, height = r.h,
                      key = "web:" & key & ":" & path)
        result.title = htmlTitle(text)
        if result.title.len == 0: result.title = path.extractFilename
      else:
        ev = htmlView("<pre>" & htmlEscape(text) & "</pre>", height = r.h,
                      key = "web:" & key & ":" & path)
        result.title = path.extractFilename
      discard popFrame()
      if ev.link.len > 0:
        result.link = ev.link
        w.follow(ev.link, result)
  result.url = w.cur
  result.canGoBack = w.history.len > 0
  ui.lastRect = r
