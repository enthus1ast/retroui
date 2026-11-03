#!/usr/bin/env python3
"""Build Fixedsys Excelsior for the kit: the Windows Fixedsys look (8 x 16
pixel cells) as clean TrueType outlines, and its smoothed HD version.

Maintainers only: users of the library never run this, the outputs are
checked in. Needs Python 3 with fontTools (`pip install fonttools`) and
the public-domain source of Fixedsys Excelsior 3.022 (Darien Valentine's
font, with Kirill Pertsev's additions):

    git clone https://github.com/kika/fixedsys ~/fixedsys
    python3 tools/genfixedsys.py ~/fixedsys

The source (FSEX.ttx) draws every pixel as a square of 10 x 10 units on an
em of 16 pixels, squares overlapping where they meet. This finds the pixels
of every glyph again (a pixel is set when its middle is inside the outline)
and traces them into clean contours -- the way tools/genretro.py makes
Retro Sans and tools/genw98hd.py MS W98 UI HD:

    FixedsysExcelsior.ttf     the pixels, each a square of 100 units; 1200
                              units to the em (12 pixels: at 12 pixels per
                              em -- the kit's 100 % -- a pixel is a screen
                              pixel); the line 13 pixels above the baseline
                              and 3 below (16, as Fixedsys's)
    FixedsysExcelsiorHD.ttf   the same glyphs smoothed for large text and
                              high-resolution screens: twice Scale2x (a
                              one-pixel staircase becomes a diagonal), traced
                              and simplified, the upright and level edges
                              kept on the pixel grid; same advances and
                              metrics

and their .ttf.z (zlib, what the kit carries). The advances (8 pixels, a
few glyphs wider) and the character map are the source's, except:

* the C0 and C1 controls (DOS pictures under control codes) are left out:
  the kit never draws a control character;
* the Arabic (U+0600..U+06FF, U+0750..U+077F, U+08A0..U+08FF and the
  presentation forms, U+FB50..U+FDFF, U+FE70..U+FEFF) is left out:
  the font joins it with OpenType substitutions only (52 of its
  presentation forms have no character of their own) and the kit joins
  Arabic by presentation forms; Arabic comes from GNU Unifont's 8 x 16
  glyphs (Retro Sans Arabic), the same cell;
* the private use area (U+E000..U+F8FF: constructed scripts, symbols) is
  left out: in the kit it is the icons' (the Nerd Fonts symbols), and a
  font's own glyphs there would stand in for icons; it was a third of the
  font;
* the programming ligatures (reached only through the layout tables) and
  the layout and bitmap tables are dropped: the kit draws outlines and
  joins nothing but Arabic.

No bold is made: the kit draws bold Fixedsys as Windows drew a bitmap
font's bold, each glyph a second time one pixel to the right.

Public domain (CC0 1.0 where that is not possible): see
src/retro/fonts/LICENSE-FixedsysExcelsior.txt.
"""
import copy, math, os, sys, zlib
from fontTools.ttLib import TTFont
from fontTools.fontBuilder import FontBuilder
from fontTools.misc.timeTools import timestampFromString
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.pointInsidePen import PointInsidePen
from fontTools.pens.ttGlyphPen import TTGlyphPen

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from genretro import trace, scale2x   # noqa: E402

ROOT = os.path.dirname(HERE)
FONTS = os.path.join(ROOT, "src", "retro", "fonts")

SRC_PX = 10           # the source's pixel, in its units (16 to its em of 160)
UPM = 1200            # 12 pixels to the em
PX = 100              # a pixel, in units
ASC, DESC = 13, 3     # the line: 13 pixels above the baseline, 3 below

LEFT_OUT = [(0x0000, 0x001F), (0x007F, 0x009F), (0x0600, 0x06FF), (0x0750, 0x077F),
            (0x08A0, 0x08FF), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF), (0xE000, 0xF8FF)]

BUILT = "Tue Nov  3 00:00:00 2026"   # (the fonts' date: the same bytes every time)

NOTICE = ("Fixedsys Excelsior 3.022 by Darien Valentine, with additions by Kirill "
          "Pertsev (github.com/kika/fixedsys). Outlines traced again from its pixels "
          "for Retro Nim UI by Sultan Al Isaiee.")
LICENCE = ("The creators of this font have released it to the public domain. Where "
           "that is not possible it is released under the Creative Commons Zero "
           "(CC0 1.0) Universal Public Domain Dedication.")


def left_out(cp):
    return any(a <= cp <= b for a, b in LEFT_OUT)


def pixels(gs, name):
    """The pixels of glyph `name`: (column, row) whose middle is inside its
    outline (nonzero winding), y up, in the source's pixels."""
    pen = DecomposingRecordingPen(gs)
    gs[name].draw(pen)
    polys, cur, curved = [], [], False
    for op, args in pen.value:
        if op == "moveTo":
            cur = [args[0]]
        elif op == "lineTo":
            cur.append(args[0])
        elif op in ("closePath", "endPath"):
            if cur:
                polys.append(cur)
            cur = []
        else:
            curved = True
    if not polys:
        return set()
    xs = [x for p in polys for x, _ in p]
    ys = [y for p in polys for _, y in p]
    i0, i1 = math.floor(min(xs) / SRC_PX) - 1, math.ceil(max(xs) / SRC_PX) + 1
    j0, j1 = math.floor(min(ys) / SRC_PX) - 1, math.ceil(max(ys) / SRC_PX) + 1
    out = set()
    if curved:
        # (a glyph drawn with curves -- one: the open bullet): asked point by point
        for j in range(j0, j1):
            for i in range(i0, i1):
                ip = PointInsidePen(gs, ((i + 0.5) * SRC_PX, (j + 0.5) * SRC_PX))
                gs[name].draw(ip)
                if ip.getResult():
                    out.add((i, j))
        return out
    edges = []
    for p in polys:
        for k in range(len(p)):
            (x1, y1), (x2, y2) = p[k], p[(k + 1) % len(p)]
            if y1 != y2:
                edges.append((x1, y1, x2, y2))
    for j in range(j0, j1):
        cy = (j + 0.5) * SRC_PX
        cross = []
        for x1, y1, x2, y2 in edges:
            if y1 <= cy < y2 or y2 <= cy < y1:
                cross.append((x1 + (cy - y1) * (x2 - x1) / (y2 - y1), 1 if y2 > y1 else -1))
        if not cross:
            continue
        for i in range(i0, i1):
            cx = (i + 0.5) * SRC_PX
            if sum(d for x, d in cross if x > cx):
                out.add((i, j))
    return out


def read_source(folder):
    """{codepoint: (advance in pixels, pixels)}, and the .notdef glyph."""
    src = TTFont()
    src.importXML(os.path.join(folder, "FSEX.ttx"))
    if src["head"].unitsPerEm != 160:
        raise SystemExit("not the 16-pixel Fixedsys Excelsior source")
    cmap = {}
    for t in src["cmap"].tables:
        if t.platformID == 3 or t.platformID == 0:
            for cp, g in t.cmap.items():
                cmap.setdefault(cp, g)
    gs = src.getGlyphSet()
    hmtx = src["hmtx"]
    cache = {}

    def glyph(name):
        if name not in cache:
            adv = hmtx[name][0]
            px = pixels(gs, name)
            if adv % SRC_PX:
                # (the open bullet, drawn with curves, 5.3 pixels wide): a whole
                # cell of 8, the pixels in its middle
                n = max(8, round(adv / SRC_PX / 8) * 8)
                if px:
                    x0 = min(x for x, _ in px)
                    w = max(x for x, _ in px) - x0 + 1
                    px = {(x - x0 + (n - w) // 2, y) for x, y in px}
                cache[name] = (n, frozenset(px))
            else:
                cache[name] = (adv // SRC_PX, frozenset(px))
        return cache[name]

    glyphs = {cp: glyph(g) for cp, g in sorted(cmap.items()) if not left_out(cp)}
    return glyphs, glyph(".notdef")


def outline_pixels(px):
    return [[(float(x), float(y)) for x, y in p] for p in trace(set(px))] if px else []


def rdp(pts, eps):
    """Douglas-Peucker on an open run of points (its ends kept)."""
    if len(pts) < 3:
        return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    dx, dy = x2 - x1, y2 - y1
    L = (dx * dx + dy * dy) ** 0.5
    best, bi = -1, 0
    for k in range(1, len(pts) - 1):
        px, py = pts[k]
        d = (abs(dy * px - dx * py + x2 * y1 - y2 * x1) / L if L
             else ((px - x1) ** 2 + (py - y1) ** 2) ** 0.5)
        if d > best:
            best, bi = d, k
    if best > eps:
        return rdp(pts[:bi + 1], eps)[:-1] + rdp(pts[bi:], eps)
    return [pts[0], pts[-1]]


def smooth_outline(px):
    """The pixel glyph `px` smoothed, in pixels (fractions): as Retro Sans HD
    and MS W98 UI HD (tools/genretro.py's `smooth_outline`: twice Scale2x,
    traced, simplified), but an upright or level edge a pixel and a half
    long or more (what is left of two pixels once Scale2x has cut their
    corners) keeps its ends: the simplifying never moves a stem's edge off
    the pixel grid."""
    if not px:
        return []
    out = []
    for poly in trace(scale2x(scale2x(set(px)))):
        n = len(poly)
        anchor = [False] * n
        for i in range(n):
            (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % n]
            if (x1 == x2 and abs(y2 - y1) >= 6) or (y1 == y2 and abs(x2 - x1) >= 6):
                anchor[i] = anchor[(i + 1) % n] = True
        if not any(anchor):
            # (no long edge: simplified as a whole, split at its farthest points)
            far = max(range(n), key=lambda k: (poly[k][0] - poly[0][0]) ** 2 +
                                              (poly[k][1] - poly[0][1]) ** 2)
            anchor[0] = anchor[far] = True
        idx = [i for i in range(n) if anchor[i]]
        q = []
        for a, b in zip(idx, idx[1:] + [idx[0] + n]):
            run = [poly[k % n] for k in range(a, b + 1)]
            q += rdp(run, 1.05)[:-1]
        if len(q) >= 3:
            out.append([(x / 4.0, y / 4.0) for x, y in q])
    return out


def write(path, family, glyphs, notdef, outline):
    names = {cp: ("space" if cp == 32 else "uni%04X" % cp if cp <= 0xFFFF else "u%05X" % cp)
             for cp in glyphs}
    order = [".notdef"] + [names[cp] for cp in sorted(glyphs)]
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap({cp: names[cp] for cp in glyphs})
    pens, metrics = {}, {}
    # (glyphs drawn alike share an outline: traced once)
    traced = {}
    for gname, (adv, px) in [(".notdef", notdef)] + [(names[cp], glyphs[cp]) for cp in sorted(glyphs)]:
        if px not in traced:
            pen = TTGlyphPen(None)
            for poly in outline(px):
                pts = []
                for x, y in poly:
                    p = (round(x * PX), round(y * PX))
                    if not pts or pts[-1] != p:
                        pts.append(p)
                if len(pts) > 1 and pts[0] == pts[-1]:
                    pts.pop()
                if len(pts) < 3:
                    continue
                pen.moveTo(pts[0])
                for p in pts[1:]:
                    pen.lineTo(p)
                pen.closePath()
            traced[px] = pen.glyph()
        # (a copy each: Cyrillic р and Latin p are drawn alike, but are two glyphs)
        g = pens[gname] = copy.deepcopy(traced[px])
        g.recalcBounds(None)
        metrics[gname] = (adv * PX, g.xMin if g.numberOfContours else 0)
    fb.setupGlyf(pens)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASC * PX, descent=-DESC * PX, lineGap=0)
    style = "Regular"
    fb.setupNameTable({
        "familyName": family, "styleName": style,
        "uniqueFontIdentifier": "Retro Nim UI: %s %s" % (family, style),
        "fullName": family, "psName": family.replace(" ", "") + "-" + style,
        "version": "Version 3.022; Retro Nim UI", "copyright": NOTICE,
        "designer": "Darien Valentine", "licenseDescription": LICENCE,
        "licenseInfoURL": "https://creativecommons.org/publicdomain/zero/1.0/",
    })

    def top(cp):
        return (max(y for _, y in glyphs[cp][1]) + 1) * PX

    fb.setupOS2(sTypoAscender=ASC * PX, sTypoDescender=-DESC * PX, sTypoLineGap=0,
                usWinAscent=ASC * PX, usWinDescent=DESC * PX,
                sxHeight=top(ord("x")), sCapHeight=top(ord("H")),
                xAvgCharWidth=8 * PX, usWeightClass=400, fsSelection=0x40, fsType=0,
                achVendID="RTRO",
                panose={"bFamilyType": 2, "bSerifStyle": 11, "bWeight": 6, "bProportion": 9,
                        "bContrast": 2, "bStrokeVariation": 2, "bArmStyle": 2,
                        "bLetterForm": 2, "bMidline": 2, "bXHeight": 4})
    fb.setupPost(keepGlyphNames=False, isFixedPitch=1)
    fb.setupHead(unitsPerEm=UPM, fontRevision=3.022, created=timestampFromString(BUILT),
                 modified=timestampFromString(BUILT))
    fb.save(path)
    data = open(path, "rb").read()
    open(path + ".z", "wb").write(zlib.compress(data, 9))
    print("%s: %d characters, %d bytes (%d packed)" %
          (os.path.basename(path), len(glyphs), len(data), os.path.getsize(path + ".z")))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    glyphs, notdef = read_source(sys.argv[1])
    write(os.path.join(FONTS, "FixedsysExcelsior.ttf"), "Fixedsys Excelsior", glyphs, notdef,
          outline_pixels)
    write(os.path.join(FONTS, "FixedsysExcelsiorHD.ttf"), "Fixedsys Excelsior HD", glyphs, notdef,
          smooth_outline)


if __name__ == "__main__":
    main()
