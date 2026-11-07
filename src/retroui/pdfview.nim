## Reading PDF documents (and Illustrator's .ai, which are PDFs inside):
## `pdfView` shows the pages one under another, as a reader does, drawn on
## worker threads at the size they are shown -- a 900-page manual opens at
## once and scrolls without waiting. `addPdfPreviews` lets the file lists,
## previews and Open dialogs show their first pages.
##
## .. code-block:: nim
##   import retroui, retroui/pdfview
##   addPdfPreviews()
##   let doc = openPdfView("manual.pdf")      # (raises PdfError, IOError)
##   app "Reader", 900, 700:
##     row:
##       if button("-"): doc.zoomOut()
##       if button("+"): doc.zoomIn()
##       label "Page " & $(doc.page + 1) & " of " & $doc.count
##     pdfView(doc)

import std/[tables, math, os, times]
import gfx, core, widgets, background, pdfread
import uirelays/input

export pdfread.PdfError

template th: untyped = ui.theme

# ---- the pages, drawn (on any thread) ---------------------------------------------------------------

var lastPdf {.threadvar.}: tuple[path: string; stamp: int64; size: int64; f: PdfFile]

proc pdfPage*(path: string; page, maxW, maxH: int): Bitmap {.gcsafe.} =
  ## Page `page` (from 0) of the PDF `path`, drawn to fit `maxW` x `maxH`;
  ## nil when it cannot be. Each thread keeps the last document it read,
  ## so the pages of one document do not read it again.
  {.cast(gcsafe).}:
    try:
      let stamp = getLastModificationTime(path).toUnix
      let size = getFileSize(path)
      if lastPdf.f == nil or lastPdf.path != path or lastPdf.stamp != stamp or lastPdf.size != size:
        lastPdf.f = nil
        lastPdf = (path, stamp, size, openPdf(readFile(path)))
      let f = lastPdf.f
      if page < 0 or page >= f.pageCount: return nil
      let (w, h) = f.pageSize(page)
      if w <= 0 or h <= 0: return nil
      let dpi = 72 * min(maxW.float / w, maxH.float / h)
      result = f.renderPage(page, max(4.0, dpi), maxPixels = max(16, maxW * maxH))
    except CatchableError, Defect:
      result = nil

proc pdfPreview*(path: string; maxW = 512; maxH = 512): Bitmap =
  ## The first page of a PDF (or an .ai) drawn to fit `maxW` x `maxH`; nil
  ## when it is not one.
  pdfPage(path, 0, maxW, maxH)

proc addPdfPreviews*() =
  ## Teaches the file widgets (lists, previews, Open dialogs) to show the
  ## first pages of PDF and Illustrator files, and `pageAsync` to draw
  ## their pages.
  addPictureReader([".pdf", ".ai"], proc (path: string; maxW, maxH: int): Bitmap {.nimcall, gcsafe.} =
    pdfPage(path, 0, maxW, maxH))
  addPageReader([".pdf", ".ai"], proc (path: string; page, maxW, maxH: int): Bitmap {.nimcall, gcsafe.} =
    pdfPage(path, page, maxW, maxH))

# ---- the view --------------------------------------------------------------------------------------

type
  PdfView* = ref object
    ## A PDF being read (`openPdfView`).
    path*: string                  ## the file
    count*: int                    ## how many pages
    title*, author*: string        ## from the document's information
    page*: int                     ## the page in view (from 0)
    zoom*: float                   ## 0: the pages as wide as the view; else
                                   ## screen pixels per point x 72/96 (1.0:
                                   ## actual size, 100 %)
    sizes: seq[tuple[w, h: float]] # the pages, in points
    pics: Table[int, Bitmap]       # pages drawn ...
    picW: Table[int, int]          # ... this wide (device pixels)
    asked: Table[int, int]         # pages being drawn, how wide
    failed: Table[int, bool]
    group: int
    goTo: int                      # a page to scroll to (-1: none)
    shownZoom: float               # (the scale of the last frame)
    lastScale: float

  PdfViewEvent* = object
    ## What happened in a `pdfView` this frame.
    pageChanged*: bool             ## another page came into view (`page`)
    zoomChanged*: bool             ## the wheel with Ctrl, + or -, a double click

var nextGroup = 0x5DF000

proc openPdfView*(path: string): PdfView =
  ## Opens the PDF `path` to read (its pages are drawn when shown). Raises
  ## `PdfError` when it is not one or is damaged past reading, `IOError`
  ## when it cannot be read.
  let f = openPdf(readFile(path))
  result = PdfView(path: path, count: f.pageCount, goTo: -1)
  inc nextGroup
  result.group = nextGroup
  for i in 0 ..< f.pageCount:
    let (w, h) = f.pageSize(i)
    result.sizes.add (max(1.0, w), max(1.0, h))
  let inf = f.info
  result.title = inf.title
  result.author = inf.author

proc closePdfView*(v: PdfView) =
  ## Stops drawing its pages and lets them go.
  if v == nil: return
  cancelTasks(tkPage, v.group)
  v.pics.clear()
  v.asked.clear()

proc pageSizePt*(v: PdfView; i: int): tuple[w, h: float] =
  ## The size of page `i` in points (72 an inch).
  if i in 0 ..< v.sizes.len: v.sizes[i] else: (612.0, 792.0)

proc goToPage*(v: PdfView; i: int) =
  ## Scrolls page `i` (from 0) into view, at its top.
  v.goTo = clamp(i, 0, max(0, v.count - 1))

proc zoomPercent*(v: PdfView): int =
  ## The size shown, in per cent of the actual size (fitted too).
  int(round(v.shownZoom * 100))

proc setZoom*(v: PdfView; z: float) =
  ## `z` times the actual size (0: as wide as the view), keeping the page
  ## in view.
  v.zoom = if z <= 0: 0.0 else: clamp(z, 0.1, 8.0)
  v.goTo = v.page

proc zoomIn*(v: PdfView) =
  ## A step larger (as Ctrl + the wheel).
  v.setZoom(max(0.1, (if v.zoom <= 0: v.shownZoom else: v.zoom)) * 1.25)

proc zoomOut*(v: PdfView) =
  ## A step smaller.
  v.setZoom(max(0.1, (if v.zoom <= 0: v.shownZoom else: v.zoom)) * 0.8)

proc fitWidth*(v: PdfView) =
  ## The pages as wide as the view.
  v.setZoom(0)

proc ask(v: PdfView; i, w, h, priority: int) =
  v.asked[i] = w
  let vv = v
  discard pageAsync(v.path, i, w, h, priority = priority, group = v.group,
    onDone = proc (r: var TaskResult) =
      let pg = r.page
      if vv.asked.getOrDefault(pg, -1) != w: return   # (asked again since)
      vv.asked.del pg
      if r.cancelled: return
      let b = toBitmap(move r)
      if b == nil: vv.failed[pg] = true
      else:
        vv.pics[pg] = b
        vv.picW[pg] = w
      ui.redraw = true)

proc pdfView*(v: PdfView; height = -1; w = 0): PdfViewEvent {.discardable.} =
  ## The pages of `v` one under another on a gray ground, each drawn at the
  ## size it is shown (while it is being drawn, the one drawn before, or a
  ## blank page). The wheel and the scroll bars (a finger) move along;
  ## Ctrl + the wheel zooms; a double click (a double tap) goes between as
  ## wide as the view and twice that. With the focus: Page Up / Down,
  ## Space, Home, End, the arrows, + / - / 0 (as wide as the view).
  let r = place(if w > 0: w else: 0, if height < 0: remainingH() else: height, fill = w <= 0)
  let id = idOf("pdfview:" & v.path & ":" & $v.group)
  let hit = interact(id, r, focusable = true)
  var st = state(id)
  fill(r, th.shadow)
  sunken(r)
  ui.lastId = id
  ui.lastRect = r
  if v.count == 0:
    let s = "This document has no pages."
    text(r.x + (r.w - textWidth(s)) div 2, r.y + r.h div 2 - FontH div 2, s, th.window)
    return
  let gap = dp(10)
  let inner = rect(r.x + 1, r.y + 1, r.w - 2 - SbW, r.h - 2)
  var widest = 1.0
  for s in v.sizes: widest = max(widest, s.w)
  # the scale: logical pixels per point
  # (as wide as the view -- but not past 125 %: a wide window and a narrow page)
  let fitScale = clamp((inner.w - 2 * gap).float / widest, 0.02, 1.25 * 96 / 72)
  let scale = if v.zoom <= 0: fitScale else: v.zoom * 96 / 72
  if v.lastScale > 0 and abs(scale - v.lastScale) > 1e-6 and v.goTo < 0 and v.zoom <= 0:
    v.goTo = v.page                  # (the window was resized: stay on the page)
  v.lastScale = scale
  v.shownZoom = scale * 72 / 96
  # where each page is
  var tops = newSeq[int](v.count + 1)
  var y0 = gap
  for i in 0 ..< v.count:
    tops[i] = y0
    y0 += int(round(v.sizes[i].h * scale)) + gap
  tops[v.count] = y0
  let contentH = y0
  let contentW = int(round(widest * scale)) + 2 * gap
  let hasHBar = contentW > inner.w
  let viewH = inner.h - (if hasHBar: SbW else: 0)
  let maxY = max(0, contentH - viewH)
  let maxX = max(0, contentW - inner.w)
  var y = clamp(st.scrollY, 0, maxY)
  var x = clamp(st.scrollX, 0, maxX)
  if v.goTo >= 0:
    y = clamp(tops[clamp(v.goTo, 0, v.count - 1)] - gap, 0, maxY)
    v.goTo = -1
    st.scrollY = y
  let wasZoom = v.zoom
  if canInput():
    let area = rect(inner.x, inner.y, inner.w, viewH)
    if ui.wheel != 0 and not ui.wheelUsed and mouseIn(r) and CtrlPressed in ui.mods:
      ui.wheelUsed = true
      if ui.wheel > 0: v.zoomIn() else: v.zoomOut()
    scrollWheel(id, y, maxY, area, 3 * ItemH)
    scrollWheel(id + 3, x, maxX, area, 3 * ItemH, sideways = true)
    if ui.panX != 0 and maxX > 0 and mouseIn(r) and not ui.panUsed:
      x = clamp(x + ui.panX, 0, maxX)
    scrollPan(id, y, maxY, area)
    if hit.clicked and ui.clicks >= 2:
      v.setZoom(if v.zoom <= 0: v.shownZoom * 2 else: 0)
    if hit.focused and not ui.keyUsed and ui.key != KeyNone:
      var used = true
      case ui.key
      of KeyPageDown, KeySpace: y = min(maxY, y + viewH - ItemH)
      of KeyPageUp: y = max(0, y - viewH + ItemH)
      of KeyDown: y = min(maxY, y + dp(40))
      of KeyUp: y = max(0, y - dp(40))
      of KeyHome: y = 0
      of KeyEnd: y = maxY
      of KeyRight:
        if maxX > 0: x = min(maxX, x + dp(40)) else: v.goToPage(v.page + 1)
      of KeyLeft:
        if maxX > 0: x = max(0, x - dp(40)) else: v.goToPage(v.page - 1)
      of KeyPlus, KeyEqual: v.zoomIn()
      of KeyMinus: v.zoomOut()
      of Key0: v.fitWidth()
      else: used = false
      if used:
        ui.keyUsed = true
        scrollStop(id)
  scrollTick(id, y, maxY)
  if v.zoom != wasZoom: result.zoomChanged = true
  # the page in view: the last whose top is above a third of the view
  var cur = 0
  let mark = y + viewH div 3
  var lo = 0
  var hi = v.count - 1
  while lo <= hi:
    let mid = (lo + hi) div 2
    if tops[mid] <= mark:
      cur = mid
      lo = mid + 1
    else: hi = mid - 1
  if y >= maxY and maxY > 0: cur = v.count - 1
  if cur != v.page:
    v.page = cur
    result.pageChanged = true
  # the pages in view (and one either side, drawn ahead)
  var first = cur
  while first > 0 and tops[first] > y: dec first
  var last = cur
  while last < v.count - 1 and tops[last + 1] < y + viewH: inc last
  let s = float(pxScale)
  pushClip(rect(inner.x, inner.y, inner.w, viewH))
  let ox = inner.x - x + max(0, (inner.w - contentW) div 2)
  for i in first .. last:
    let pw = int(round(v.sizes[i].w * scale))
    let ph = int(round(v.sizes[i].h * scale))
    let pr = rect(ox + gap + (int(round(widest * scale)) - pw) div 2, inner.y + tops[i] - y, pw, ph)
    fill(rect(pr.x + dp(3), pr.y + dp(3), pr.w, pr.h), th.frame)
    fill(pr, color(255, 255, 255))
    let b = v.pics.getOrDefault(i)
    if b != nil:
      drawBitmap(pr, b)
    elif v.failed.getOrDefault(i):
      let t = "This page cannot be shown."
      text(pr.x + (pr.w - textWidth(t)) div 2, pr.y + pr.h div 2, t, th.gray)
    else:
      let t = "Page " & $(i + 1) & "..."
      text(pr.x + (pr.w - textWidth(t)) div 2, pr.y + pr.h div 2, t, th.gray)
  popClip()
  # draw what is in view at the size shown; the next pages ahead
  let capW = 4096
  for i in max(0, first - 1) .. min(v.count - 1, last + 1):
    if v.failed.getOrDefault(i): continue
    let pw = int(round(v.sizes[i].w * scale * s))
    let ph = int(round(v.sizes[i].h * scale * s))
    let k = min(1.0, min(capW.float / max(1, pw).float, 24e6 / max(1.0, pw.float * ph.float)))
    let need = max(8, int(pw.float * k))
    let needH = max(8, int(ph.float * k))
    let have = v.picW.getOrDefault(i, 0)
    let pending = v.asked.getOrDefault(i, 0)
    if (have == 0 or abs(have - need) > need div 6) and pending != need:
      v.ask(i, need, needH, if i in first .. last: 6 else: 4)
  # let go of pages far away
  var gone: seq[int]
  for i in v.pics.keys:
    if i < first - 4 or i > last + 4: gone.add i
  for i in gone:
    v.pics.del i
    v.picW.del i
  # the scroll bars
  scrollBarFor(id + 9, id, rect(r.x + r.w - SbW - 1, r.y + 1, SbW, viewH), true, y,
               maxY, max(ItemH, viewH - ItemH), ItemH)
  if hasHBar:
    scrollBarFor(id + 10, id + 3, rect(inner.x, inner.y + viewH, inner.w, SbW), false, x,
                 maxX, max(ItemH, inner.w - ItemH), ItemH)
    fill(rect(r.x + r.w - SbW - 1, inner.y + viewH, SbW, SbW), th.face)
  if y != st.scrollY or x != st.scrollX:
    st.scrollY = y
    st.scrollX = x
    ui.redraw = true
  state(id) = st
  if hit.focused: focusDots(inset(r, 2))
  if accessOn:
    accessNode(arImage, v.path.extractFilename, id = id, r = r, help = "PDF")
  ui.lastId = id
  ui.lastRect = r
