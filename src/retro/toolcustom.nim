## Customize Toolbar: the user picks the buttons of an app's tool bar and
## their order, in the dialog of that name Windows 95 brought (and Outlook
## Express used): the buttons there are on the left, the bar's on the
## right, Add, Remove, Move Up, Move Down, Reset, and how labels show.
##
## The app keeps the bar as a list of its own keys (`toolKeys` reads it from
## a setting, `toolKeysText` writes it back) and draws the bar from it:
##
## ```nim
## for k in bar:
##   case k
##   of "-": toolSeparator()
##   of "reply": (if barButton(pxBack, "Reply"): reply())
##   ...
## if customizeToolbar(customizing, bar, choices, defaults, look):
##   prefs.put("toolbar", toolKeysText(bar))
## ```
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/strutils
import core, widgets, business

type
  ToolChoice* = object
    ## A button the bar can have.
    key*: string      ## how the app knows it
    label*: string    ## its name, as the bar and the dialog show it
    glyph*: string    ## its picture: a pixel icon (`pxMail`) or an icon-font glyph

const toolSeparatorKey* = "-"
  ## The key of a separator (a bar may have several).

proc toolKeys*(saved: string; defaults: openArray[string];
               available: openArray[ToolChoice]): seq[string] =
  ## The bar's buttons from a setting (keys joined by commas): keys the app
  ## no longer has are left out; the defaults when there is no setting.
  if saved.strip.len == 0: return @defaults
  for k in saved.split(','):
    let k = k.strip
    if k == toolSeparatorKey:
      result.add k
      continue
    for c in available:
      if c.key == k and k notin result:
        result.add k
        break

proc toolKeysText*(keys: openArray[string]): string =
  ## The bar's buttons as a setting.
  keys.join(",")

var cust: tuple[availSel, barSel: int]

proc choiceOf(available: openArray[ToolChoice]; key: string): ToolChoice =
  for c in available:
    if c.key == key: return c
  ToolChoice(key: key, label: key)

const lookNames = ["Text below the icons", "Text beside the icons", "Icons only (names as tips)"]
const looks = [blTextBelow, blTextBeside, blIconOnly]

proc customizeToolbar*(open: var bool; keys: var seq[string];
                       available: openArray[ToolChoice]; defaults: openArray[string];
                       look: var ButtonLook; title = "Customize Toolbar"): bool =
  ## The Customize Toolbar dialog while `open`. True when it changed the bar
  ## (`keys`, in order) or the look of its labels (`look`).
  if not open: return false
  var unused: seq[ToolChoice]
  unused.add ToolChoice(key: toolSeparatorKey, label: "Separator", glyph: "")
  for c in available:
    if c.key notin keys: unused.add c
  var availNames, barNames: seq[string]
  for c in unused:
    availNames.add(if c.key == toolSeparatorKey: "------ Separator ------" else: c.label)
  for k in keys:
    barNames.add(if k == toolSeparatorKey: "------ Separator ------" else: choiceOf(available, k).label)
  cust.availSel = clamp(cust.availSel, 0, max(0, unused.high))
  cust.barSel = clamp(cust.barSel, 0, max(0, keys.high))
  dialog open, title, dp(560):
    row([-1, dp(104), -1]):
      col:
        label "A&vailable buttons:"
        listbox(availNames, cust.availSel, rows = 11)
      col:
        space(FontH + Gap + dp(40))
        if button("&Add ->", w = dp(104), enabled = unused.len > 0):
          let c = unused[cust.availSel]
          let at = if keys.len == 0: 0 else: cust.barSel + 1
          keys.insert(c.key, at)
          cust.barSel = at
          result = true
        if button("<- &Remove", w = dp(104), enabled = keys.len > 0):
          keys.delete(cust.barSel)
          cust.barSel = max(0, cust.barSel - 1)
          result = true
      col:
        label "&Toolbar buttons:"
        listbox(barNames, cust.barSel, rows = 11)
    row:
      if button("Move &Up", w = dp(104), enabled = cust.barSel > 0 and keys.len > 1):
        swap(keys[cust.barSel], keys[cust.barSel - 1])
        dec cust.barSel
        result = true
      if button("Move &Down", w = dp(104), enabled = cust.barSel < keys.high):
        swap(keys[cust.barSel], keys[cust.barSel + 1])
        inc cust.barSel
        result = true
      if button("R&eset", w = dp(104)):
        keys = @defaults
        cust.barSel = 0
        result = true
    form dp(110):
      field "Text &labels:":
        block:
          var i = max(0, looks.find(look))
          if combo(lookNames, i, w = dp(240)):
            look = looks[i]
            result = true
    row:
      space available() - dp(84)
      if button("Close", isDefault = true, w = dp(84)): open = false
