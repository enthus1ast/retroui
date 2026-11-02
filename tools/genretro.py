#!/usr/bin/env python3
"""Build Retro Sans -- retro's default UI font -- and everything made from it.

Maintainers only: users of the library never run this, the outputs are
checked in. Needs Python 3 with fontTools and brotli
(`pip install fonttools brotli`).

    python3 tools/genretro.py [FOLDER]

FOLDER holds the two MS Sans Serif recreations by "lou" (FontStruct,
CC BY-SA 3.0) as distributed by 98.css: ms_sans_serif.woff2 and
ms_sans_serif_bold.woff2 (default: the Win31 project's copy,
../wieslawsoltes/win31/dist/assets/fonts). The Arabic comes from the GNU
Unifont glyphs already in src/retro/unifontar.nim (tools/genunifont.py).

Retro Sans is lou's pixel font, with the characters it lacks drawn in the
same 1-pixel style: the rest of ASCII in bold, the Latin-1 Supplement,
Latin Extended-A and common punctuation and symbols. Every glyph is a
bitmap on a grid of "bricks"; at 12 pixels per em a brick is one pixel.

Writes, into src/retro/fonts/:

    RetroSans.ttf, RetroSansBold.ttf     the pixel font as TrueType (bricks),
                                         CC BY-SA 3.0 (LICENSE-RetroSans.txt)
    RetroSansArabic.ttf                  Unifont's Arabic as bricks, OFL 1.1
    RetroSansHD*.ttf + .ttf.z            the same, smoothed for large text and
                                         high-resolution screens: one-pixel
                                         staircases become clean diagonals
                                         (the kit reads the .z files)

and src/retro/font.nim: the bitmaps the kit draws at one pixel per brick.

The two licences (CC BY-SA and OFL) cannot be mixed in one font file, so
the Latin and the Arabic are separate fonts that the kit joins at run time.
"""
import os, re, sys, unicodedata, zlib
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "src", "retro", "fonts")
SRC_DEFAULT = os.path.join(os.path.dirname(ROOT), "wieslawsoltes", "win31", "dist",
                           "assets", "fonts")

UPM = 1200            # 12 bricks to the em: at 12 px per em a brick is a pixel
BRICK = 100
ASC, DESC = 12, 4     # the line: 12 bricks above the baseline, 4 below (16)
TOP = ASC - 1         # the highest row a glyph may use (y = 11)
BOTTOM = -2           # the lowest row of the Latin glyphs
PIXEL_H = TOP - BOTTOM + 1   # rows of the bitmaps in font.nim (14)

# ---- reading lou's font -------------------------------------------------------------------------

def read_source(path):
    """{codepoint: (advance, set of (x, y) filled bricks, y up)} of a font
    built from square bricks (2048 / 11 units each)."""
    f = TTFont(path)
    br = f["head"].unitsPerEm / 11.0
    gs = f.getGlyphSet()
    out = {}
    for cp, gname in f.getBestCmap().items():
        pen = RecordingPen()
        gs[gname].draw(pen)
        polys, cur = [], []
        for op, args in pen.value:
            if op == "moveTo":
                cur = [args[0]]
            elif op == "lineTo":
                cur.append(args[0])
            elif op in ("closePath", "endPath"):
                if cur:
                    polys.append([(round(x / br), round(y / br)) for x, y in cur])
                cur = []
            else:
                raise SystemExit("curves in a brick font? " + gname)
        adv = round(f["hmtx"][gname][0] / br)
        px = set()
        if polys:
            xs = [x for p in polys for x, _ in p]
            ys = [y for p in polys for _, y in p]
            for yy in range(min(ys), max(ys)):
                for xx in range(min(xs), max(xs)):
                    cx, cy = xx + 0.5, yy + 0.5
                    wn = 0
                    for p in polys:
                        for i in range(len(p)):
                            (x1, y1), (x2, y2) = p[i], p[(i + 1) % len(p)]
                            if y1 <= cy < y2 and cx < x1 + (cy - y1) * (x2 - x1) / (y2 - y1):
                                wn += 1
                            elif y2 <= cy < y1 and cx < x1 + (cy - y1) * (x2 - x1) / (y2 - y1):
                                wn -= 1
                    if wn:
                        px.add((xx, yy))
        out[cp] = (adv, px)
    return out


def art(top, rows):
    """A bitmap from rows of '#' and '.', the first row at height `top`."""
    px = set()
    for i, r in enumerate(rows):
        for x, c in enumerate(r):
            if c == "#":
                px.add((x, top - i))
    return px


def width_of(px):
    return max(x for x, _ in px) + 1 if px else 0


def glyph(top, rows, adv=None):
    px = art(top, rows)
    return (adv if adv is not None else max(len(r) for r in rows) + 1, px)


def embolden(g):
    adv, px = g
    return (adv + 1, px | {(x + 1, y) for x, y in px})


def shift(px, dx, dy=0):
    return {(x + dx, y + dy) for x, y in px}


def mirror_x(g):
    adv, px = g
    w = width_of(px)
    return (adv, {(w - 1 - x, y) for x, y in px})


def flip_y(g, axis):
    adv, px = g
    return (adv, {(x, axis - y) for x, y in px})

# ---- the characters lou's font lacks, drawn in its style ---------------------------------------

DRAWN = {
    "`": glyph(8, ["#.", ".#"]),
    "|": glyph(8, ["#"] * 11),
    "<": glyph(6, ["...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#"]),
    ">": glyph(6, ["#...", ".#..", "..#.", "...#", "..#.", ".#..", "#..."]),
    "¡": glyph(5, ["#", ".", "#", "#", "#", "#", "#", "#"]),
    "¢": glyph(6, ["..#..", ".###.", "#.#.#", "#.#..", "#.#..", "#.#.#", ".###.", "..#.."]),
    "£": glyph(8, ["..##.", ".#..#", ".#...", ".#...", "###..", ".#...", ".#...", "##..#", "#.##."]),
    "¤": glyph(6, ["#....#", ".####.", ".#..#.", ".#..#.", ".####.", "#....#"]),
    "¥": glyph(8, ["#.....#", ".#...#.", "..#.#..", "...#...", ".#####.", "...#...",
                        ".#####.", "...#...", "...#..."]),
    "¦": glyph(8, ["#", "#", "#", "#", ".", ".", "#", "#", "#", "#", "#"]),
    "§": glyph(8, [".###.", "#...#", "#....", ".###.", "#...#", "#...#", ".###.", "....#",
                        "#...#", ".###."]),
    "¨": glyph(8, ["#.#"]),
    "©": glyph(8, ["..#####..", ".#.....#.", "#..###..#", "#.#...#.#", "#.#.....#",
                        "#.#...#.#", "#..###..#", ".#.....#.", "..#####.."]),
    "ª": glyph(8, [".##.", "...#", ".###", "#..#", ".###", "....", "####"]),
    "«": glyph(5, ["..#..#", ".#..#.", "#..#..", ".#..#.", "..#..#"]),
    "¬": glyph(4, ["#####", "....#", "....#"]),
    "®": glyph(8, ["..#####..", ".#.....#.", "#.####..#", "#.#...#.#", "#.####..#",
                        "#.#..#..#", "#.#...#.#", ".#.....#.", "..#####.."]),
    "¯": glyph(9, ["#####"]),
    "°": glyph(8, [".#.", "#.#", ".#."]),
    "±": glyph(6, ["..#..", "..#..", "#####", "..#..", "..#..", ".....", "#####"]),
    "²": glyph(8, ["##.", "..#", ".#.", "#..", "###"]),
    "³": glyph(8, ["##.", "..#", ".#.", "..#", "##."]),
    "´": glyph(8, [".#", "#."]),
    "µ": glyph(5, ["#...#", "#...#", "#...#", "#...#", "#..##", "###.#", "#....", "#...."]),
    "¶": glyph(8, [".####", "###.#", "###.#", ".##.#", "..#.#", "..#.#", "..#.#", "..#.#",
                        "..#.#"]),
    "·": glyph(3, ["#"]),
    "¸": glyph(-1, [".#", "##"]),
    "¹": glyph(8, [".#", "##", ".#", ".#", ".#"]),
    "º": glyph(8, [".#.", "#.#", "#.#", ".#.", "...", "###"]),
    "»": glyph(5, ["#..#..", ".#..#.", "..#..#", ".#..#.", "#..#.."]),
    "¼": glyph(8, [".#....#..", "##....#..", ".#...#...", ".#...#...", ".#..#..#.",
                        "....#.##.", "...#.#.#.", "...#.####", "..#....#."]),
    "½": glyph(8, [".#....#..", "##....#..", ".#...#...", ".#...#...", ".#..#.##.",
                        "....#...#", "...#...#.", "...#..#..", "..#...###"]),
    "¾": glyph(8, ["##....#..", "..#...#..", ".#...#...", "..#..#...", "##..#..#.",
                        "....#.##.", "...#.#.#.", "...#.####", "..#....#."]),
    "¿": glyph(5, ["..#..", ".....", "..#..", "..#..", ".#...", "#....", "#...#", ".###."]),
    "Æ": glyph(8, ["....#####", "...#.#...", "...#.#...", "..#..#...", "..#..####",
                        ".#####...", ".#...#...", "#....#...", "#....####"]),
    "Ð": glyph(8, [".####..", ".#...#.", ".#....#", ".#....#", "####..#", ".#....#",
                        ".#....#", ".#...#.", ".####.."]),
    "×": glyph(5, ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"]),
    "Ø": glyph(9, ["......#", ".####.#", "#....#.", "#...##.", "#...#.#", "#..#..#",
                        "#.#...#", ".#....#", "#.####.", "#......"], 8),
    "Þ": glyph(8, ["#.....", "#####.", "#....#", "#....#", "#....#", "#####.", "#.....",
                        "#.....", "#....."]),
    "ß": glyph(8, [".##..", "#..#.", "#..#.", "#.#..", "#..#.", "#...#", "#...#", "#...#",
                        "#.##."]),
    "æ": glyph(5, [".###.###.", "....#...#", ".########", "#...#....", "#...#...#",
                        ".###.###."]),
    "ð": glyph(8, [".#.#.", "..#..", ".#.#.", "....#", ".####", "#...#", "#...#", "#...#",
                        ".###."]),
    "÷": glyph(5, ["..#..", ".....", "#####", ".....", "..#.."]),
    "ø": glyph(6, ["....#", ".###.", "#..##", "#.#.#", "#.#.#", "##..#", ".###.", "#...."]),
    "þ": glyph(8, ["#....", "#....", "#....", "####.", "#...#", "#...#", "#...#", "#...#",
                        "####.", "#....", "#...."]),
    "Đ": None,  # = U+00D0
    "đ": glyph(8, ["....#.", "..####", "....#.", ".####.", "#...#.", "#...#.", "#...#.",
                        "#...#.", ".####."], 6),
    "Ħ": glyph(8, [".#....#.", "########", ".#....#.", ".#....#.", ".######.", ".#....#.",
                        ".#....#.", ".#....#.", ".#....#."]),
    "ħ": glyph(8, [".#....", "####..", ".#....", ".#.##.", ".##..#", ".#...#", ".#...#",
                        ".#...#", ".#...#"]),
    "ı": glyph(5, ["#"] * 6),
    "ȷ": glyph(5, ["#"] * 8),     # dotless j (to put accents on)
    "ĸ": glyph(5, ["#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"]),
    "Ł": glyph(8, [".#....", ".#....", ".#....", ".##...", "##....", ".#....", ".#....",
                        ".#....", ".#####"]),
    "ł": glyph(8, [".#.", ".#.", ".#.", ".##", "##.", ".#.", ".#.", ".#.", ".#."]),
    "Ŋ": glyph(8, ["#.###.", "##...#", "#....#", "#....#", "#....#", "#....#", "#....#",
                        "#....#", "#....#", ".....#", "...##."]),
    "ŋ": glyph(5, ["#.##.", "##..#", "#...#", "#...#", "#...#", "#...#", "....#", "..##."]),
    "Œ": glyph(8, [".########", "#....#...", "#....#...", "#....#...", "#....####",
                        "#....#...", "#....#...", "#....#...", ".########"]),
    "œ": glyph(5, [".###.###.", "#...#...#", "#...#####", "#...#....", "#...#...#",
                        ".###.###."]),
    "Ŧ": glyph(8, ["#####", "..#..", "..#..", "..#..", ".###.", "..#..", "..#..", "..#..",
                        "..#.."], 6),
    "ŧ": glyph(7, [".#.", ".#.", ".##", ".#.", "###", ".#.", ".#.", "..#"]),
    "ſ": glyph(8, [".#", "#.", "#.", "#.", "#.", "#.", "#.", "#.", "#."]),
    "€": glyph(8, ["..###.", ".#...#", "#.....", "####..", "#.....", "####..", "#.....",
                        ".#...#", "..###."]),
    "•": glyph(4, ["##", "##"], 4),
    "…": glyph(0, ["#..#..#"], 9),
    "‹": glyph(5, ["..#", ".#.", "#..", ".#.", "..#"]),
    "›": glyph(5, ["#..", ".#.", "..#", ".#.", "#.."]),
    "‚": glyph(0, [".#", "#."]),
    "„": glyph(0, [".#.#", "#.#."]),
    "†": glyph(8, ["..#..", "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."]),
    "‡": glyph(8, ["..#..", "#####", "..#..", "..#..", "..#..", "..#..", "#####", "..#.."]),
    "‰": glyph(8, [".##........", "#..#..#....", ".##..#.....", "....#......", "...#.......",
                        "..#........", ".#..##..##.", "#..#..##..#", "....##..##."]),
    "™": glyph(8, ["###.#...#", ".#..##.##", ".#..#.#.#", ".#..#...#"]),
    "−": glyph(3, ["#####"]),
    "′": glyph(8, ["#", "#"]),
    "″": glyph(8, ["#.#", "#.#"]),
    "←": glyph(6, ["..#....", ".#.....", "#######", ".#.....", "..#...."]),
    "→": glyph(6, ["....#..", ".....#.", "#######", ".....#.", "....#.."]),
    "↑": glyph(8, ["..#..", ".###.", "#.#.#", "..#..", "..#..", "..#..", "..#..", "..#..",
                        "..#.."]),
    "↓": glyph(8, ["..#..", "..#..", "..#..", "..#..", "..#..", "..#..", "#.#.#", ".###.",
                        "..#.."]),
    "✓": glyph(6, ["......#", ".....##", "#...##.", "##.##..", ".###...", "..#...."]),
    "▲": glyph(5, ["...#...", "..###..", ".#####.", "#######"]),
    "▼": glyph(5, ["#######", ".#####.", "..###..", "...#..."]),
    "▶": glyph(6, ["#...", "##..", "###.", "####", "###.", "##..", "#..."]),
    "◀": glyph(6, ["...#", "..##", ".###", "####", ".###", "..##", "...#"]),
    "◦": glyph(5, [".#.", "#.#", ".#."]),
    "▪": glyph(4, ["##", "##"]),
    "≤": glyph(7, ["..#", ".#.", "#..", ".#.", "..#", "...", "###"]),
    "≥": glyph(7, ["#..", ".#.", "..#", ".#.", "#..", "...", "###"]),
    "≠": glyph(6, ["...#.", "#####", "..#..", "#####", ".#..."]),
    "≈": glyph(5, [".##.#", "#..#.", ".....", ".##.#", "#..#."]),
    "∞": glyph(4, [".#...#.", "#.#.#.#", ".#...#."]),
    "№": glyph(8, ["#....#....", "##...#....", "##...#.##.", "#.#..##..#", "#.#..##..#",
                        "#..#.#.##.", "#..#.#....", "#...##.###", "#....#...."]),
}
DRAWN["Đ"] = DRAWN["Ð"]

# accents, by combining mark: (rows top-down, above or below)
ACCENTS = {
    0x0300: (["#.", ".#"], "above"),
    0x0301: ([".#", "#."], "above"),
    0x0302: ([".#.", "#.#"], "above"),
    0x0303: ([".#.#", "#.#."], "above"),
    0x0304: (["###"], "above"),
    0x0306: (["#..#", ".##."], "above"),
    0x0307: (["#"], "above"),
    0x0308: (["#.#"], "above"),
    0x030A: ([".#.", "#.#", ".#."], "above"),
    0x030B: ([".#.#", "#.#."], "above"),
    0x030C: (["#.#", ".#."], "above"),
    0x0327: ([".#", "##"], "below"),
    0x0328: (["#.", ".##"], "below"),
}

TALL_LOWER = set("bdfhklt")   # lowercase letters whose top is above the x-height


def ink_center(px):
    xs = [x for x, _ in px]
    return (min(xs) + max(xs)) / 2.0


def compose(base, marks, cp, faces):
    """An accented letter: the base glyph with each mark drawn over or
    under it, centred on its ink."""
    bch = chr(base)
    is_upper = bch.isupper() or bch.isdigit()
    tall = is_upper or bch in TALL_LOWER
    if bch == "i" and any(ACCENTS.get(m, (0, "below"))[1] == "above" for m in marks):
        base = 0x0131
    if bch == "j" and any(ACCENTS.get(m, (0, "below"))[1] == "above" for m in marks):
        base = 0x0237
    if base not in faces:
        return None
    adv, px = faces[base]
    px = set(px)
    for m in marks:
        if m not in ACCENTS:
            return None
        rows, where = ACCENTS[m]
        rows = list(rows)
        if m == 0x0304 and is_upper:
            rows = ["####"]
        if m == 0x0308 and is_upper and width_of(px) >= 6:
            rows = ["#..#"]
        if m == 0x030A and is_upper:
            rows = [".#.", "#.#", ".#."]
        w = max(len(r) for r in rows)
        if where == "above":
            if m == 0x030A and is_upper:
                top = 11                   # the ring sits on the letter
            elif tall:
                top = 11
            else:
                top = 8
            # letters with a caron on an ascender take it as an apostrophe
            if m == 0x030C and bch in "dLlt":
                ink = max(x for x, _ in px)
                apo = art(8, ["#", "#"]) if bch != "t" else art(7, ["#", "#"])
                px |= shift(apo, ink + 2)
                adv = max(adv, ink + 4)
                continue
            mx = round(ink_center(px) - (w - 1) / 2.0)
            px |= shift(art(top, rows), mx)
        else:
            # cedilla under the middle; ogonek at the right foot; the comma
            # of Latvian letters (U+0327 on g k l n r) below
            if m == 0x0328:
                foot = max(x for x, y in px if y == 0) if any(y == 0 for _, y in px) else 0
                mx = foot - 1
            else:
                mx = round(ink_center(px) - (w - 1) / 2.0)
            if m == 0x0327 and bch in "GKLNRkln":
                rows = [".#", "#."]
            if m == 0x0327 and bch == "g":
                # ģ: the comma goes above, turned
                px |= shift(art(9 if bch.isupper() else 8, ["#.", ".#"]), round(ink_center(px)) - 1)
                continue
            px |= shift(art(-1, rows), mx)
        if min(x for x, _ in px) < 0:
            dx = -min(x for x, _ in px)
            px = shift(px, dx)
            adv += dx
        adv = max(adv, width_of(px) + 1)
    return (adv, px)


def build_face(src, bold, regular_full=None):
    """All the glyphs of one weight: lou's, the drawn ones, the composed
    ones (bold: the regular drawn ones made bold)."""
    faces = dict(src)
    # characters lou's font has that we replace or leave out
    for cp in list(faces):
        if cp == 0x25FC:
            del faces[cp]
    if bold:
        # what the bold lacks: the regular glyph made bold
        for cp, g in regular_full.items():
            if cp not in faces:
                faces[cp] = embolden(g) if g[1] else g
        return faces
    for ch, g in DRAWN.items():
        faces[ord(ch)] = g
    wanted = list(range(0x00C0, 0x0100)) + list(range(0x0100, 0x0180))
    for cp in wanted:
        if cp in faces:
            continue
        d = unicodedata.decomposition(chr(cp))
        if not d or d.startswith("<"):
            continue
        parts = [int(p, 16) for p in d.split()]
        base, marks = parts[0], parts[1:]
        # a base that is itself decomposed (none in these blocks) is skipped
        g = compose(base, marks, cp, faces)
        if g:
            faces[cp] = g
    # composites of two letters
    def join(a, b, gap=0):
        ga, gb = faces[a], faces[b]
        return (ga[0] + gb[0] + gap, ga[1] | shift(gb[1], ga[0] + gap))
    faces[0x0132] = join(ord("I"), ord("J"))
    faces[0x0133] = join(ord("i"), ord("j"))
    faces[0x0149] = join(0x2019, ord("n"))
    l = faces[ord("L")]
    faces[0x013F] = (l[0], l[1] | {(3, 4)})
    faces[0x0140] = (4, faces[ord("l")][1] | {(2, 4)})
    return faces


def compose_bold_accents(faces_b, faces_r):
    """Accented bold letters: the bold base with the accent made bold."""
    for cp in list(range(0x00C0, 0x0100)) + list(range(0x0100, 0x0180)):
        d = unicodedata.decomposition(chr(cp))
        if cp in faces_b and cp < 0x00C0:
            continue
        if not d or d.startswith("<"):
            continue
        parts = [int(p, 16) for p in d.split()]
        base, marks = parts[0], parts[1:]
        if base not in faces_b or base == cp:
            continue
        # the regular accent's pixels (the composed regular glyph minus its
        # base), made bold, over the bold base
        r = faces_r.get(cp)
        rb = faces_r.get(base if not (chr(base) == "i" and cp not in (0x012E,)) else 0x0131)
        if r is None:
            continue
        b0 = base
        if chr(base) == "i" and any(m in ACCENTS and ACCENTS[m][1] == "above" for m in marks):
            b0 = 0x0131
        if chr(base) == "j" and any(m in ACCENTS and ACCENTS[m][1] == "above" for m in marks):
            b0 = 0x0237
        rb = faces_r[b0]
        # find where the regular base sat inside the composed glyph (it may
        # have been moved right to make room)
        best = None
        for dx in range(0, 4):
            if shift(rb[1], dx) <= r[1]:
                best = dx
                break
        if best is None:
            continue
        acc = r[1] - shift(rb[1], best)
        bb = faces_b[b0] if b0 in faces_b else embolden(faces_r[b0])
        # centre the accent over the bold base
        if acc:
            acx = ink_center(acc) - best
            off = round(ink_center(bb[1]) - ink_center(rb[1]))
            acc_b = shift(acc, -best + off)
            acc_b = acc_b | shift(acc_b, 1)
            if any(y >= 6 for _, y in acc):
                pass
        else:
            acc_b = set()
        px = bb[1] | acc_b
        mn = min(x for x, _ in px)
        if mn < 0:
            px = shift(px, -mn)
        faces_b[cp] = (max(bb[0], width_of(px) + 1), px)
    # the composites again, in bold
    faces_b[0x0132] = (faces_b[ord("I")][0] + faces_b[ord("J")][0],
                       faces_b[ord("I")][1] | shift(faces_b[ord("J")][1], faces_b[ord("I")][0]))
    faces_b[0x0133] = (faces_b[ord("i")][0] + faces_b[ord("j")][0],
                       faces_b[ord("i")][1] | shift(faces_b[ord("j")][1], faces_b[ord("i")][0]))
    return faces_b

# ---- Unifont's Arabic ----------------------------------------------------------------------------

def read_unifont():
    src = open(os.path.join(ROOT, "src", "retro", "unifontar.nim")).read()
    def arr(name):
        return re.search(name + r"\*: array\[UniCount, \w+\] = \[(.*?)\]", src).group(1)
    cps = [int(x.replace("u16", "")) for x in arr("uniCps").split(", ")]
    offs = [int(x.replace("u16", "")) for x in arr("uniOffs").split(", ")]
    wide = [x == "true" for x in arr("uniWide").split(", ")]
    blob = bytes(int(h, 16) for h in re.findall(r"\\x([0-9a-f]{2})",
                                                re.search(r'uniBits\* = "(.*?)"', src).group(1)))
    out = {}
    for cp, o, w in zip(cps, offs, wide):
        nb = 2 if w else 1
        px = set()
        for r in range(16):
            v = 0
            for b in range(nb):
                v = (v << 8) | blob[o + r * nb + b]
            for c in range(nb * 8):
                if v >> (nb * 8 - 1 - c) & 1:
                    px.add((c, 10 - r))         # Unifont's row 10 sits on the baseline
        adv = 16 if w else 8
        if unicodedata.combining(chr(cp)) or cp in (0x0670,):
            # a mark: no advance, drawn over the letter before it
            px = shift(px, -8 if not w else -16)
            adv = 0
        out[cp] = (adv, px)
    return out

# ---- outlines ----------------------------------------------------------------------------------

def trace(cells):
    """The outlines of a set of filled grid cells (y up), as closed
    polygons with the filled side on the right (TrueType's clockwise outer
    contours)."""
    edges = {}
    for (x, y) in cells:
        if (x, y + 1) not in cells:
            edges.setdefault((x, y + 1), []).append((x + 1, y + 1))
        if (x + 1, y) not in cells:
            edges.setdefault((x + 1, y + 1), []).append((x + 1, y))
        if (x, y - 1) not in cells:
            edges.setdefault((x + 1, y), []).append((x, y))
        if (x - 1, y) not in cells:
            edges.setdefault((x, y), []).append((x, y + 1))
    polys = []
    while edges:
        start = next(iter(edges))
        poly = [start]
        cur = start
        prev_dir = None
        while True:
            outs = edges[cur]
            if len(outs) == 1:
                nxt = outs.pop()
            else:
                # two ways on (cells touching at a corner): turn right
                def turn(p):
                    d = (p[0] - cur[0], p[1] - cur[1])
                    if prev_dir is None:
                        return 0
                    cross = prev_dir[0] * d[1] - prev_dir[1] * d[0]
                    return cross   # negative: a right turn (y up)
                outs.sort(key=turn)
                nxt = outs.pop(0)
            if not outs:
                del edges[cur]
            prev_dir = (nxt[0] - cur[0], nxt[1] - cur[1])
            cur = nxt
            if cur == start:
                break
            poly.append(cur)
        polys.append(simplify_collinear(poly))
    return polys


def simplify_collinear(poly):
    out = []
    n = len(poly)
    for i in range(n):
        a, b, c = poly[i - 1], poly[i], poly[(i + 1) % n]
        if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) != 0:
            out.append(b)
    return out


def scale2x(cells):
    """EPX / Scale2x: twice the size, diagonal steps filled in."""
    out = set()
    if not cells:
        return out
    xs = [x for x, _ in cells]
    ys = [y for _, y in cells]
    for y in range(min(ys) - 1, max(ys) + 2):
        for x in range(min(xs) - 1, max(xs) + 2):
            P = (x, y) in cells
            A = (x, y + 1) in cells   # above
            B = (x + 1, y) in cells   # right
            C = (x - 1, y) in cells   # left
            D = (x, y - 1) in cells   # below
            # quadrants: top-left, top-right, bottom-left, bottom-right
            tl = A if (C == A and C != D and A != B) else P
            tr = B if (A == B and A != C and B != D) else P
            bl = C if (D == C and D != B and C != A) else P
            br = D if (B == D and B != A and D != C) else P
            if tl: out.add((2 * x, 2 * y + 1))
            if tr: out.add((2 * x + 1, 2 * y + 1))
            if bl: out.add((2 * x, 2 * y))
            if br: out.add((2 * x + 1, 2 * y))
    return out


def dp_simplify(poly, eps):
    """Douglas-Peucker on a closed polygon, keeping its corners."""
    n = len(poly)
    if n < 4:
        return poly
    # split at the two points farthest apart
    i0 = 0
    far = max(range(n), key=lambda k: (poly[k][0] - poly[0][0]) ** 2 + (poly[k][1] - poly[0][1]) ** 2)
    def rdp(pts):
        if len(pts) < 3:
            return pts
        (x1, y1), (x2, y2) = pts[0], pts[-1]
        dx, dy = x2 - x1, y2 - y1
        L = (dx * dx + dy * dy) ** 0.5
        best, bi = -1, 0
        for k in range(1, len(pts) - 1):
            px, py = pts[k]
            d = abs(dy * px - dx * py + x2 * y1 - y2 * x1) / L if L else ((px - x1) ** 2 + (py - y1) ** 2) ** 0.5
            if d > best:
                best, bi = d, k
        if best > eps:
            return rdp(pts[:bi + 1])[:-1] + rdp(pts[bi:])
        return [pts[0], pts[-1]]
    a = poly[i0:far + 1]
    b = poly[far:] + poly[:i0 + 1]
    return rdp(a)[:-1] + rdp(b)[:-1]


def smooth_outline(px):
    """The pixel glyph `px` as smooth polygons, in bricks (fractions)."""
    if not px:
        return []
    up = scale2x(scale2x(px))
    polys = trace(up)
    out = []
    for p in polys:
        q = dp_simplify(p, 1.05)
        if len(q) >= 3:
            out.append([(x / 4.0, y / 4.0) for x, y in q])
    return out


def brick_outline(px):
    return [[(float(x), float(y)) for x, y in p] for p in trace(px)] if px else []

# ---- writing fonts ----------------------------------------------------------------------------

def write_ttf(path, family, style, glyphs, outline, licence, desc, asc=ASC, dsc=DESC):
    """glyphs: {cp: (adv in bricks, pixels)}."""
    order = [".notdef", "space"] if 32 in glyphs else [".notdef"]
    names = {}
    for cp in sorted(glyphs):
        if cp == 32:
            names[cp] = "space"
            continue
        n = "uni%04X" % cp
        names[cp] = n
        order.append(n)
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap({cp: names[cp] for cp in glyphs})
    pen_glyphs, metrics = {}, {}
    # .notdef: an empty box
    pen = TTGlyphPen(None)
    box = [(0, 0), (0, 900), (500, 900), (500, 0)]
    inner = [(100, 100), (400, 100), (400, 800), (100, 800)]
    for poly in (box, inner):
        pen.moveTo(poly[0])
        for p in poly[1:]:
            pen.lineTo(p)
        pen.closePath()
    pen_glyphs[".notdef"] = pen.glyph()
    metrics[".notdef"] = (600, 0)
    for cp, (adv, px) in glyphs.items():
        pen = TTGlyphPen(None)
        polys = outline(px)
        for poly in polys:
            pts = [(round(x * BRICK), round(y * BRICK)) for x, y in poly]
            pen.moveTo(pts[0])
            for p in pts[1:]:
                pen.lineTo(p)
            pen.closePath()
        g = pen.glyph()
        pen_glyphs[names[cp]] = g
        xs = [x for poly in polys for x, _ in poly]
        lsb = round(min(xs) * BRICK) if xs else 0
        metrics[names[cp]] = (adv * BRICK, lsb)
    fb.setupGlyf(pen_glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=asc * BRICK, descent=-dsc * BRICK)
    fb.setupNameTable({
        "familyName": family, "styleName": style,
        "uniqueFontIdentifier": "Retro Nim UI: %s %s" % (family, style),
        "fullName": "%s %s" % (family, style), "psName": (family + "-" + style).replace(" ", ""),
        "version": "Version 1.0", "copyright": desc, "licenseDescription": licence,
        "designer": "lou (MS Sans Serif FontStructions); Retro Nim UI" if "Arabic" not in family
                    else "GNU Unifont contributors; Retro Nim UI",
    })
    fb.setupOS2(sTypoAscender=asc * BRICK, sTypoDescender=-dsc * BRICK, sTypoLineGap=0,
                usWinAscent=asc * BRICK, usWinDescent=dsc * BRICK,
                sxHeight=6 * BRICK, sCapHeight=9 * BRICK,
                usWeightClass=700 if style == "Bold" else 400,
                fsSelection=0x20 if style == "Bold" else 0x40)
    fb.setupPost()
    fb.setupHead(unitsPerEm=UPM)
    if style == "Bold":
        fb.font["head"].macStyle = 1
    fb.save(path)
    data = open(path, "rb").read()
    return len(data)


def pack(path):
    data = open(path, "rb").read()
    open(path + ".z", "wb").write(zlib.compress(data, 9))
    return os.path.getsize(path + ".z")

# ---- font.nim ---------------------------------------------------------------------------------

HD_ARABIC = [(0x0600, 0x06FF), (0xFB50, 0xFBFF), (0xFE70, 0xFEFF)]


def write_nim(reg, bold, arabic_cps):
    cps = sorted(c for c in set(reg) | set(bold) if c >= 32)
    lines = ["# Generated by tools/genretro.py -- do not edit.",
             "# Glyphs: Retro Sans (lou's MS Sans Serif FontStructions with retro's",
             "# additions; CC BY-SA 3.0, see fonts/LICENSE-RetroSans.txt), as the",
             "# bitmaps drawn at one pixel per brick (12 pixels per em).",
             "## Retro Sans, the built-in pixel font: each glyph's code point, advance",
             "## and rows of pixels, regular and bold (and the code points of the Arabic",
             "## HD face).", "",
             "const",
             "  PixelH* = %d          ## rows of a glyph" % PIXEL_H,
             "  PixelAscent* = %d     ## rows above the baseline" % (TOP + 1),
             "  GlyphCount* = %d" % len(cps), "",
             "type GlyphInfo* = tuple[adv, xoff, w: int8]", "",
             "const glyphCps*: array[GlyphCount, uint16] = ["]
    lines.append("  " + ", ".join(("%du16" % c) if i == 0 else str(c) for i, c in enumerate(cps)) + "]")
    lines.append("")
    lines.append("const")
    lines.append("  ArabicHdCount* = %d" % len(arabic_cps))
    lines.append("  arabicHdCps*: array[ArabicHdCount, uint16] = [  ## glyph i + 1 of the Arabic HD face")
    lines.append("    " + ", ".join(("%du16" % c) if i == 0 else str(c) for i, c in enumerate(arabic_cps)) + "]")
    lines.append("")
    for tag, face in (("reg", reg), ("bold", bold)):
        info, rows = [], []
        for c in cps:
            g = face.get(c)
            if g is None:
                g = embolden(reg[c]) if tag == "bold" and c in reg else (reg.get(c) or (0, set()))
            adv, px = g
            if px:
                x0 = min(x for x, _ in px)
                w = width_of(px) - x0
                if w > 16:
                    raise SystemExit("too wide: U+%04X" % c)
            else:
                x0, w = 0, 0
            info.append("(%d'i8, %d'i8, %d'i8)" % (adv, x0, w))
            rr = []
            for row in range(PIXEL_H):
                y = TOP - row
                v = 0
                for x, yy in px:
                    if yy == y:
                        v |= 1 << (15 - (x - x0))
                rr.append(v)
            for x, yy in px:
                if yy > TOP or yy < BOTTOM:
                    raise SystemExit("out of the rows: U+%04X y=%d" % (c, yy))
            ch = chr(c) if c not in (92,) and unicodedata.category(chr(c))[0] != "Z" else "U+%04X" % c
            rows.append("  " + ", ".join("0x%04x'u16" % v for v in rr) + ",  # " + ch)
        lines.append("const %sInfo*: array[GlyphCount, GlyphInfo] = [" % tag)
        lines.append(",\n".join("  " + s for s in info) + "]")
        lines.append("")
        lines.append("const %sRows*: array[GlyphCount * PixelH, uint16] = [" % tag)
        lines.append("\n".join(rows))
        lines.append("]")
        lines.append("")
    open(os.path.join(ROOT, "src", "retro", "font.nim"), "w").write("\n".join(lines))
    return len(cps)


LICENCE_CC = ("Retro Sans: lou's MS Sans Serif FontStructions "
              "(https://fontstruct.com/fontstructions/show/1384746 and /1384862), "
              "licensed CC BY-SA 3.0 (https://creativecommons.org/licenses/by-sa/3.0/); "
              "modified by Retro Nim UI. This font is licensed CC BY-SA 3.0 too.")
LICENCE_OFL = ("Retro Sans Arabic: the Arabic glyphs of GNU Unifont, used and modified under "
               "the SIL Open Font License 1.1 (https://openfontlicense.org).")


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else SRC_DEFAULT
    reg_src = read_source(os.path.join(src, "ms_sans_serif.woff2"))
    bold_src = read_source(os.path.join(src, "ms_sans_serif_bold.woff2"))
    reg = build_face(reg_src, False)
    bold = build_face(bold_src, True, reg)
    bold = compose_bold_accents(bold, reg)
    # the same characters in both weights, in the same order: glyph i + 1 of
    # either face is entry i of glyphCps in font.nim
    for cp in reg:
        if cp not in bold:
            bold[cp] = embolden(reg[cp]) if reg[cp][1] else reg[cp]
    for cp in bold:
        if cp not in reg:
            reg[cp] = bold[cp]
    # lou's space is 2 bricks: words ran together in menus and labels; 3,
    # as Windows' own 8-point MS Sans Serif had
    for face in (reg, bold):
        face[0x20] = (3, set())
        face[0xA0] = (3, set())
    arabic = read_unifont()
    arabic_hd = {cp: g for cp, g in arabic.items() if any(a <= cp <= b for a, b in HD_ARABIC)}
    os.makedirs(OUT, exist_ok=True)
    sizes = {}
    sizes["RetroSans.ttf"] = write_ttf(os.path.join(OUT, "RetroSans.ttf"), "Retro Sans", "Regular",
                                       reg, brick_outline, LICENCE_CC, LICENCE_CC)
    sizes["RetroSansBold.ttf"] = write_ttf(os.path.join(OUT, "RetroSansBold.ttf"), "Retro Sans",
                                           "Bold", bold, brick_outline, LICENCE_CC, LICENCE_CC)
    sizes["RetroSansArabic.ttf"] = write_ttf(os.path.join(OUT, "RetroSansArabic.ttf"),
                                             "Retro Sans Arabic", "Regular", arabic, brick_outline,
                                             LICENCE_OFL, LICENCE_OFL, dsc=5)
    for name, family, style, g, lic in (
            ("RetroSansHD.ttf", "Retro Sans HD", "Regular", reg, LICENCE_CC),
            ("RetroSansHDBold.ttf", "Retro Sans HD", "Bold", bold, LICENCE_CC),
            ("RetroSansArabicHD.ttf", "Retro Sans Arabic HD", "Regular", arabic_hd, LICENCE_OFL)):
        p = os.path.join(OUT, name)
        sizes[name] = write_ttf(p, family, style, g, smooth_outline, lic, lic,
                                dsc=5 if "Arabic" in family else DESC)
        sizes[name + ".z"] = pack(p)
    n = write_nim(reg, bold, sorted(arabic_hd))
    for k, v in sizes.items():
        print("%-28s %7d bytes" % (k, v))
    print(n, "bitmap glyphs in font.nim")


if __name__ == "__main__":
    main()
