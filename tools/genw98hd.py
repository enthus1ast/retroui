#!/usr/bin/env python3
"""Build MS W98 UI HD: MS W98 UI with its staircases made smooth, for
high-resolution screens (2x and more), where the pixel font itself would be
drawn as doubled pixels.

Maintainers only: users of the library never run this, the outputs are
checked in. Needs Python 3 with fontTools (`pip install fonttools`).

    python3 tools/genw98hd.py

Reads src/retro/fonts/MSW98UI.ttf and MSW98UIBold.ttf (outlines of the
Windows 98 bitmaps, 11 pixels to the em), finds the pixels of every glyph,
and traces them again the way tools/genretro.py makes Retro Sans HD: twice
Scale2x (one-pixel steps become diagonals), the edges traced, straight runs
simplified. The advances, the character map and the line metrics are the
font's own, so text takes exactly the room it took before.

Writes src/retro/fonts/MSW98UIHD.ttf, MSW98UIHDBold.ttf and their .ttf.z.
The fonts carry the same notice as MS W98 UI (NOTICE-MSW98UI.txt): no
licence is known for them.
"""
import os, sys, zlib, math
from fontTools.ttLib import TTFont
from fontTools.pens.pointInsidePen import PointInsidePen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.boundsPen import BoundsPen

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from genretro import smooth_outline   # noqa: E402

ROOT = os.path.dirname(HERE)
FONTS = os.path.join(ROOT, "src", "retro", "fonts")
GRID = 11


def cells_of(glyphset, name, cell):
    """The pixels of glyph `name`: cells whose middle is inside its outline."""
    g = glyphset[name]
    bp = BoundsPen(glyphset)
    g.draw(bp)
    if bp.bounds is None:
        return set()
    x0, y0, x1, y1 = bp.bounds
    out = set()
    for j in range(math.floor(y0 / cell) - 1, math.ceil(y1 / cell) + 1):
        for i in range(math.floor(x0 / cell) - 1, math.ceil(x1 / cell) + 1):
            pen = PointInsidePen(glyphset, ((i + 0.5) * cell, (j + 0.5) * cell))
            g.draw(pen)
            if pen.getResult():
                out.add((i, j))
    return out


def build(src, dst, family):
    f = TTFont(os.path.join(FONTS, src))
    upm = f["head"].unitsPerEm
    cell = upm / GRID
    gs = f.getGlyphSet()
    glyf = f["glyf"]
    order = f.getGlyphOrder()
    new = {}
    for name in order:
        cells = cells_of(gs, name, cell)
        pen = TTGlyphPen(None)
        for poly in smooth_outline(cells):
            pts = [(round(x * cell), round(y * cell)) for x, y in poly]
            # (points that rounding made the same are dropped)
            clean = []
            for p in pts:
                if not clean or clean[-1] != p:
                    clean.append(p)
            if len(clean) > 1 and clean[0] == clean[-1]:
                clean.pop()
            if len(clean) < 3:
                continue
            pen.moveTo(clean[0])
            for p in clean[1:]:
                pen.lineTo(p)
            pen.closePath()
        new[name] = pen.glyph()
    for name, g in new.items():
        glyf[name] = g
    if "DSIG" in f:
        del f["DSIG"]
    for rec in f["name"].names:
        if rec.nameID in (1, 3, 4, 16):
            old = rec.toUnicode()
            rec.string = old.replace("MS W98 UI", family) if "MS W98 UI" in old else family
        elif rec.nameID == 6:
            rec.string = family.replace(" ", "") + ("-Bold" if "Bold" in src else "-Regular")
    f["head"].checkSumAdjustment = 0
    out = os.path.join(FONTS, dst)
    f.save(out)
    data = open(out, "rb").read()
    open(out + ".z", "wb").write(zlib.compress(data, 9))
    print(dst, len(data), "bytes,", len(new), "glyphs")


def main():
    build("MSW98UI.ttf", "MSW98UIHD.ttf", "MS W98 UI HD")
    build("MSW98UIBold.ttf", "MSW98UIHDBold.ttf", "MS W98 UI HD")


if __name__ == "__main__":
    main()
